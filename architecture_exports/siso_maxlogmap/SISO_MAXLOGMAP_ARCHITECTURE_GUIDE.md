# `siso_maxlogmap` Architecture Guide

This export package documents the **current** [`rtl/siso_maxlogmap.vhd`](../../rtl/siso_maxlogmap.vhd), after the rolling-window rewrite.

Important context:
- The saved paper-aligned parallel top still instantiates this block as the per-lane SISO tile.
- The active folded top also instantiates this block, but with `G_USE_EXTERNAL_FETCH = true`.
- So the exported diagrams here describe the **updated SISO RTL**, not the older alpha-seed-prepass version.

## 1. What Changed Architecturally

The old exported SISO view is obsolete in three major ways:
- there is no longer a whole-segment alpha-seed prepass
- there is no longer an `alpha_seed_ram` / `LOAD_ALPHA_*` path
- LLR extraction no longer recomputes branch metrics; it reuses locally stored `g0`, `g1`, and radix-4 `gamma`

The new schedule is the rolling-window scheme:
1. optional legacy `LOAD` of the whole segment into internal RAMs
2. forward recursion on the current window, storing local `alpha/g0/g1/gamma`
3. dummy backward recursion on the next window to derive the current window beta seed
4. local backward recursion on the current window, emitting `ext/post`
5. carry the current window end-alpha forward as the next window start seed

## 2. Two Feed Modes

The RTL now supports two input modes.

### Legacy Load Mode

Used by:
- standalone SISO testbenches
- any instantiation with `G_USE_EXTERNAL_FETCH = false`

Behavior:
- `LOAD` fills six segment memories:
  - `sys_even_mem`, `sys_odd_mem`
  - `par_even_mem`, `par_odd_mem`
  - `apri_even_mem`, `apri_odd_mem`
- later states read pairs from these memories

### External Fetch Mode

Used by:
- the active folded top [`rtl/turbo_decoder_top.vhd`](../../rtl/turbo_decoder_top.vhd)

Behavior:
- the SISO asserts:
  - `fetch_req_valid`
  - `fetch_req_pair_idx`
- the top returns one requested pair using:
  - `fetch_rsp_valid`
  - the existing `sys/par/apri` input ports as the response payload

Architecturally this means the active top no longer bulk-loads the SISO with a whole segment first.

## 3. Port Meaning

Core ports:
- `clk`, `rst`, `start`
- `seg_first`, `seg_last`, `seg_len`
- `out_valid`, `out_pair_idx`, `ext_even`, `ext_odd`, `post_even`, `post_odd`, `done`

Legacy load-mode ports:
- `in_valid`, `in_pair_idx`
- `sys_even`, `sys_odd`
- `par_even`, `par_odd`
- `apri_even`, `apri_odd`

External-fetch control ports:
- `fetch_req_valid`
- `fetch_req_pair_idx`
- `fetch_rsp_valid`

In external-fetch mode, the returned pair data still arrives on:
- `sys_even`, `sys_odd`
- `par_even`, `par_odd`
- `apri_even`, `apri_odd`

## 4. Fixed-Point Contract

From [`rtl/turbo_pkg.vhd`](../../rtl/turbo_pkg.vhd):
- `chan_llr_t`: signed 5 bits
- `ext_llr_t`: signed 6 bits
- `post_llr_t`: signed 7 bits
- `metric_t`: signed 10 bits
- `C_NUM_STATES = 8`
- `C_WINDOW = 30` bits, so `C_PAIR_WIN = 15`

Algorithmic style retained:
- radix-4 processing
- max-log-MAP style metric recursion
- fixed-width modulo arithmetic through `mod_add/mod_sub/mod_max`
- `11/16` extrinsic scaling through `scale_ext`

## 5. High-Level Block Decomposition

The current SISO tile is best drawn as these blocks:

1. **Segment setup / boundary selector**
   - `seg_len`, `seg_first`, `seg_last`
   - computes `pair_cnt`, `win_cnt`
   - chooses `start_seed_v` and `end_seed_v`

2. **Optional legacy segment RAM bank**
   - only used when `G_USE_EXTERNAL_FETCH = false`
   - six memories for `sys/par/apri`

3. **Pair fetch front-end**
   - either:
     - reads a pair from legacy segment RAMs
     - or requests a pair through `fetch_req_*`
   - latches one returned pair into `fetched_*_q`

4. **Forward branch/gamma path**
   - `branch_metrics` for even and odd
   - `pair_gamma_from_branches`
   - forward `acs_step`
   - writes local window buffers

5. **Local window buffer bank**
   - `alpha_local_mem`
   - `gamma_local_mem`
   - `g0_local_mem`
   - `g1_local_mem`
   - `sys_even_local_mem`, `sys_odd_local_mem`
   - `apri_even_local_mem`, `apri_odd_local_mem`

6. **Dummy backward path**
   - fetches pairs from the next window
   - computes `gamma`
   - runs backward `acs_step`
   - produces the current-window beta seed

7. **Local backward + LLR extraction**
   - reads stored local alpha/gamma/branch data
   - runs `extract_pair_precomp`
   - updates `beta_work`
   - emits outputs

8. **Rolling alpha carry**
   - `next_alpha_seed_reg`
   - stores only one boundary alpha vector: the end-alpha of the current window

## 6. What Is No Longer Present

These old architectural blocks are gone from the updated SISO:
- `DUMMY_FWD`
- `FWD_SEEDS`
- `PREP_WINDOW`
- `LOAD_ALPHA_WAIT`
- `LOAD_ALPHA`
- `LOCAL_FWD`
- `alpha_seed_ram`
- `pack_state_metric`
- `unpack_state_metric`

So do not draw the previous “global forward seed pass + per-window seed BRAM” architecture anymore.

## 7. Updated State Machine

Current states:
- `IDLE`
- `LOAD`
- `FWD_REQ`
- `FWD_WAIT`
- `FWD_STEP`
- `DUMMY_REQ`
- `DUMMY_WAIT`
- `DUMMY_STEP`
- `LOCAL_BWD`
- `FINISH`

State meaning:

### `IDLE`
- wait for `start`
- clamp `seg_len`
- compute `pair_cnt` and `win_cnt`
- initialize `alpha_work` with the correct segment-start seed
- branch to `LOAD` or directly to `FWD_REQ`

### `LOAD`
- legacy mode only
- capture incoming pairs into the six segment memories

### `FWD_REQ` / `FWD_WAIT`
- request or read the current-window pair at `work_win_idx * C_PAIR_WIN + work_local_idx`
- load it into `fetched_*_q`

### `FWD_STEP`
- compute `g0`, `g1`, and radix-4 `gamma`
- store current-pair local context
- advance forward `alpha_work`
- if end of current window:
  - save `next_alpha_seed_reg`
  - either start `DUMMY_REQ` on the next window
  - or go directly to `LOCAL_BWD` for the last window

### `DUMMY_REQ` / `DUMMY_WAIT`
- request or read one pair from the next window, walking backward

### `DUMMY_STEP`
- compute dummy backward recursion over the next window
- when the next window is exhausted, the resulting `beta_work` becomes the current-window beta seed
- then jump to `LOCAL_BWD`

### `LOCAL_BWD`
- walk the current window backward
- use stored `alpha/gamma/g0/g1/sys/apri`
- compute `post/ext`
- emit outputs
- when the current window is done:
  - either advance to the next window and restart at `FWD_REQ`
  - or finish

### `FINISH`
- pulse `done`

## 8. Core Scheduling Idea

For window `Wm`, the current RTL does:

```text
forward on Wm
  -> store local alpha/g0/g1/gamma

dummy backward on Wm+1
  -> derive beta seed for Wm

local backward on Wm
  -> emit outputs for Wm

carry end-alpha(Wm)
  -> start alpha for Wm+1
```

So unlike the old version:
- windows are processed in forward order `W0, W1, W2, ...`
- there is no whole-segment forward prepass
- only one window of detailed alpha history is buffered at a time

## 9. Datapath Meaning

The most important datapath fact in the new RTL is:
- `extract_pair_precomp` takes precomputed `g0` and `g1`
- `LOCAL_BWD` reuses stored `gamma_local_mem`

That means:
- branch metrics are computed once per pair in `FWD_STEP`
- radix-4 gamma is computed once per pair in `FWD_STEP`
- LLR extraction reuses cached branch data instead of rebuilding it

## 10. Control Meaning

The most important control changes are:
- new fetch handshake controller
- new rolling window controller
- no alpha-seed BRAM controller
- no reverse-order window decode

The controller now manages:
- optional preload
- pair fetch issue/wait
- current-window forward traversal
- next-window dummy backward traversal
- current-window local backward emission

## 11. Drawing Guidance

For the updated SISO, draw three views:

### Combined Architecture
- optional segment RAM bank
- fetch front-end
- branch/gamma unit
- shared ACS
- local window buffers
- local backward/LLR extractor
- rolling alpha register
- FSM

### Datapath View
- fetched pair latch
- `branch_metrics` x2
- `pair_gamma_from_branches`
- forward/backward shared `acs_step`
- local caches
- `extract_pair_precomp`

### Control View
- `LOAD` path
- fetch request / wait states
- forward step
- dummy backward step
- local backward emit
- finish

## 12. Diagram Files

- [`SISO_MAXLOGMAP_ARCHITECTURE.svg`](SISO_MAXLOGMAP_ARCHITECTURE.svg)
- [`SISO_MAXLOGMAP_DATAPATH.svg`](SISO_MAXLOGMAP_DATAPATH.svg)
- [`SISO_MAXLOGMAP_CONTROL.svg`](SISO_MAXLOGMAP_CONTROL.svg)
- [`internal_units/`](internal_units/)
- [`internal_control/`](internal_control/)
