# `turbo_decoder_top` Cell-Level Guide

This package covers the active folded top:

- [`rtl/turbo_decoder_top.vhd`](../../../rtl/turbo_decoder_top.vhd)

The top is not decomposed into every minor signal assignment. Instead, the
cell-level package focuses on the blocks that materially define the active
architecture.

## 1. Selected Worthy Blocks

The worthy cell-level blocks in the active top are:

1. input load scatter
   - converts the scalar frame stream into even/odd natural memories and parity-2 interleaved memories
2. QPP recurrence engine
   - generates the rolling `qpp_curr_i`, `qpp_delta_i`, and `qpp_step_i` sequence used by all permutation-copy phases
3. permutation-copy engine
   - shared structure used by:
   - `ST_BUILD_SYS_INT`
   - `ST_EXT_NAT_TO_INT`
   - `ST_EXT_INT_TO_NAT`
   - `ST_FINAL_INT_TO_NAT`
4. SISO fetch bridge
   - translates the single SISO external-fetch request into BRAM reads and one-cycle delayed response data
5. serializer
   - drains final natural-order posterior memories into scalar `out_valid/out_idx/l_post`
6. top FSM
   - the actual active control schedule of the folded top

## 2. Input Load Scatter

The active top accepts scalar frame samples:

- `in_idx`
- `l_sys_in`
- `l_par1_in`
- `l_par2_in`

The load scatter block:

1. computes `pair_idx = in_idx / 2`
2. checks even/odd with `in_idx mod 2`
3. selects even or odd natural banks
4. writes:
   - natural systematic
   - natural parity-1
   - interleaved parity-2
5. zero-initializes:
   - natural extrinsic
   - interleaved extrinsic
   - interleaved posterior
   - final natural posterior

This is shown in:

- [`TURBO_TOP_LOAD_SCATTER_CELL_LEVEL.svg`](TURBO_TOP_LOAD_SCATTER_CELL_LEVEL.svg)

## 3. QPP Recurrence Engine

The active top does not call `qpp_value` repeatedly during the permutation-copy
phases. Instead it uses the incremental recurrence:

```text
qpp_curr_next  = qpp_add_mod(qpp_curr_i, qpp_delta_i, K)
qpp_delta_next = qpp_add_mod(qpp_delta_i, qpp_step_i, K)
qpp_step_i     = qpp_double_mod(f2_i, K)
```

This is the core arithmetic that keeps the active top much smaller than the
earlier quadratic recomputation style.

This is shown in:

- [`TURBO_TOP_QPP_RECURRENCE_CELL_LEVEL.svg`](TURBO_TOP_QPP_RECURRENCE_CELL_LEVEL.svg)

## 4. Permutation-Copy Engine

Four states in the top reuse the same structural copy engine:

- system natural -> interleaved build
- extrinsic natural -> interleaved copy
- extrinsic interleaved -> natural copy
- final posterior interleaved -> natural copy

The common structure is:

1. use `qpp_curr_i` or `perm_issue_idx` to determine source / destination oddness
2. read one source bank selected by source parity
3. pipeline `valid`, `src_odd`, `dst_odd`, `dst_pair`
4. one cycle later, write the selected destination bank

That shared structure is shown in:

- [`TURBO_TOP_PERMUTE_COPY_CELL_LEVEL.svg`](TURBO_TOP_PERMUTE_COPY_CELL_LEVEL.svg)

## 5. SISO Fetch Bridge

The folded top uses `siso_maxlogmap` in external-fetch mode. So the top must:

1. observe `siso_fetch_req_valid`
2. decode the current run mode
3. read the correct bank set:
   - natural sys/par1/ext
   - or interleaved sys/par2/ext
4. hold one-cycle pending flags for BRAM latency
5. return fetched samples through `siso_fetch_rsp_valid_q` and the SISO input latches

This bridge is shown in:

- [`TURBO_TOP_SISO_FETCH_BRIDGE_CELL_LEVEL.svg`](TURBO_TOP_SISO_FETCH_BRIDGE_CELL_LEVEL.svg)

## 6. Serializer

The serializer is the final scalar-output engine. It:

1. issues `ser_issue_idx`
2. derives:
   - `pair = idx / 2`
   - `is_odd = idx mod 2`
3. reads `FINAL_NAT_E` or `FINAL_NAT_O`
4. pipelines index and odd/even selection one cycle
5. emits `out_valid_q`, `out_idx_q`, and `l_post_q`

This is shown in:

- [`TURBO_TOP_SERIALIZER_CELL_LEVEL.svg`](TURBO_TOP_SERIALIZER_CELL_LEVEL.svg)

## 7. Control FSM

The actual active-state schedule is:

- `ST_IDLE`
- `ST_BUILD_SYS_INT`
- `ST_START_RUN`
- `ST_WAIT_RUN`
- `ST_EXT_NAT_TO_INT`
- `ST_EXT_INT_TO_NAT`
- `ST_FINAL_INT_TO_NAT`
- `ST_SERIALIZE`
- `ST_FINISH`

Important note:

- `ST_FEED_RUN` is still present in the type declaration, but in the current
  RTL it is not used in the active state transition path

So the true control figure should show the states above, not every enum symbol
as if it were live.

That schedule is shown in:

- [`TURBO_TOP_CONTROL_FSM_CELL_LEVEL.svg`](TURBO_TOP_CONTROL_FSM_CELL_LEVEL.svg)

## 8. Reading Convention

This package uses the same convention as the newer SISO, batcher, and QPP
cell-level packages:

- adder: circular `+`
- subtractor: circular `-`
- comparator / test: diamond
- mux: trapezoid `MUX`
- register / pipeline latch: storage block
- repeated blocks: first, `...`, last, with total count stated when relevant

These figures are exact-isomorphic with respect to the active RTL structure.
They are not post-synthesis gate-level netlists.
