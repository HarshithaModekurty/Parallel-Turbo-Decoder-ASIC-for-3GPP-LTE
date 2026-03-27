# `turbo_decoder_top_parallel8_backup` Cell-Level Guide

This package adds the top-module cell-level view for:

- [`rtl/turbo_decoder_top_parallel8_backup.vhd`](../../../rtl/turbo_decoder_top_parallel8_backup.vhd)

The emphasis here is only on structures that actually live in the top module.
So this package does **not** redraw the internals of:

- `siso_maxlogmap`
- `qpp_parallel_scheduler`
- `batcher_master`
- `batcher_slave`
- `multiport_row_bram`

Those modules already have their own export packages. Here, they appear as
referenced subblocks wherever the top instantiates or surrounds them.

## 1. Worthy Top-Level Cell Blocks

The worthy top-specific blocks are:

1. scalar load scatter
2. issue / feed pipeline and permutation-context capture
3. phase-2 source-select and forward-routing shell
4. writeback shell and reverse-routing destination mapping
5. serializer
6. top control loop around `turbo_iteration_ctrl`

## 2. Load Scatter

The load-scatter process converts the scalar input stream into:

- `lane_i = in_idx / seg_i`
- `row_i = in_idx mod seg_i`
- `pair_i = row_i / 2`
- one-hot `load_lane_we`
- `load_even_en` or `load_odd_en`
- packed `load_sys_bus`, `load_par1_bus`, `load_par2_bus`

This is shown in:

- [`TURBO_DECODER_TOP_PARALLEL8_LOAD_SCATTER_CELL_LEVEL.svg`](TURBO_DECODER_TOP_PARALLEL8_LOAD_SCATTER_CELL_LEVEL.svg)

## 3. Issue / Feed Pipeline

The main sequential process creates a pair-stream issue pipeline:

- `issue_active`
- `issue_pair_idx`
- `feed_pipe_valid`
- `feed_pipe_pair_idx`

During `run2` it also captures the permutation context:

- `feed_perm_even_q`
- `feed_perm_odd_q`
- `feed_even_is_odd_q`
- `feed_odd_is_odd_q`
- `feed_even_valid_q`
- `feed_odd_valid_q`

Then one pair row later it fans the selected row bundle to all `8` SISO lanes.

This is shown in:

- [`TURBO_DECODER_TOP_PARALLEL8_ISSUE_FEED_CELL_LEVEL.svg`](TURBO_DECODER_TOP_PARALLEL8_ISSUE_FEED_CELL_LEVEL.svg)

## 4. Phase-2 Feed Shell

The top-specific phase-2 feed shell does:

1. choose even or odd physical source row from `row_base(0)`
2. zero the row if `feed_*_valid_q = 0`
3. pack the selected row
4. pass it through forward `batcher_slave`
5. unpack the lane-order result

That shell exists four times:

- even sys
- odd sys
- even apri
- odd apri

This is shown in:

- [`TURBO_DECODER_TOP_PARALLEL8_PHASE2_FEED_CELL_LEVEL.svg`](TURBO_DECODER_TOP_PARALLEL8_PHASE2_FEED_CELL_LEVEL.svg)

## 5. Writeback Shell

The writeback process has two distinct branches:

- `run1`
  - direct pair-row writes into natural extrinsic and optional final memories
- `run2`
  - reverse `batcher_slave` on ext/post
  - row-base parity test
  - destination-bank selection
  - even/odd row-address mapping

This is shown in:

- [`TURBO_DECODER_TOP_PARALLEL8_WRITEBACK_CELL_LEVEL.svg`](TURBO_DECODER_TOP_PARALLEL8_WRITEBACK_CELL_LEVEL.svg)

## 6. Serializer

The serializer derives:

- `lane = idx / seg_bits`
- `row = idx mod seg_bits`
- `pair = row / 2`
- `is_odd = row mod 2`

Then it selects:

- `final_even_rd_row(lane)`
- or `final_odd_rd_row(lane)`

and emits the scalar posterior stream.

This is shown in:

- [`TURBO_DECODER_TOP_PARALLEL8_SERIALIZER_CELL_LEVEL.svg`](TURBO_DECODER_TOP_PARALLEL8_SERIALIZER_CELL_LEVEL.svg)

## 7. Control Loop

The top control is the combination of:

- `turbo_iteration_ctrl`
- run-edge detection on `run1` / `run2`
- `all_done` AND-reduction of `core_done[0..7]`
- `phase1_done` / `phase2_done`
- serializer start on `last_half`

This is shown in:

- [`TURBO_DECODER_TOP_PARALLEL8_CONTROL_CELL_LEVEL.svg`](TURBO_DECODER_TOP_PARALLEL8_CONTROL_CELL_LEVEL.svg)

## 8. Reading Convention

This package uses the same convention as the newer SISO, batcher, and QPP
cell-level packages:

- adder: circular `+`
- comparator / test: diamond
- mux: trapezoid `MUX`
- pipeline register / captured context: storage block
- repeated structures: explicit first blocks, `...`, explicit last block, with total count stated

These figures are exact-isomorphic with respect to the top RTL structure.
They are not post-synthesis gate-level netlists.
