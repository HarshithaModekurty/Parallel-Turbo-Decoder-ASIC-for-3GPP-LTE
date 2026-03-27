# `qpp_parallel_scheduler` Architecture Guide

This note explains:

- [`rtl/qpp_parallel_scheduler.vhd`](../../rtl/qpp_parallel_scheduler.vhd)
- the helper function [`qpp_value`](../../rtl/turbo_pkg.vhd) used by it

The scheduler is the address-generation front end for the paper-aligned
parallel decoder. It does not move payload data. It only:

- computes one QPP address per lane
- extracts the common row residue
- checks whether the resulting address vector obeys the maximally-vectorizable row rule

So this block sits ahead of the Batcher network and tells the rest of the
parallel datapath whether one row can be processed as a consistent parallel row.

## 1. Inputs And Outputs

Inputs:

- `row_idx`
- `seg_len`
- `k_len`
- `f1`
- `f2`

Outputs:

- `addr_vec`
- `row_base`
- `row_ok`

Meaning:

- `addr_vec(lane)` is the QPP interleaved global address for that lane
- `row_base` is the common residue `addr_i mod seg_len` seen by the row
- `row_ok` is asserted only if all generated lane addresses belong to the same row residue class and remain inside the valid frame

## 2. Natural Block Split

The RTL splits naturally into five combinational blocks:

1. scalar decode / guard
   - `seg_len`, `row_idx`, `k_len`, `f1`, `f2` are converted to integers
   - invalid `seg_len = 0` or `row_idx >= seg_len` is detected
2. lane index generation
   - for each lane:
   - `g_idx := row_i + lane * seg_i`
3. per-lane QPP evaluator
   - if `g_idx < k_i`, compute `addr_i := qpp_value(g_idx, k_i, f1_i, f2_i)`
   - otherwise force `addr_i := 0` and clear `row_ok`
4. row-base extractor and consistency check
   - lane `0` captures `row_v := addr_i mod seg_i`
   - later lanes compare their own residue with `row_v`
5. output pack
   - pack all lane addresses into `addr_vec`
   - drive `row_base` and `row_ok`

That split is shown in:

- [`QPP_PARALLEL_SCHEDULER_ARCHITECTURE.svg`](QPP_PARALLEL_SCHEDULER_ARCHITECTURE.svg)

## 3. Datapath View

The datapath is:

```text
row_idx, seg_len, k_len, f1, f2
  -> scalar integer decode
  -> repeated lane cells
       g_idx = row_i + lane*seg_i
       addr_i = qpp_value(g_idx, k_i, f1_i, f2_i)
       residue_i = addr_i mod seg_i
  -> residue reducer
  -> pack addr_vec / row_base
```

There are `G_P` repeated lane cells. In the paper-aligned decoder:

- `G_P = 8`

That datapath is shown in:

- [`QPP_PARALLEL_SCHEDULER_DATAPATH.svg`](QPP_PARALLEL_SCHEDULER_DATAPATH.svg)

## 4. Control View

There is no FSM. Control is purely combinational and consists of:

- input-range guard:
  - `seg_i = 0`
  - `row_i >= seg_i`
- per-lane in-range check:
  - `g_idx >= k_i`
- row-base capture:
  - lane `0` establishes the reference residue
- row-consistency compare:
  - each later lane checks `(addr_i mod seg_i) = row_v`
- row-valid reduction:
  - `row_ok` is the AND of all guard and consistency conditions

That control structure is shown in:

- [`QPP_PARALLEL_SCHEDULER_CONTROL.svg`](QPP_PARALLEL_SCHEDULER_CONTROL.svg)

## 5. `qpp_value` Structure

The scheduler delegates the actual interleaver address evaluation to:

```text
qpp_value(idx_i, k_i, f1_i, f2_i)
```

as defined in `turbo_pkg.vhd`.

Its structure is:

```text
term1   = mod_mult(f1_i, idx_i, k_i)
idx_sq  = mod_mult(idx_i, idx_i, k_i)
term2   = mod_mult(f2_i, idx_sq, k_i)
addr_i  = (term1 + term2) mod k_i
```

So the deep arithmetic inside the scheduler is actually:

- `3` modular-multiply blocks
- `1` final modular adder / subtractor

## 6. What The Row Check Means

The scheduler is not only generating addresses. It is checking the paper’s
maximally-vectorizable row property.

For one chosen `row_idx`, the block evaluates:

```text
g_idx(lane) = row_idx + lane * seg_len
addr_i(lane) = qpp_value(g_idx(lane))
residue_i(lane) = addr_i(lane) mod seg_len
```

Then it requires:

```text
residue_i(0) = residue_i(1) = ... = residue_i(G_P-1)
```

If all residues match and all addresses are in range, then:

- `row_ok = '1'`
- `row_base = residue_i(0)`

Otherwise:

- `row_ok = '0'`

## 7. What To Draw

The clean drawing set is:

1. full architecture:
   - scalar guard
   - repeated lane address-generation bank
   - residue reducer
   - output pack
2. datapath:
   - repeated lane arithmetic and `qpp_value`
3. control:
   - guard checks and row-consistency chain
4. cell level:
   - one lane cell
   - one `qpp_value` evaluator
   - one `mod_mult` block
   - one row-check chain

## 8. Diagram Files In This Package

- [`QPP_PARALLEL_SCHEDULER_ARCHITECTURE.svg`](QPP_PARALLEL_SCHEDULER_ARCHITECTURE.svg)
- [`QPP_PARALLEL_SCHEDULER_DATAPATH.svg`](QPP_PARALLEL_SCHEDULER_DATAPATH.svg)
- [`QPP_PARALLEL_SCHEDULER_CONTROL.svg`](QPP_PARALLEL_SCHEDULER_CONTROL.svg)
- [`cell_level/`](cell_level/)
