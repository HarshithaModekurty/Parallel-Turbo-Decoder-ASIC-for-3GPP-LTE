# `siso_maxlogmap` Internal Control Functional Guide

This note decomposes the control logic inside [`rtl/siso_maxlogmap.vhd`](../../../rtl/siso_maxlogmap.vhd).

The intent here is narrower than the earlier control figure:
- not the arithmetic datapath
- not the whole SISO black-box architecture
- specifically the **internal control functions** that sequence the datapath

The relevant logic lives mainly inside the single sequential process beginning near the middle of the file.

## 1. What Counts As The Control Unit Here

There is no separately instantiated control module.

The control unit is the combination of:
- the state register `st`
- loop/index registers:
  - `pair_cnt`
  - `seg_bits_i`
  - `win_cnt`
  - `load_idx`
  - `work_win_idx`
  - `work_local_idx`
- one-cycle pulse signals:
  - `alpha_seed_rd_en`
  - `alpha_seed_wr_en`
  - `out_valid_q`
  - `done_q`
- derived temporary control variables:
  - `start_seed_v`
  - `end_seed_v`
  - `frame_read_valid_v`
  - `frame_read_idx_v`
  - `win_pair_cnt_v`

So the control unit is not just “the FSM states”. It is:
- state transition logic
- state-dependent enable generation
- address generation
- loop traversal logic
- boundary-condition selection

## 2. Main Functional Control Blocks

The control logic can be split into seven functional blocks.

### 2.1 Segment Setup Unit

Active in `IDLE` when `start = '1'`.

Functions:
- clamp `seg_len` to `G_SEG_MAX`
- compute:
  - `seg_bits_i`
  - `pair_cnt = ceil(seg_bits/2)`
  - `win_cnt = ceil(seg_bits/C_WINDOW)`
- initialize `load_idx`
- choose between:
  - immediate `done_q` for empty segment
  - transition to `LOAD`

This is the frame/segment admission controller.

### 2.2 Boundary Seed Selector

Every active cycle it computes:
- `start_seed_v`
- `end_seed_v`

using:
- `seg_first`
- `seg_last`
- `uniform_state()`
- `terminated_state()`

Meaning:
- the control logic chooses whether the segment starts/ends with terminated state metrics or uniform neutral metrics

This block is purely control policy, even though its outputs are state vectors.

### 2.3 Frame Read Selector

Before the main state-action case, the controller chooses whether a frame-memory read is needed and which pair index to read.

State-dependent selection:
- `DUMMY_FWD`
  - `frame_read_idx_v = work_local_idx`
- `FWD_SEEDS`
  - `frame_read_idx_v = work_win_idx * C_PAIR_WIN + work_local_idx`
- `DUMMY_BWD`
  - `frame_read_idx_v = (work_win_idx + 1) * C_PAIR_WIN + work_local_idx`
- `LOCAL_FWD`
  - `frame_read_idx_v = work_win_idx * C_PAIR_WIN + work_local_idx`

Then if `frame_read_valid_v = true`, the six frame memories are sampled.

So there is an implicit read-address multiplexer controlled by the FSM.

### 2.4 Loop / Index Controller

This is the core traversal logic.

Registers:
- `load_idx`
  - walks through the segment during `LOAD`
- `work_win_idx`
  - selects the active window
- `work_local_idx`
  - selects the pair inside a window

This block determines:
- load traversal
- forward seed traversal
- backward dummy traversal
- local forward replay
- local backward emission order

### 2.5 Alpha-Seed BRAM Controller

This logic manages `alpha_seed_ram`.

Write side:
- `DUMMY_FWD`
  - write seed `0` with `pack_state_metric(start_seed_v)` at end of first window
- `FWD_SEEDS`
  - write seed for `work_win_idx + 1` using `pack_state_metric(alpha_next_v)`

Read side:
- `PREP_WINDOW`
  - if current window is last, start read immediately
- `DUMMY_BWD`
  - when beta seed is ready, start read of current window seed
- `LOAD_ALPHA_WAIT`
  - absorb BRAM latency
- `LOAD_ALPHA`
  - unpack and load `alpha_work`

So this is a dedicated memory-handshake controller for the per-window alpha seeds.

### 2.6 Phase Controller

The SISO schedule has distinct phases:
- `LOAD`
- global forward prepass
- backward-seed preparation
- local forward replay
- local backward extraction

This block is the higher-level sequencing policy embodied by the state transitions:
- `LOAD -> DUMMY_FWD -> FWD_SEEDS`
- `PREP_WINDOW -> DUMMY_BWD / LOAD_ALPHA_WAIT`
- `LOAD_ALPHA -> LOCAL_FWD -> LOCAL_BWD`

This is the real algorithmic scheduler.

### 2.7 Output Pulse Controller

This logic generates:
- `out_valid_q`
- `out_pair_idx_q`
- `done_q`

Important behavior:
- `out_valid_q` is asserted only in `LOCAL_BWD`
- `done_q` is normally asserted only in `FINISH`
- but `done_q` can also be asserted early for degenerate zero-length cases

The pulse-style behavior is created by default-clearing these signals every cycle before the state case.

## 3. Default-Clear Pulse Logic

At the top of the active clock branch, the controller does:

- `out_valid_q <= '0'`
- `done_q <= '0'`
- `alpha_seed_rd_en <= '0'`
- `alpha_seed_wr_en <= '0'`

That means these signals are one-cycle pulses unless explicitly reasserted in the current state.

Architecturally this is a small control-output register bank with default-zero next-state logic.

## 4. Deep State-by-State Control Meaning

### `IDLE`

Control functions:
- wait for `start`
- compute segment setup quantities
- select empty-segment short-circuit or `LOAD`

Registers updated:
- `seg_bits_i`
- `pair_cnt`
- `win_cnt`
- `load_idx`

### `LOAD`

Control functions:
- gate writes into segment memories when `in_valid = '1'`
- decide whether all pairs are loaded

Registers updated:
- memory arrays
- `load_idx`
- `work_local_idx`
- `alpha_work`

### `DUMMY_FWD`

Control functions:
- request frame reads from window `0`
- advance `work_local_idx`
- at the end of the window:
  - write alpha seed `0`
  - reset traversal to start `FWD_SEEDS`

### `FWD_SEEDS`

Control functions:
- request frame reads for current window/pair
- update `alpha_work`
- at the end of each window:
  - either write the next window’s alpha seed and continue
  - or move to `PREP_WINDOW`

### `PREP_WINDOW`

Control functions:
- choose last-window vs interior-window path
- for last window:
  - load `beta_seed_reg <= end_seed_v`
  - trigger alpha-seed BRAM read
- for interior window:
  - set `work_local_idx` to last pair of `Wm+1`
  - initialize `beta_work <= uniform_v`
  - move to `DUMMY_BWD`

### `DUMMY_BWD`

Control functions:
- request frame reads from the next window
- walk backward through `Wm+1`
- when finished:
  - capture `beta_seed_reg`
  - trigger alpha-seed read of `Wm`

### `LOAD_ALPHA_WAIT`

Control function:
- one-cycle BRAM-latency absorption

### `LOAD_ALPHA`

Control function:
- unpack BRAM read data into `alpha_work`

### `LOCAL_FWD`

Control functions:
- request frame reads for current window
- write local buffers
- advance forward through window
- at the end:
  - load `beta_work <= beta_seed_reg`
  - set `work_local_idx` to the last local pair
  - move to `LOCAL_BWD`

### `LOCAL_BWD`

Control functions:
- emit one output pair
- update `beta_work`
- either:
  - continue backward within the window
  - or move to previous window via `PREP_WINDOW`
  - or finish if current window is `0`

### `FINISH`

Control function:
- pulse `done_q`
- return to `IDLE`

## 5. Deep Index And Address Control

Three address domains are controlled here.

### 5.1 Segment-Level Setup

Computed once in `IDLE`:

```text
pair_cnt = (seg_bits + 1) / 2
win_cnt  = (seg_bits + C_WINDOW - 1) / C_WINDOW
```

### 5.2 Frame-Memory Pair Address

Derived combinationally from `st`, `work_win_idx`, and `work_local_idx`.

This is the controller’s read-address multiplexer for:
- `sys_even_mem`
- `sys_odd_mem`
- `par_even_mem`
- `par_odd_mem`
- `apri_even_mem`
- `apri_odd_mem`

### 5.3 Alpha-Seed BRAM Address

Write addresses:
- `0` in `DUMMY_FWD`
- `work_win_idx + 1` in `FWD_SEEDS`

Read address:
- `work_win_idx` in `PREP_WINDOW` or `DUMMY_BWD`

So the control logic manages two distinct memory-address spaces:
- pair-memory addresses
- window-seed addresses

## 6. Hidden But Important Control Policies

### 6.1 Interior vs Last Window Policy

`PREP_WINDOW` is the branch point for:
- direct end-boundary beta seed on the last window
- dummy backward on `Wm+1` for interior windows

This is the main place where the window algorithm policy is encoded.

### 6.2 Forward/Backward Reuse Policy

The same datapath blocks are reused across phases.

The control logic is what decides:
- when `acs_step` is forward
- when `acs_step` is backward
- when frame memories feed the BMU
- when local buffers feed the extractor

### 6.3 Reverse Window Order

Forward seed generation moves:
- window `0 -> 1 -> 2 -> ...`

Local decode moves:
- window `last -> ... -> 1 -> 0`

That reverse-order policy is controlled by `work_win_idx` updates in:
- `FWD_SEEDS`
- `LOCAL_BWD`

## 7. Control-Unit Decomposition Summary

A clean decomposition of the control unit is:

1. start/segment setup unit
2. boundary seed select unit
3. FSM state register and transition logic
4. frame-read address selector
5. loop/index update unit
6. alpha-seed BRAM handshake controller
7. state-action decoder
8. output pulse generator

## 8. Diagram Files In This Folder

- [`SISO_MAXLOGMAP_CONTROL_FUNCTIONAL_UNITS.svg`](SISO_MAXLOGMAP_CONTROL_FUNCTIONAL_UNITS.svg)
  - overall control functional decomposition
- [`SISO_MAXLOGMAP_FSM_DEEP_CONTROL.svg`](SISO_MAXLOGMAP_FSM_DEEP_CONTROL.svg)
  - exact state-transition structure
- [`SISO_MAXLOGMAP_INDEX_AND_ADDRESS_CONTROL.svg`](SISO_MAXLOGMAP_INDEX_AND_ADDRESS_CONTROL.svg)
  - counters, indices, and address generation
- [`SISO_MAXLOGMAP_STATE_ACTION_CONTROL.svg`](SISO_MAXLOGMAP_STATE_ACTION_CONTROL.svg)
  - mapping from states to asserted actions and enables
