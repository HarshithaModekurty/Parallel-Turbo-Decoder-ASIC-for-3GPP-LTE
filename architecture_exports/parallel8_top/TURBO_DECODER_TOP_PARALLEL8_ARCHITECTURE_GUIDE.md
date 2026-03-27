# `turbo_decoder_top_parallel8_backup` Architecture Guide

This note explains [`rtl/turbo_decoder_top_parallel8_backup.vhd`](../../rtl/turbo_decoder_top_parallel8_backup.vhd) as the paper-aligned top-level architecture of the parallel turbo decoder.

This is the version that wraps:
- `8` parallel `siso_maxlogmap` constituent decoders
- `qpp_parallel_scheduler`
- `batcher_master` / `batcher_slave`
- `multiport_row_bram`
- `turbo_iteration_ctrl`

Important framing:
- this is the **paper-aligned parallel architecture**
- the active FPGA-fit top in the repo is the folded single-SISO top, not this one
- the module directly instantiates `batcher_master` and `batcher_slave`
- the wrapper `batcher_router` is **not** used in this top

## 1. What This Module Is

`turbo_decoder_top_parallel8_backup` is the full top-level parallel decoder shell around eight SISO lanes.

At a high level it does this:
1. scatter-load the input frame into lane-partitioned row memories
2. run the first constituent half-iteration in natural order across all `8` SISOs
3. run the second constituent half-iteration in interleaved order using the QPP scheduler and Batcher network
4. write extrinsic and posterior results back into row memories
5. serialize the final posterior LLRs back to a scalar output stream

So the top module is not “the decoder algorithm” by itself. It is the:
- lane scheduler
- parallel memory shell
- permutation network
- iteration-phase controller
- output gatherer

The per-lane decoding algorithm still lives inside [`rtl/siso_maxlogmap.vhd`](../../rtl/siso_maxlogmap.vhd).

## 2. Top-Level Ports

Ports from [`rtl/turbo_decoder_top_parallel8_backup.vhd`](../../rtl/turbo_decoder_top_parallel8_backup.vhd):

- `clk`, `rst`
  - global clock and reset

- `start`
  - starts the decoder run

- `n_half_iter`
  - total number of half-iterations
  - consumed by [`rtl/turbo_iteration_ctrl.vhd`](../../rtl/turbo_iteration_ctrl.vhd)

- `k_len`
  - frame length `K`

- `f1`, `f2`
  - QPP interleaver coefficients

- `in_valid`, `in_idx`
- `l_sys_in`, `l_par1_in`, `l_par2_in`
  - scalar input stream for loading the full frame
  - these are scattered into the row memories before/while decoding

- `out_valid`, `out_idx`, `l_post`
  - serialized final posterior LLR output

- `done`
  - final completion pulse

## 3. Structural Assumptions

The module hard-codes the paper-style parallelism:

- `C_CORES = C_PARALLEL = 8`
- `C_SEG_MAX = ceil(K/8)`
- `C_PAIR_MAX = ceil(C_SEG_MAX/2)`
- `C_BRAM_BANKS = 16`

Operational assumption:
- `K` must be divisible by `8`
- this is enforced by an assertion in the sequential control process

Architectural meaning:
- the frame is split into `8` contiguous segments
- each SISO lane decodes one segment
- each segment is still internally windowed by `siso_maxlogmap`

So this top adds **segmentation across cores**, while the SISO core itself adds **windowing inside one segment**.

## 4. Major Internal Blocks

You can understand the top as nine major blocks.

### 4.1 Iteration Controller

[`rtl/turbo_iteration_ctrl.vhd`](../../rtl/turbo_iteration_ctrl.vhd) generates:
- `run1`
- `run2`
- `last_half`
- `ctrl_done`

This is the phase controller for the two constituent decoders:
- `RUN1`: natural-order half-iteration
- `RUN2`: interleaved/deinterleaved half-iteration

### 4.2 Eight-Lane SISO Array

The `gen_siso` generate block instantiates `8` copies of [`rtl/siso_maxlogmap.vhd`](../../rtl/siso_maxlogmap.vhd).

Per-lane behavior:
- each lane gets one segment
- lane `0` has `seg_first = '1'`
- lane `7` has `seg_last = '1'`
- interior lanes are non-terminated at one or both boundaries

Architecturally this is the core parallelism of the paper.

### 4.3 Scalar Input Scatter Loader

The first combinational process maps the scalar input stream into:
- lane index
- row index inside that segment
- pair address
- even/odd write enable

So one scalar incoming sample is converted into one write into the correct:
- lane
- parity of row
- pair address

### 4.4 Multiport Row Memory System

This top uses many [`rtl/multiport_row_bram.vhd`](../../rtl/multiport_row_bram.vhd) instances.

Logical memory groups:
- systematic:
  - `sys_even_rd0_ram`
  - `sys_even_rd1_ram`
  - `sys_odd_rd0_ram`
  - `sys_odd_rd1_ram`
- parity for decoder 1:
  - `par1_even_ram`
  - `par1_odd_ram`
- parity for decoder 2:
  - `par2_even_ram`
  - `par2_odd_ram`
- extrinsic memory:
  - `ext_even_rd0_ram`
  - `ext_even_rd1_ram`
  - `ext_odd_rd0_ram`
  - `ext_odd_rd1_ram`
- final posterior memory:
  - `final_even_ram`
  - `final_odd_ram`

Why there are duplicate read memories:
- phase 1 reads in natural segment order
- phase 2 needs two QPP-related read streams
- the structure is trying to emulate the paper’s parallel row access pattern using FPGA BRAM banking

### 4.5 QPP Parallel Scheduler

Two [`rtl/qpp_parallel_scheduler.vhd`](../../rtl/qpp_parallel_scheduler.vhd) instances are used:
- even-row scheduler
- odd-row scheduler

Inputs:
- `row_idx`
- `seg_len`
- `k_len`
- `f1`, `f2`

Outputs:
- `addr_vec`
- `row_base`
- `row_ok`

Meaning:
- for a given pair row, compute the `8` global QPP addresses
- require that those addresses lie in the same segment row modulo `seg_len`
- this is the “maximally vectorizable” property the top asserts in run 2

### 4.6 Batcher Network

Two [`rtl/batcher_master.vhd`](../../rtl/batcher_master.vhd) instances sort the QPP address vectors and emit:
- sorted addresses
- lane permutation vectors

Then four [`rtl/batcher_slave.vhd`](../../rtl/batcher_slave.vhd) instances route:
- interleaved systematic rows
- interleaved apriori/extrinsic rows

into lane order before feeding the SISO array.

At writeback time, another four `batcher_slave` instances run in reverse mode to unsort:
- extrinsic outputs
- posterior outputs

back into memory-row order.

### 4.7 Permutation History Memories

The top stores, per pair row:
- `perm_even_mem`
- `perm_odd_mem`
- `row_base_even_mem`
- `row_base_odd_mem`

These are needed because:
- phase 2 feed uses one permutation to route data into the SISO lanes
- phase 2 writeback later needs to undo that exact permutation

So these are the side memories that preserve the routing context.

### 4.8 Writeback Network

The second combinational process handles SISO writeback.

Two cases:
- in `run1`, write outputs directly by the current pair row
- in `run2`, use stored row-base and permutation history to write outputs back to the correct interleaved even/odd destinations

If `last_half = '1'`, posterior LLRs are also written into final memories.

### 4.9 Output Serializer

After the last half-iteration finishes, the sequential process turns on `ser_issue_active`.

The serializer then:
- scans `ser_issue_idx` from `0` to `K-1`
- maps that index to:
  - lane = `global_idx / seg_bits`
  - row = `global_idx mod seg_bits`
  - parity = even or odd row
- reads `final_even_ram` / `final_odd_ram`
- emits one scalar `l_post`

So the parallel result memories are converted back to a serial output stream.

## 5. Run-1 Datapath

`run1` is the natural-order half-iteration.

Dataflow:
1. the issue loop steps through pair rows `0 .. pair_count-1`
2. `sys_even/odd` are read directly from natural-order memories
3. `par1_even/odd` are read as the parity inputs
4. apriori inputs come from:
   - zero on the very first `run1`
   - otherwise `ext_even/odd` memories
5. all `8` SISOs receive one pair row in parallel
6. outputs write directly back into `ext_even/odd`
7. if this is the last half-iteration, posterior outputs also write into `final_even/odd`

This is the simpler of the two phases because there is no QPP routing in the feed path.

## 6. Run-2 Datapath

`run2` is the interleaved half-iteration.

Dataflow:
1. the issue loop chooses a pair row
2. even and odd row indices are formed as:
   - `2 * pair_idx`
   - `2 * pair_idx + 1`
3. the QPP schedulers compute the `8` interleaved addresses for both rows
4. the Batcher masters sort those addresses and generate permutation vectors
5. the top remembers permutation and row-base information for writeback
6. systematic and apriori rows are read from the corresponding memories
7. `feed_even_is_odd_q` / `feed_odd_is_odd_q` choose whether the source row is physically even or odd
8. Batcher slaves route the sorted rows back into SISO lane order
9. parity for decoder 2 comes from `par2_even/odd`
10. the `8` SISOs decode in parallel
11. writeback unslaves the SISO outputs and writes them into the correct interleaved row destinations

So `run2` is where the real paper-style parallel interleaver routing happens.

## 7. Issue / Feed Pipeline

The top has a simple two-stage feed mechanism:

- `issue_active`
  - memory read side is stepping through pair rows

- `feed_pipe_valid`
  - one cycle later, the read data is presented to all SISOs

This is the top-level pair scheduler for the eight-lane array.

Important detail:
- `core_start` is pulsed for all lanes together when `run1` or `run2` begins
- `core_seg_len(i)` is the same `seg_bits` for all lanes
- `core_out_valid(i)` and `core_out_pair_idx(i)` are asserted to stay aligned across all `8` lanes

The top explicitly asserts against lane skew.

## 8. Top-Level Control Behavior

This top does not have a separate top-level enumerated FSM type.

Instead, control is the combination of:
- [`rtl/turbo_iteration_ctrl.vhd`](../../rtl/turbo_iteration_ctrl.vhd)
- the main sequential process in [`rtl/turbo_decoder_top_parallel8_backup.vhd`](../../rtl/turbo_decoder_top_parallel8_backup.vhd)
- the issue/feed/writeback combinational processes

The effective schedule is:

1. external load fills the memories
2. `start` captures `K`, computes `seg_bits`, `pair_count`
3. iteration controller enters `RUN1`
4. all eight SISOs are started
5. issue/feed loop streams all pair rows to the cores
6. when all cores report done, `phase1_done` pulses
7. iteration controller either moves to `RUN2` or finishes
8. in `RUN2`, the same issue/feed loop runs, but through the QPP + Batcher path
9. when all cores report done, `phase2_done` pulses
10. if this was the last half-iteration, serializer drains final posterior outputs
11. `done` is asserted after the last serialized output

## 9. Boundary Conditions And First-Iteration Handling

Two details are easy to miss.

### 9.1 Segment Boundary Flags

The lane index determines boundary behavior:
- lane `0`: first segment
- lane `7`: last segment

So only the outermost SISOs use terminated outer boundaries.

### 9.2 `first_run1_pending`

On the very first `run1`:
- apriori inputs are forced to zero

On later `run1` passes:
- apriori inputs come from stored extrinsic memory

So `first_run1_pending` is the flag that distinguishes:
- first constituent pass with no prior extrinsic information
- later passes with feedback

## 10. What To Draw

For the full top-level parallel architecture, draw these blocks:

1. scalar input loader / scatter
2. natural-order row memories
3. QPP even/odd schedulers
4. Batcher masters
5. phase-2 source selection
6. Batcher slave feed routers
7. `8 x siso_maxlogmap`
8. permutation-history memories
9. reverse Batcher writeback
10. extrinsic / final row memories
11. output serializer
12. turbo-iteration controller

The clean mental model is:

```text
scalar input stream
    -> row memories
    -> either direct natural feed (run1)
       or QPP + Batcher routed feed (run2)
    -> 8 parallel SISOs
    -> direct or unsorted writeback
    -> final posterior memories
    -> scalar output stream
```

## 11. Datapath vs Control

For presentation, split the module into two drawings.

### Datapath drawing

Show:
- load scatter
- memory banks
- QPP scheduler
- Batcher network
- SISO array
- writeback network
- serializer

### Control drawing

Show:
- `turbo_iteration_ctrl` states
- run-edge start pulse to all cores
- issue loop
- feed pipe
- all-done reduction
- `phase1_done` / `phase2_done`
- serializer drain after last half-iteration

## 12. Short Description

The clean one-line description is:

`turbo_decoder_top_parallel8_backup` is an eight-lane segmented turbo-decoder shell that uses banked row memories, a QPP scheduler, Batcher-based routing, and a half-iteration controller to feed eight radix-4 windowed SISO tiles in parallel, then writes back and serializes the final posterior LLRs.

## 13. Diagram Files In This Folder

This folder contains:

- [`TURBO_DECODER_TOP_PARALLEL8_ARCHITECTURE.svg`](TURBO_DECODER_TOP_PARALLEL8_ARCHITECTURE.svg)
  - combined architecture overview
- [`TURBO_DECODER_TOP_PARALLEL8_DATAPATH.svg`](TURBO_DECODER_TOP_PARALLEL8_DATAPATH.svg)
  - datapath-only view
- [`TURBO_DECODER_TOP_PARALLEL8_CONTROL.svg`](TURBO_DECODER_TOP_PARALLEL8_CONTROL.svg)
  - control / schedule view

Editable sources:

- [`TURBO_DECODER_TOP_PARALLEL8_ARCHITECTURE.dot`](TURBO_DECODER_TOP_PARALLEL8_ARCHITECTURE.dot)
- [`TURBO_DECODER_TOP_PARALLEL8_DATAPATH.dot`](TURBO_DECODER_TOP_PARALLEL8_DATAPATH.dot)
- [`TURBO_DECODER_TOP_PARALLEL8_CONTROL.dot`](TURBO_DECODER_TOP_PARALLEL8_CONTROL.dot)
