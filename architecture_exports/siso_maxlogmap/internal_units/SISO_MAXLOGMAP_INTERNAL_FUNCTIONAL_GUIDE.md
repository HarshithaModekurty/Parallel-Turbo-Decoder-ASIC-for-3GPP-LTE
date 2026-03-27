# `siso_maxlogmap` Internal Functional Unit Guide

This note decomposes the **updated** datapath inside [`rtl/siso_maxlogmap.vhd`](../../../rtl/siso_maxlogmap.vhd).

This is the rolling-window version, so the earlier alpha-seed BRAM pack/unpack path is no longer part of the datapath.

## 1. Main Functional Units

The current datapath breaks into:

1. pair fetch input latch
2. even-step branch metric unit
3. odd-step branch metric unit
4. radix-4 gamma combiner
5. shared forward/backward ACS
6. local alpha cache
7. local branch cache (`g0_local_mem`, `g1_local_mem`)
8. local gamma cache
9. local observation cache (`sys/apri`)
10. precomputed LLR extraction unit
11. posterior/extrinsic output formatting

## 2. Pair Fetch Latch

The datapath always works from one registered pair:
- `fetched_sys_even_q`, `fetched_sys_odd_q`
- `fetched_par_even_q`, `fetched_par_odd_q`
- `fetched_apri_even_q`, `fetched_apri_odd_q`

That latch is fed either by:
- legacy segment memories
- or the external fetch response path

So the arithmetic datapath itself is independent of the source memory system.

## 3. Branch Metric Units

`branch_metrics(...)` is still the one-bit BMU.

For each pair, the datapath instantiates it logically twice:
- once for even bit
- once for odd bit

Outputs:
- `g0(0..3)` for the even branch candidates
- `g1(0..3)` for the odd branch candidates

## 4. Radix-4 Gamma Combiner

`pair_gamma_from_branches(g0, g1)` combines the two 4-way branch vectors into the 16-entry radix-4 gamma vector.

This is now the preferred architectural view.

Important difference from the old guide:
- `pair_gamma(...)` still exists as a helper
- but the active datapath actually works as:
  - BMU even
  - BMU odd
  - gamma combine

## 5. Shared ACS

`acs_step(...)` remains the shared radix-4 ACS block.

It is reused for:
- forward recursion in `FWD_STEP`
- dummy backward recursion in `DUMMY_STEP`
- local backward recursion in `LOCAL_BWD`

So the current SISO still time-multiplexes one trellis engine rather than duplicating forward and backward engines.

## 6. Local Caches

At the end of `FWD_STEP`, the current window stores:
- entering alpha state in `alpha_local_mem`
- `gamma` in `gamma_local_mem`
- `g0` in `g0_local_mem`
- `g1` in `g1_local_mem`
- `sys_even/sys_odd` in local caches
- `apri_even/apri_odd` in local caches

This is the critical structural change.

The old architecture stored:
- alpha
- gamma
- raw `sys/par/apri`

The new architecture stores:
- alpha
- gamma
- precomputed branch metrics
- only the `sys/apri` terms still needed for final extrinsic subtraction

So the branch metric arithmetic is not repeated during output extraction.

## 7. Precomputed LLR Extraction

`extract_pair_precomp(...)` replaces the old “recompute branch metrics in extractor” view.

Inputs:
- `alpha_in`
- `beta_in`
- precomputed `g0`
- precomputed `g1`
- `sys_even/sys_odd`
- `apri_even/apri_odd`

Subfunctions inside it:
- alpha-mid reconstruction
- beta-mid reconstruction
- even-bit max tree
- odd-bit max tree
- posterior subtraction
- extrinsic subtraction
- `scale_ext`

The important update is:
- there is no internal BMU inside the extractor anymore

## 8. What Was Removed

These units are no longer part of the active datapath decomposition:
- alpha-seed pack unit
- alpha-seed unpack unit
- alpha-seed BRAM data path
- local forward replay storage of raw parity LLRs for later branch recomputation

## 9. Diagram Files

- [`SISO_MAXLOGMAP_FUNCTIONAL_UNITS.svg`](SISO_MAXLOGMAP_FUNCTIONAL_UNITS.svg)
- [`SISO_BRANCH_AND_GAMMA_UNIT.svg`](SISO_BRANCH_AND_GAMMA_UNIT.svg)
- [`SISO_RADIX4_ACS_UNIT.svg`](SISO_RADIX4_ACS_UNIT.svg)
- [`SISO_LLR_EXTRACTION_UNIT.svg`](SISO_LLR_EXTRACTION_UNIT.svg)
