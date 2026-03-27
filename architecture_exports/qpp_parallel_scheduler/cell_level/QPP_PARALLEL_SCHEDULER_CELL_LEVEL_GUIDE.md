# `qpp_parallel_scheduler` Cell-Level Guide

This package adds the exact-isomorphic schematic level for the QPP scheduler.

The scheduler is purely combinational, so the deep primitives are arithmetic,
compare, mux, decode, and reduction blocks rather than registers or FSM states.

## 1. Repeated Top-Level Primitive: Lane Cell

The scheduler is a bank of `G_P` repeated lane cells.

For the paper-aligned parallel decoder:

- `G_P = 8`

One lane cell performs:

1. `g_idx = row_i + lane * seg_i`
2. `g_idx < k_i` range check
3. `addr_i = qpp_value(g_idx, k_i, f1_i, f2_i)` if valid
4. zero-mux fallback if invalid
5. `residue_i = addr_i mod seg_i`

The lane bank and one primitive cell are shown in:

- [`QPP_SCHEDULER_LANE_BANK_CELL_LEVEL.svg`](QPP_SCHEDULER_LANE_BANK_CELL_LEVEL.svg)
- [`QPP_SCHEDULER_LANE_CELL_LEVEL.svg`](QPP_SCHEDULER_LANE_CELL_LEVEL.svg)

## 2. `qpp_value` Deep Structure

The function `qpp_value(idx_i, k_i, f1_i, f2_i)` is the arithmetic core.

Its RTL structure is:

```text
term1  = mod_mult(f1_i, idx_i, k_i)
idx_sq = mod_mult(idx_i, idx_i, k_i)
term2  = mod_mult(f2_i, idx_sq, k_i)
sum_v  = term1 + term2
if sum_v >= k_i then sum_v := sum_v - k_i
```

So one `qpp_value` cell contains:

- `3` modular multiply blocks
- `1` adder
- `1` compare-subtract reducer

That exact arithmetic split is shown in:

- [`QPP_VALUE_CELL_LEVEL.svg`](QPP_VALUE_CELL_LEVEL.svg)

## 3. `mod_mult` Deep Structure

`mod_mult` is written as a bounded iterative modular multiply with:

- `C_MAX_BITS = 16`

Each iteration behaves like a repeated update slice:

1. inspect current multiplier bit / state
2. conditionally accumulate `acc_v + a_v`
3. modular reduce by compare-subtract against `mod_i`
4. shift/divide multiplier state
5. double `a_v`
6. modular reduce doubled `a_v`

So the deep isomorphic view is a chain of `16` repeated update slices. The
figure shows the first slices, `...`, and the last slice explicitly.

That structure is shown in:

- [`QPP_MOD_MULT_CELL_LEVEL.svg`](QPP_MOD_MULT_CELL_LEVEL.svg)
- [`QPP_MOD_MULT_UPDATE_SLICE_CELL_LEVEL.svg`](QPP_MOD_MULT_UPDATE_SLICE_CELL_LEVEL.svg)

## 4. Row-Check Chain

After lane cells produce `residue_i`, the scheduler performs:

- lane `0` reference capture
- residue compare for lanes `1..G_P-1`
- validity reduction into `row_ok`

That chain is shown in:

- [`QPP_ROW_CHECK_CELL_LEVEL.svg`](QPP_ROW_CHECK_CELL_LEVEL.svg)

## 5. Reading Convention

This package uses the same convention as the newer SISO and batcher cell-level
packages:

- adder: circular `+`
- subtractor: circular `-`
- multiplier: circular `*`
- comparator / test: diamond
- mux: trapezoid `MUX`
- repeated blocks: first, `...`, last, with total count stated

These figures are exact-isomorphic with respect to the RTL algorithmic
structure. They are not post-synthesis gate-level netlists.
