# Turbo Decoder Architecture and Theory Write-Up

Date: 2026-03-20
Project: Parallel-Turbo-Decoder-ASIC-for-3GPP-LTE
Worktree: `codex-worktree`
Branch: `codex-branch`

## 1. What Is Implemented

This branch now implements the paper-facing architecture at these levels:
- scalar external top-level interface
- internal `N = 8` segmented parallel datapath for `K % 8 = 0`
- folded-memory style storage
- recursive QPP addressing
- explicit master/slave Batcher routing for the interleaved half-iteration
- half-iteration controller semantics through `n_half_iter`
- radix-4 SISO processing
- windowed `M = 30` trellis-step scheduling inside the active SISO
- dummy-recursion scheduling inside the active SISO

This branch does not yet claim full LTE-standard boundary fidelity because the public RTL interface still does not feed overlap-window or tail-symbol data into the active decoder datapath.

## 2. Top-Level Dataflow

### External view

`turbo_decoder_top.vhd` stays scalar:
- load one frame with `in_valid`, `in_idx`, `l_sys_in`, `l_par1_in`, `l_par2_in`
- launch with `start`
- stop by `n_half_iter`
- emit final posterior LLRs through `out_valid`, `out_idx`, `l_post`

This keeps the testbench and vector tooling simple while the internal architecture stays parallel.

### Internal view

Internally the frame is split into `N = 8` equal segments:
- `S = K / 8`
- segment `seg = floor(k / S)`
- local row `row = k mod S`
- folded row `pair_row = floor(row / 2)`

The top level keeps separate even/odd folded memories for:
- systematic LLRs
- parity-1 LLRs
- parity-2 LLRs
- extrinsic LLRs
- final posterior LLRs

Two half-iterations alternate:

### Half-iteration 1

Each SISO sees:
- original-order systematic samples
- original-order parity-1 samples
- original-order a-priori information from the previous half-iteration

Outputs:
- original-order extrinsic values
- original-order posterior values if this is the final half-iteration

### Half-iteration 2

Each SISO sees:
- interleaved systematic samples
- interleaved parity-2 samples
- interleaved a-priori values obtained through QPP + Batcher routing

Outputs:
- extrinsic values are deinterleaved back into natural folded order
- final posterior values are also deinterleaved into natural/original order if this is the final half-iteration

## 3. QPP and Master-Slave Batcher

### QPP

The scalar QPP formula is:

`pi(k) = (f1*k + f2*k^2) mod K`

The hardware uses the recursive form because it is add/mod based:
- `pi(k+1) = pi(k) + delta(k) mod K`
- `delta(k+1) = delta(k) + b mod K`

with:
- `pi(0) = 0`
- `delta(0) = f1 + f2`
- `b = 2*f2`

`qpp_parallel_scheduler.vhd` evaluates the 8 addresses associated with one folded row group and checks that they land in the same folded row base. That is the maximally-vectorizable property used by the paper.

### Master-slave Batcher

The interleaver network is split into two logical parts:

1. Master sorter:
- sort the 8 QPP addresses
- record which lane each sorted address came from

2. Slave permutation:
- read a folded natural-order row word
- permute it into BCJR-lane order for phase-2 reads
- apply the reverse permutation for deinterleaving writeback

So the Batcher network is not just shuffling data randomly. It is the hardware bridge between:
- address order preferred by the memories
- lane order preferred by the 8 SISOs

## 4. Fixed-Point Contract

The active fixed-point sizes are:
- `chan_llr_t`: 5-bit signed
- `ext_llr_t`: 6-bit signed
- `post_llr_t`: 7-bit signed
- `metric_t`: 10-bit signed

Why these matter:
- the channel values are intentionally tight because turbo-decoder ASICs are quantized aggressively
- extrinsic values need slightly more range than raw channel observations
- posterior output gets one extra bit so the final sign is less likely to clip too early
- state metrics accumulate many branch terms, so they need the widest representation

The package also provides:
- modulo add
- modulo subtract
- modulo max
- modulo max4

These are used by the radix-4 ACS and the LLR extraction logic.

Extrinsic scaling is `0.6875`, implemented as shift/add:
- `0.6875 = 11/16`
- hardware form: `(8*x + 2*x + x) >> 4`

## 5. SISO Theory

This is the core of the decoder.

### 5.1 What a SISO decoder does

One constituent decoder receives:
- systematic evidence
- one parity stream
- a-priori information from the other constituent decoder

It must estimate the posterior LLR of each information bit.

The BCJR logic uses three metric families:
- `alpha`: forward state metric
- `gamma`: branch metric
- `beta`: backward state metric

For a given bit position, the posterior LLR is:
- best path metric among all paths where the bit is `1`
- minus the best path metric among all paths where the bit is `0`

The extrinsic output is the posterior stripped of:
- the systematic term
- the incoming a-priori term

That extrinsic value is what gets passed to the other constituent decoder.

### 5.2 Why radix-4 exists

Radix-2 processes one trellis step per cycle.

Radix-4 groups two trellis steps into one hardware step:
- even bit `u0`
- odd bit `u1`

That means one cycle evaluates the two-step path:
- start state `s(k)`
- intermediate state `s(k+1)`
- end state `s(k+2)`

Because each bit can be 0 or 1, there are four input-pair combinations:
- `00`
- `01`
- `10`
- `11`

For each start state, the hardware evaluates all four admissible two-step paths.
This is why radix-4 roughly doubles trellis throughput.

### 5.3 Branch metrics

The single-step branch metric uses:
- systematic LLR
- parity LLR
- a-priori LLR

In the active RTL, `siso_maxlogmap.vhd` computes the four possibilities for one trellis step internally:
- `u=0,p=0`
- `u=0,p=1`
- `u=1,p=0`
- `u=1,p=1`

That same active SISO then combines one even-step and one odd-step branch set into a 16-entry two-step gamma vector.

So one radix-4 gamma vector represents every valid local two-step path cost for one pair of bits.

### 5.4 Why windowing is needed

If BCJR is run over the whole segment at once, the decoder must keep very large alpha or beta histories.
The paper avoids that by processing windows of length `M = 30` trellis steps.

In the active RTL:
- one window = `30` trellis steps
- one radix-4 cycle = `2` trellis steps
- so one full window = `15` pair cycles

This is exactly the paper’s `M = 30` radix-4 operating point.

### 5.5 What dummy recursion means here

Windowed BCJR has a boundary problem:
- the backward recursion of window `m` needs an initial beta vector at the end of window `m`
- but that value depends on what happens in later trellis steps

The paper solves this with dummy recursion.

In the active RTL the rule is:
- to decode window `m`, run a dummy backward recursion over window `m + 1`
- the beta vector that appears at the start of window `m + 1` is used as the seed for the real backward recursion of window `m`

So the next window is not decoded during dummy backward.
It is used to generate the boundary condition needed by the current window.

There is also one dummy forward warm-up at segment start.
Because the current public interface does not provide overlap-window data, the active implementation keeps the first-window boundary assumption simple:
- segment-start state metrics are initialized uniformly
- the dummy-forward pass is retained as architectural warm-up overhead
- later forward seeds are still computed and stored window by window

That is the main practical assumption in the current implementation.

### 5.6 How the active SISO is scheduled

The active SISO still exposes the same segment-level ports to the top level:
- load all pair samples for one segment
- then process the segment internally

Inside the SISO the schedule is:

1. Load phase:
- store segment-local `sys`, `par`, and `apri` pairs

2. Dummy forward warm-up:
- run one warm-up recursion over the first window

3. Forward-seed phase:
- walk windows from start to end
- compute and store only the alpha seed at the start of each window

4. Per-window decode phase, from last window to first:
- if this is not the last window, run dummy backward on window `m + 1`
- use that beta seed for window `m`
- recompute only the local alpha/gamma history of window `m`
- run the real backward recursion of window `m`
- emit one pair of posterior/extrinsic outputs per cycle while sweeping backward

This means the active SISO no longer stores full-segment alpha history.
It stores:
- full-segment input pairs
- one alpha seed per window
- one local window alpha/gamma buffer during active decoding

That is much closer to the paper than the old full-segment backward sweep.

### 5.7 Why odd-step reconstruction is needed

A radix-4 recursion naturally lands on even trellis indices:
- `k`
- `k + 2`
- `k + 4`

But the decoder must still compute an LLR for the odd bit inside the pair.

So for one pair the SISO reconstructs the missing intermediate step:
- `alpha_mid` is built from `alpha(k)` and the even-step branch metrics
- `beta_mid` is built from `beta(k+2)` and the odd-step branch metrics

Then:
- even-bit LLR uses `alpha(k)`, even-step branch metrics, and `beta_mid`
- odd-bit LLR uses `alpha_mid`, odd-step branch metrics, and `beta(k+2)`

This is the reason the LLR path still needs radix-2 branch metrics even inside a radix-4 decoder.

### 5.8 What the extractor is doing mathematically

For the even bit:
- enumerate all valid first-step transitions
- group them by `u0 = 0` or `u0 = 1`
- for each transition, combine:
  - start alpha
  - first-step branch metric
  - reconstructed `beta_mid`
- take the max metric for `u0 = 0`
- take the max metric for `u0 = 1`
- subtract them to form the posterior LLR

For the odd bit:
- enumerate all valid second-step transitions
- group them by `u1 = 0` or `u1 = 1`
- for each transition, combine:
  - reconstructed `alpha_mid`
  - second-step branch metric
  - end beta
- take the two maxima and subtract them

Then:
- `post = max(u=1) - max(u=0)`
- `ext = post - sys - apri`
- `ext` is scaled by `0.6875`

That is the exact logic the active RTL now uses.

## 6. What the Verification Now Means

There are two reference paths in the tooling:

1. Floating reference:
- conventional max-log software reference
- useful for qualitative behavior and BER intuition

2. Fixed-point reference:
- mirrors the active RTL scheduling and quantization
- now exact for the checked `K = 40`, `n_half_iter = 11` regression
- not yet exact for the larger checked points `K = 3200` and `K = 6144`

So if the fixed-point comparison reports zero mismatches, it means:
- the active RTL and the active model agree exactly for that tested point

It does not mean:
- the current boundary assumptions are the final LTE-standard ones
- the floating reference must match
- all larger block sizes are already covered

## 7. Current Assumptions

The active implementation makes these explicit assumptions:

1. `K` must be divisible by 8.
2. Max-log-MAP is used.
3. The public RTL interface does not carry overlap-window data.
4. The public RTL interface does not carry explicit tail-symbol LLR streams.
5. Segment/window boundary state metrics therefore use internal uniform assumptions.
6. Outer frame boundaries now use terminated-state seeds, but the public RTL interface still does not carry explicit overlap-window or tail-symbol inputs for interior boundaries.
7. The Python tooling now includes the full LTE QPP table.

## 8. Bottom Line

The branch is now past the earlier "radix-4 direction only" stage.

What is materially true now:
- the top level is folded-memory and Batcher-based
- the active SISO is windowed with `M = 30`
- dummy-recursion scheduling is active
- odd-step reconstruction is explicit
- the checked fixed-point model and RTL agree exactly for the `K = 40` default regression

What is still left for a fully standards-faithful hardware story:
- explicit overlap/tail boundary delivery
- larger-block exact fixed-point closure
