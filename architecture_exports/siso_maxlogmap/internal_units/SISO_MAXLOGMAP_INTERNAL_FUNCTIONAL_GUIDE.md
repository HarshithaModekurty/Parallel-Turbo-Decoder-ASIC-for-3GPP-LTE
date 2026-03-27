# `siso_maxlogmap` Internal Functional Unit Guide

This note decomposes the datapath of [`rtl/siso_maxlogmap.vhd`](../../../rtl/siso_maxlogmap.vhd) into its arithmetic and trellis-processing units.

The goal here is narrower than the top-level SISO guide:
- not memory scheduling
- not top-level FSM sequencing
- specifically the **internal functional units** inside the datapath

Relevant fixed-point contract from [`rtl/turbo_pkg.vhd`](../../../rtl/turbo_pkg.vhd):

- `chan_llr_t`: 5-bit signed
- `ext_llr_t`: 6-bit signed
- `post_llr_t`: 7-bit signed
- `metric_t`: 10-bit signed
- `C_NUM_STATES = 8`
- radix-4 gamma size = `16`

## 1. Functional Units

The datapath can be split into these functional units:

1. single-bit branch metric unit
2. radix-4 pair gamma combiner
3. radix-4 ACS unit
4. alpha-seed pack / unpack unit
5. alpha-mid reconstruction unit
6. beta-mid reconstruction unit
7. even-bit max tree
8. odd-bit max tree
9. posterior subtraction unit
10. extrinsic subtraction unit
11. extrinsic scaling / saturation unit

## 2. Branch Metric Unit

The single-bit BMU is implemented by `branch_metrics(...)`.

Inputs:
- `l_sys`
- `l_par`
- `l_apri`

Internal arithmetic:

```text
s_sys = resize_chan_to_metric(l_sys)
s_par = resize_chan_to_metric(l_par)
s_ap  = resize_ext_to_metric(l_apri)

g(0) = ( s_sys + s_ap + s_par) >> 1
g(1) = ( s_sys + s_ap - s_par) >> 1
g(2) = (-s_sys - s_ap + s_par) >> 1
g(3) = (-s_sys - s_ap - s_par) >> 1
```

Architecturally this means:
- two sign-inversion paths
- two adder stages
- one arithmetic right shift
- four outputs

So this is not just a lookup table. It is a small arithmetic BMU.

## 3. Pair Gamma Combiner

The radix-4 gamma generator is `pair_gamma(...)`.

Inputs:
- even-bit BMU output `g0[0..3]`
- odd-bit BMU output `g1[0..3]`

Output:
- `gamma_v[0..15]`

Internal arithmetic:

```text
gamma(idx) = g0(u0,p0) + g1(u1,p1)
idx = 8*u0 + 4*p0 + 2*u1 + p1
```

So the pair-gamma unit is:
- `2 x` single-bit BMU
- plus a `16`-entry combine/add network

## 4. Radix-4 ACS Unit

The shared ACS is `acs_step(...)`.

Inputs:
- `state_in[0..7]`
- `gamma_in[0..15]`
- direction flag `is_backward`

### Forward ACS

For each previous state:
- enumerate the `4` two-bit input combinations
- compute the end state
- compute the radix-4 gamma index
- form candidate metric:

```text
candidate = state_in(prev_s) + gamma_in(path_g)
```

For each end state:
- retain the maximum candidate with `mod_max`

So the forward ACS is:
- trellis next-state generation
- candidate metric generation
- 8 destination-state max-selection networks

### Backward ACS

For each current state:
- enumerate the `4` outgoing two-bit combinations
- compute successor state
- compute radix-4 gamma index
- form `4` candidate metrics
- reduce them with `mod_max4`

So the backward ACS is:
- trellis successor generation
- `4` candidate metrics per state
- `max4` tree per state

### Important architectural fact

The RTL uses one **shared ACS structure** for both directions.
The difference is:
- the state index used on the `state_in` side
- whether maxima are accumulated by end state or by current state

## 5. Alpha-Seed Pack / Unpack Units

These are the small format-conversion blocks:

- `pack_state_metric(...)`
  - packs `8 x metric_t` into one `80`-bit alpha-seed word
- `unpack_state_metric(...)`
  - unpacks BRAM read data back into `state_metric_t`

These are not heavy arithmetic blocks, but they are explicit datapath units bridging:
- ACS forward seed generation
- alpha-seed BRAM
- local forward replay

## 6. LLR Extraction Unit

`extract_pair(...)` is the deepest arithmetic block in the SISO.

It contains six subfunctions.

### 6.1 Even/Odd BMUs

First it recomputes:
- `g0 = branch_metrics(sys_even, par_even, apri_even)`
- `g1 = branch_metrics(sys_odd, par_odd, apri_odd)`

### 6.2 Alpha-Mid Reconstruction

For each start state and even-bit input:

```text
metric = alpha_in(start_s) + g0(idx)
alpha_mid(mid_s) = max(alpha_mid(mid_s), metric)
```

This reconstructs the best metric at the middle trellis stage.

### 6.3 Beta-Mid Reconstruction

For each middle-state candidate:

```text
metric = g1(idx) + beta_in(end_s)
beta_mid(start_s) = max(beta_mid(start_s), metric)
```

This reconstructs the middle-stage backward metrics.

### 6.4 Even-Bit Max Tree

The even posterior uses:

```text
metric = alpha_in(start_s) + g0(idx) + beta_mid(mid_s)
```

Then two maxima are built:
- `max0_u0`: best metric for even input bit `0`
- `max1_u0`: best metric for even input bit `1`

### 6.5 Odd-Bit Max Tree

The odd posterior uses:

```text
metric = alpha_mid(mid_s) + g1(idx) + beta_in(end_s)
```

Then two maxima are built:
- `max0_u1`: best metric for odd input bit `0`
- `max1_u1`: best metric for odd input bit `1`

### 6.6 Posterior And Extrinsic Arithmetic

Posterior metrics:

```text
post0_v = max1_u0 - max0_u0
post1_v = max1_u1 - max0_u1
```

Extrinsic metrics:

```text
ext0_v = post0_v - sys_even - apri_even
ext1_v = post1_v - sys_odd  - apri_odd
```

Output formatting:

```text
post_even = metric_to_post_sat(post0_v)
post_odd  = metric_to_post_sat(post1_v)
ext_even  = scale_ext(ext0_v)
ext_odd   = scale_ext(ext1_v)
```

## 7. Extrinsic Scaling Unit

`scale_ext(...)` in [`rtl/turbo_pkg.vhd`](../../../rtl/turbo_pkg.vhd) implements:

```text
scaled = (8*x + 2*x + 1*x) >> 4 = 11*x/16
```

Then it saturates to 6-bit `ext_llr_t`.

Architecturally this unit is:
- one widened input register/resize
- two shift-left paths
- adder tree
- right shift by 4
- saturation to `[-32, 31]`

## 8. Modulo Arithmetic Units

The datapath repeatedly uses:
- `mod_add`
- `mod_sub`
- `mod_max`
- `mod_max4`

In this RTL they are fixed-width two's-complement arithmetic units, not explicit subtract-the-offset normalization blocks.

Architecturally:
- `mod_add` and `mod_sub` are fixed-width add/sub blocks
- `mod_max` is compare-by-sign-of-difference
- `mod_max4` is a tree of three `mod_max` blocks

## 9. How The Units Connect

During `LOCAL_FWD`:

```text
frame pair
  -> branch_metrics even/odd
  -> pair_gamma
  -> ACS forward
  -> alpha_local / gamma_local buffers
```

During `LOCAL_BWD`:

```text
alpha_local + beta_work + local observations
  -> extract_pair
    -> alpha_mid and beta_mid reconstruction
    -> even/odd max trees
    -> posterior subtractors
    -> extrinsic subtractors
    -> scale_ext
```

So the true arithmetic core of the SISO datapath is:

```text
BMU -> pair_gamma -> ACS
and
BMU -> alpha_mid/beta_mid -> max trees -> subtract -> scale_ext
```

## 10. Diagram Files In This Folder

- [`SISO_MAXLOGMAP_FUNCTIONAL_UNITS.svg`](SISO_MAXLOGMAP_FUNCTIONAL_UNITS.svg)
  - overall internal functional datapath
- [`SISO_BRANCH_AND_GAMMA_UNIT.svg`](SISO_BRANCH_AND_GAMMA_UNIT.svg)
  - BMU and radix-4 gamma combiner
- [`SISO_RADIX4_ACS_UNIT.svg`](SISO_RADIX4_ACS_UNIT.svg)
  - shared forward/backward ACS structure
- [`SISO_LLR_EXTRACTION_UNIT.svg`](SISO_LLR_EXTRACTION_UNIT.svg)
  - `extract_pair` arithmetic decomposition
