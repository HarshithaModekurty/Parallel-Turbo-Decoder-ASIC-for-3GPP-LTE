# `siso_maxlogmap` Cell-Level Structural Guide

This guide explains the deeper exported diagrams in this folder. These figures
are not gate-level synthesis netlists. They are **RTL-faithful structural
isomorphisms** of the arithmetic used in the updated
[`rtl/siso_maxlogmap.vhd`](../../../rtl/siso_maxlogmap.vhd).

The focus here is the repeated adder, mux, compare-select, and storage
structures inside three datapath units:

1. radix-4 gamma metric generation
2. radix-4 ACS recursion
3. LLR extraction

## 1. Gamma Metric Unit

Reference RTL:
- `branch_metrics(...)`
- `pair_gamma_from_branches(...)`

The updated SISO computes one radix-4 gamma vector per trellis pair by:

1. computing `g0[0..3]` for the even step
2. computing `g1[0..3]` for the odd step
3. combining `g0` and `g1` into `gamma[0..15]`

### 1.1 One Branch-Metric Cell

One branch-metric cell corresponds to one call to:

- `branch_metrics(l_sys, l_par, l_apri)`

Structural view per cell:
- polarity generation for `+/-sys`, `+/-apri`, `+/-par`
- `2` first-stage `10-bit` adders for the positive and negative systematic-apriori sums
- `4` second-stage `10-bit` add/sub blocks for the four branch hypotheses
- `4` arithmetic right shifts by `1`
- `4` branch outputs written into local `g0` or `g1` storage

There are **2 identical branch-metric cells per trellis pair**:
- one for the even trellis step
- one for the odd trellis step

### 1.2 Pair-Gamma Combiner

`pair_gamma_from_branches(...)` creates the `16` radix-4 gamma values:

- `gamma[idx] = g0[*] + g1[*]`

Structural view:
- **16 total `10-bit` adders**
- fixed wiring from the selected `g0` and `g1` branches
- packed write into one `gamma_local_mem(work_local_idx)` word

So the total pair-level gamma generator contains:
- **2 branch-metric cells**
- **12 total branch-metric add/sub blocks**
- **8 total shifters**
- **16 total pair-gamma adders**

## 2. Radix-4 ACS Unit

Reference RTL:
- `acs_step(state_in, gamma_in, is_backward)`

This is the shared recursion block reused for:
- forward alpha update
- dummy backward beta seeding
- local backward beta stepping

### 2.1 One ACS State Cell

For one destination/output state, the ACS cell contains:

- `4` path-metric adders
- one `max4` tree
- the `max4` tree is structurally `3` compare-select cells

So one state cell is:
- **4 adders**
- **3 compare-select units**

### 2.2 Full Radix-4 ACS Array

The constituent code has `8` trellis states, so the full ACS array is:

- **8 parallel state cells**
- **32 path-metric adders total**
- **24 compare-select units total**

The diagrams show:
- state cell `0`
- state cell `1`
- `...`
- state cell `7`

This is intentional; the omitted middle cells are the same structure replicated
for the remaining states.

### 2.3 Mux/Register Interpretation

At the RTL level:
- `alpha_work` and `beta_work` are the state-vector registers
- the ACS output is written back into the active state register bank on each step
- `is_backward` changes the source/destination interpretation of the state paths

So the cell-level diagram shows:
- input state register bank `8 x 10-bit`
- mode-dependent source selection / path wiring
- parallel state-cell array
- output state register bank `8 x 10-bit`

## 3. LLR Extraction Unit

Reference RTL:
- `extract_pair_precomp(...)`

The updated extractor no longer recomputes branch metrics. It consumes:

- `alpha_in[0..7]`
- `beta_in[0..7]`
- precomputed `g0[0..3]`
- precomputed `g1[0..3]`
- cached `sys_even/sys_odd`
- cached `apri_even/apri_odd`

### 3.1 Alpha-Mid Reconstruction

`alpha_mid` is reconstructed by evaluating the first trellis step only.

Structure:
- **16 adders total**
- grouped into **8 cells**
- each cell performs:
  - `2` candidate adders
  - `1` max2 compare-select

So `alpha_mid` is:
- **8 repeated cells**
- **16 adders**
- **8 compare-select units**

### 3.2 Beta-Mid Reconstruction

`beta_mid` is reconstructed similarly for the second trellis step.

Structure:
- **8 repeated cells**
- **16 adders**
- **8 compare-select units**

### 3.3 Even-Bit Decision Network

The even-bit posterior uses:

- `alpha_in + g0 + beta_mid`

Structure:
- **16 metric generators total**
- each metric generator is a **2-adder chain**
- outputs split into:
  - `8` candidates for `u0 = 0`
  - `8` candidates for `u0 = 1`
- each side uses one `max8` tree
- one `max8` tree is structurally `7` compare-select cells

So the even-bit decision network is:
- **32 adders**
- **14 compare-select units**

### 3.4 Odd-Bit Decision Network

The odd-bit posterior uses:

- `alpha_mid + g1 + beta_in`

It has the same structure as the even-bit network:
- **32 adders**
- **14 compare-select units**

### 3.5 Final Posterior/Extrinsic Arithmetic

After the max trees:

- `2` posterior subtractors:
  - `post_even = max1_u0 - max0_u0`
  - `post_odd  = max1_u1 - max0_u1`
- `4` extrinsic subtractors:
  - subtract systematic term
  - subtract apriori term
- `2` posterior saturation blocks
- `2` `scale_ext` blocks

Each `scale_ext` block is:
- left shift by `3`
- left shift by `1`
- plus original term
- **2 adders**
- arithmetic right shift by `4`
- saturation to `ext_llr_t`

So the final arithmetic stage is:
- **6 subtractors**
- **4 adders inside the two scaling blocks**
- **2 posterior saturators**
- **2 extrinsic saturators**

## 4. Why Registers/Memories Appear In The Diagrams

These deep figures show register or storage boundaries where the RTL really has
state or cached words:

- `alpha_work` / `beta_work`
- `alpha_local_mem`
- `g0_local_mem`
- `g1_local_mem`
- `gamma_local_mem`
- cached `sys/apri` local memories

They do **not** try to explode each `10-bit` word into bit-slices. The level of
detail is:
- arithmetic block
- mux / compare-select block
- register or memory word bank

That is the right depth for an isomorphic architecture figure of this RTL.
