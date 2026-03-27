# `siso_maxlogmap` Architecture Guide

This note explains [`rtl/siso_maxlogmap.vhd`](rtl/siso_maxlogmap.vhd) as a hardware block so you can draw the isomorphic architecture for the parallel turbo-decoder.

Important framing:
- The **parallel paper-aligned decoder** instantiates this SISO core **multiple times**. In [`rtl/turbo_decoder_top_parallel8_backup.vhd`](rtl/turbo_decoder_top_parallel8_backup.vhd), there are `8` copies of `siso_maxlogmap`.
- The **active folded top** instantiates only **one** copy of this same SISO core in [`rtl/turbo_decoder_top.vhd`](rtl/turbo_decoder_top.vhd).
- So if you understand **one** `siso_maxlogmap`, you understand the **per-lane SISO tile** of the parallel version.

## 1. What This Module Is

`siso_maxlogmap` is the **constituent decoder core**:
- one **max-log-MAP / M-BCJR SISO**
- **radix-4**
- **windowed**
- fixed-point
- supports terminated or non-terminated boundaries through `seg_first` / `seg_last`

Functionally, it does this:
1. Load a segment worth of paired LLRs into internal memories.
2. Compute forward state-metric seeds for each decoding window.
3. Decode windows from the end of the segment back to the beginning.
4. Produce extrinsic and posterior LLRs pair by pair.

The module is called `siso_maxlogmap`, but the actual algorithmic style is the paper’s **practical hardware max-log-MAP / M-BCJR** direction, not full floating BCJR.

## 2. Port-Level Meaning

Entity ports:

- `clk, rst`
  - synchronous clock/reset

- `start`
  - starts a new segment/frame decode transaction

- `seg_first`, `seg_last`
  - tell the core whether this segment is the first or last segment of a larger frame partition
  - these select the boundary state-metric seeds
  - in the active folded top they are tied to `'1'`, so the whole frame is treated as one segment
  - in the old parallel top they matter because each SISO handles one segment

- `seg_len`
  - number of information bits in the current segment

- `in_valid`, `in_pair_idx`
  - write interface for loading one **pair** of trellis inputs
  - one pair corresponds to two bit times: `(even, odd)`

- `sys_even`, `sys_odd`
- `par_even`, `par_odd`
- `apri_even`, `apri_odd`
  - the actual paired inputs
  - `sys_*` and `par_*` are `5`-bit channel/parity LLRs
  - `apri_*` is `6`-bit extrinsic/apriori input

- `out_valid`, `out_pair_idx`
  - valid flag and pair index for decoded output

- `ext_even`, `ext_odd`
  - computed extrinsic LLRs, `6` bits

- `post_even`, `post_odd`
  - posterior LLRs, `7` bits

- `done`
  - one-cycle completion pulse

## 3. Fixed-Point Contract

The relevant widths come from [`rtl/turbo_pkg.vhd`](rtl/turbo_pkg.vhd):

- `chan_llr_t`: signed `5` bits
- `ext_llr_t`: signed `6` bits
- `post_llr_t`: signed `7` bits
- `metric_t`: signed `10` bits
- number of trellis states: `8`
- window length: `30` trellis steps

Important helper behavior:

- `scale_ext(v)`
  - multiplies by `11/16`
  - this is the hardware-friendly extrinsic scaling used by the paper

- `mod_add`, `mod_sub`, `mod_max`
  - implement the module’s fixed-width **modulo-normalized** state-metric arithmetic
  - there is no explicit “subtract common offset from all states” block
  - instead, the fixed-width metric operations are used directly

## 4. High-Level Internal Architecture

You can draw the SISO core as these major blocks:

1. **Input Pair Loader**
   - stores incoming `(sys, par, apri)` pairs into internal memories

2. **Segment Pair Memories**
   - `sys_even_mem`, `sys_odd_mem`
   - `par_even_mem`, `par_odd_mem`
   - `apri_even_mem`, `apri_odd_mem`

3. **Branch-Metric / Gamma Generator**
   - `branch_metrics`
   - `pair_gamma`

4. **Radix-4 ACS Engine**
   - `acs_step`
   - reused for:
     - dummy forward
     - forward seed generation
     - dummy backward
     - local forward
     - local backward

5. **Alpha-Seed Memory**
   - `alpha_seed_ram`
   - explicit `simple_dp_bram`
   - stores one `8-state x 10-bit = 80-bit` alpha seed per window

6. **Local Window Buffers**
   - `gamma_local_mem`
   - `alpha_local_mem`
   - local `sys/par/apri` copies for the current window

7. **LLR Extraction Unit**
   - `extract_pair`
   - computes even and odd posterior/extrinsic LLRs from stored local data

8. **FSM / Schedule Controller**
   - the `state_t` machine
   - orchestrates all phases

9. **Output Register Block**
   - `out_valid_q`
   - `out_pair_idx_q`
   - `ext_*_q`
   - `post_*_q`
   - `done_q`

## 5. Why The Core Is Radix-4

The trellis is binary per bit, but the module processes **two trellis steps together**.

That is why the datapath is pair-based:
- inputs arrive as `(even, odd)`
- one `pair_gamma` call generates `16` metrics
- one `acs_step` advances the state metrics by **two bits**

So the core’s natural time unit is:
- **one pair**
- not one bit

This is the core reason the architecture uses:
- `in_pair_idx`
- `out_pair_idx`
- `C_PAIR_WIN = C_WINDOW / 2`

With `C_WINDOW = 30` bits:
- one window = `30` trellis steps
- one radix-4 window = `15` pair cycles

## 6. Internal Memories

### 6.1 Segment Memories

These six arrays store the whole segment:

- `sys_even_mem`
- `sys_odd_mem`
- `par_even_mem`
- `par_odd_mem`
- `apri_even_mem`
- `apri_odd_mem`

Each address stores data for one pair index.

What to draw:
- six logical RAMs
- common address generation under FSM control
- write path from `LOAD`
- read path into the gamma/local-forward/local-backward phases

These are tagged with:
- `attribute ram_style ... "block"`

So architecturally they are intended as BRAM-style frame memories.

### 6.2 Alpha Seed RAM

`alpha_seed_ram` stores:
- one alpha seed per window
- each seed = all `8` state metrics packed into one `80`-bit word

This is the bridge between:
- the forward seed-generation pass
- and the later per-window local decode pass

What to draw:
- one BRAM labeled `alpha_seed_ram`
- write port driven during `DUMMY_FWD` and `FWD_SEEDS`
- read port used during `LOAD_ALPHA_WAIT` / `LOAD_ALPHA`

### 6.3 Local Window Buffers

These are small arrays for only the current window:

- `gamma_local_mem`
- `alpha_local_mem`
- `sys_even_local_mem`, `sys_odd_local_mem`
- `par_even_local_mem`, `par_odd_local_mem`
- `apri_even_local_mem`, `apri_odd_local_mem`

Purpose:
- once a window’s backward seed is known, the module replays the window forward
- while replaying it stores all per-pair data locally
- then it walks backward through that local window to emit outputs

What to draw:
- a small local buffer bank beside the ACS/LLR extractor

## 7. Helper Functions and Their Architectural Meaning

### 7.1 `uniform_state`

Returns all-zero metrics.

Meaning:
- used as a non-terminated neutral seed
- used for dummy backward startup on interior windows

### 7.2 `terminated_state`

Returns:
- state `0` metric = `0`
- all other states = `-256`

Meaning:
- terminated boundary seed
- used when the segment is known to start or end in trellis state `0`

### 7.3 `branch_metrics`

Input:
- one bit’s `sys`, `par`, `apri`

Output:
- `4` branch metric candidates

Architecturally:
- this is the single-step BMU
- it expands the one-bit observation into the small candidate set needed later

### 7.4 `pair_gamma`

Input:
- one even/odd pair

Output:
- `16` radix-4 gamma values

Architecturally:
- this is the real radix-4 BMU
- it combines two single-step BMUs into one two-step metric table

Draw it as:
- `2 x branch_metrics`
- then a combine/add network producing `16` outputs

### 7.5 `acs_step`

This is the central radix-4 ACS engine.

Input:
- current state metric vector `state_in`
- radix-4 gamma vector `gamma_in`
- direction flag `is_backward`

Output:
- next state metric vector

Architectural behavior:

- **forward mode**
  - for each end state, find the best of the four predecessor paths

- **backward mode**
  - for each current state, find the best of the four successor paths

Important detail:
- the same ACS logic is reused for both directions
- the FSM changes the dataflow context

So in the architecture drawing, it is reasonable to draw:
- one **shared radix-4 ACS block**
- with a direction control input

### 7.6 `extract_pair`

This is the LLR extractor for one pair.

It does more than just `max1 - max0`.
It reconstructs the middle of the two-step trellis:

1. build `g0` for even bit
2. build `g1` for odd bit
3. compute `alpha_mid`
4. compute `beta_mid`
5. compute max metrics for the even-bit decision
6. compute max metrics for the odd-bit decision
7. form posterior LLRs
8. subtract channel/apriori to form extrinsic
9. scale extrinsic by `11/16`

This is the block you should draw as:
- **LLR extraction unit**
- with sub-blocks:
  - midpoint alpha reconstruction
  - midpoint beta reconstruction
  - even-bit max comparator tree
  - odd-bit max comparator tree
  - posterior subtractor
  - extrinsic subtractor
  - extrinsic scaler

### 7.7 `window_pairs_for`

This function converts:
- window index
- segment length

into:
- number of valid pair entries in that window

Architecturally:
- this is control logic, not a datapath block
- it handles the shorter final window

## 8. FSM State-by-State Meaning

This is the most important part for your drawing because the core is highly time-multiplexed.

### `IDLE`

Role:
- wait for `start`
- capture `seg_len`
- compute:
  - `pair_cnt = ceil(seg_len/2)`
  - `win_cnt = ceil(seg_len/C_WINDOW)`

Transition:
- `start` -> `LOAD`

### `LOAD`

Role:
- accept the entire segment through the pair input port
- fill the six segment memories

Inputs active:
- `in_valid`
- `in_pair_idx`
- `sys_even/sys_odd`
- `par_even/par_odd`
- `apri_even/apri_odd`

Transition:
- after last pair loaded -> `DUMMY_FWD`

### `DUMMY_FWD`

Role:
- run one dummy forward pass on the first window
- then write window-0 alpha seed

Architectural meaning:
- warm-up stage before regular seed generation

Transition:
- end of first window -> `FWD_SEEDS`

### `FWD_SEEDS`

Role:
- walk forward over all windows
- compute the alpha seed for every window
- write them into `alpha_seed_ram`

Architectural meaning:
- precomputation phase for later window-local decode

Transition:
- after last window seed is established -> `PREP_WINDOW`

### `PREP_WINDOW`

Role:
- prepare backward seed for the current window

Two cases:
- if current window is the last window:
  - backward seed comes from `end_seed_v`
- otherwise:
  - backward seed is produced by dummy backward recursion over the next window

Transition:
- last window -> `LOAD_ALPHA_WAIT`
- otherwise -> `DUMMY_BWD`

### `DUMMY_BWD`

Role:
- run backward recursion over window `m+1`
- obtain the beta seed for window `m`

Architectural meaning:
- this is the paper’s dummy backward recursion idea

Transition:
- when next window has been fully traversed backward -> `LOAD_ALPHA_WAIT`

### `LOAD_ALPHA_WAIT`

Role:
- wait one cycle for the synchronous alpha-seed BRAM read

Architectural meaning:
- explicit BRAM latency compensation

Transition:
- next cycle -> `LOAD_ALPHA`

### `LOAD_ALPHA`

Role:
- unpack alpha seed from `alpha_seed_ram`
- load it into `alpha_work`

Transition:
- immediately -> `LOCAL_FWD`

### `LOCAL_FWD`

Role:
- replay the current window forward from its alpha seed
- store all local information needed for LLR extraction:
  - alpha at each pair
  - gamma at each pair
  - local sys/par/apri values

Architectural meaning:
- this is the local window pre-buffering phase

Transition:
- end of window -> `LOCAL_BWD`

### `LOCAL_BWD`

Role:
- traverse the buffered window backward
- for each pair:
  - compute `ext_even/ext_odd`
  - compute `post_even/post_odd`
  - emit outputs
  - update backward metrics

This is the only state that asserts:
- `out_valid`

Transition:
- if more pairs remain in this window -> stay in `LOCAL_BWD`
- if window done and more windows remain -> `PREP_WINDOW`
- if first window done -> `FINISH`

### `FINISH`

Role:
- pulse `done`

Transition:
- next cycle -> `IDLE`

## 9. Actual Scheduling Across Time

A good way to think about the module is:

1. **Load whole segment**
2. **Forward pre-pass**
   - dummy forward on first window
   - forward seed generation for all windows
3. **Backward/local decode pass**
   - process windows from last to first
   - for each window:
     - derive beta seed
     - read alpha seed
     - replay local forward
     - run local backward + emit LLRs

This means the module is **not** a fully streaming decoder.
It is:
- segment-buffered
- window-scheduled
- heavily hardware-reused

## 9A. Timing View For One Window

This is the part that usually causes confusion.

For one target window `Wm`, the module does **not** simply start with:
- forward on `Wm`
- backward on `Wm`

Instead, the timing is:

```text
Whole segment:

LOAD all pair LLRs
    |
    v
Global forward seed prepass over windows:
    DUMMY_FWD on W0
    FWD_SEEDS on W0, W1, W2, ... , Wm, ... , Wlast
    -> store alpha seed of each window into alpha_seed_ram

Then for target window Wm:

    if Wm is not the last window:
        DUMMY_BWD on Wm+1
        -> derive beta seed for Wm
    else
        use end boundary seed directly

    LOAD_ALPHA_WAIT / LOAD_ALPHA
        -> read alpha seed of Wm from alpha_seed_ram

    LOCAL_FWD on Wm
        -> replay Wm forward
        -> store local alpha/gamma/sys/par/apri into local buffers

    LOCAL_BWD on Wm
        -> walk Wm backward
        -> compute post/ext LLRs
        -> emit output pairs
```

So the window-local processing order is:

1. get `beta` boundary for the window
2. read stored `alpha` boundary for the window
3. run **local forward replay** across the whole window
4. run **local backward** across the same window
5. emit outputs during the backward walk

This means:
- yes, for the final local decode of one window, the RTL completes the window's forward replay first
- then backward recursion starts
- but that happens **after** the earlier global alpha-seed prepass, and usually after a dummy backward over the next window

### Compact Per-Window State Sequence

If `Wm` is an interior window:

```text
PREP_WINDOW
  -> DUMMY_BWD over Wm+1
  -> LOAD_ALPHA_WAIT
  -> LOAD_ALPHA
  -> LOCAL_FWD over Wm
  -> LOCAL_BWD over Wm
```

If `Wm` is the last window:

```text
PREP_WINDOW
  -> LOAD_ALPHA_WAIT
  -> LOAD_ALPHA
  -> LOCAL_FWD over Wm
  -> LOCAL_BWD over Wm
```

### What Happens Inside `LOCAL_FWD` And `LOCAL_BWD`

During `LOCAL_FWD`:
- the ACS runs in forward mode
- one pair is processed per cycle
- `alpha_local_mem(work_local_idx)` stores the entering alpha state vector
- `gamma_local_mem(work_local_idx)` stores the radix-4 branch metrics
- local `sys/par/apri` memories store the observations for later LLR extraction

During `LOCAL_BWD`:
- the ACS runs in backward mode
- one pair is processed per cycle in reverse order
- `extract_pair` uses:
  - stored local alpha
  - current beta
  - stored local observations
- the module outputs `ext_even/ext_odd` and `post_even/post_odd`

### Why The Forward Replay Is Needed

The window cannot jump directly from alpha seed and beta seed to outputs unless the per-pair alpha and gamma values inside that window are available.

That is why `LOCAL_FWD` exists:
- it reconstructs the internal forward history of the selected window
- and stores it in local buffers

Then `LOCAL_BWD` can combine:
- local alpha history
- running beta history
- branch metrics

to compute the pair LLRs.

## 10. What To Draw For The Isomorphic Architecture

If your goal is a clean architecture drawing, draw these boxes:

### Top-Level SISO Tile

- Input load interface
- Segment pair memories
- Radix-4 gamma/BMU block
- Shared radix-4 ACS block
- Alpha-seed BRAM
- Local window buffer bank
- LLR extraction block
- FSM controller
- Output register block

### Suggested Connectivity

1. Input loader writes into segment memories.
2. Segment memories feed gamma/BMU during:
   - dummy forward
   - forward seeds
   - dummy backward
   - local forward
3. Gamma/BMU feeds shared ACS.
4. Shared ACS updates:
   - `alpha_work`
   - `beta_work`
5. Forward seed values are packed and written into alpha-seed BRAM.
6. Alpha-seed BRAM read gives starting alpha for a selected window.
7. Local forward fills local window buffers.
8. Local backward plus LLR extractor emit output pairs.

### Controller Signals To Show

- `work_win_idx`
- `work_local_idx`
- `load_idx`
- `alpha_seed_rd_addr`
- `alpha_seed_wr_addr`
- direction control for ACS (`forward/backward`)
- output valid/done

## 11. How This Maps Into The Parallel Version

For the paper-aligned parallel version:
- draw **one** `siso_maxlogmap` tile exactly as above
- then annotate it as **replicated x8**

What changes in the parallel architecture is mostly outside this core:
- QPP scheduler
- Batcher routing
- folded/multiport memory system
- iteration control
- inter-core synchronization

What does **not** fundamentally change:
- each lane still contains one SISO datapath of this kind

In [`rtl/turbo_decoder_top_parallel8_backup.vhd`](rtl/turbo_decoder_top_parallel8_backup.vhd):
- each SISO instance gets one segment
- `seg_first` is asserted only for the first core
- `seg_last` is asserted only for the last core

So for the parallel-architecture figure:
- the SISO tile is replicated
- the per-tile boundary seed behavior differs at the outer edges

## 12. Segmentation vs Windowing

These are different.

### Segmentation

- partition the full `K` block across multiple SISOs
- used by the parallel version
- example: `8` cores each decode one contiguous segment

### Windowing

- inside one SISO, decode the assigned segment in smaller windows
- used inside `siso_maxlogmap`
- example: `30`-bit windows

So the hierarchy is:
- full frame
  - segmented across cores in the parallel version
    - each segment is windowed inside one `siso_maxlogmap`

## 13. One Good Drawing Strategy

Make three drawings instead of one overloaded figure:

### Drawing A: Black-Box SISO Tile

Show:
- ports
- memories
- ACS
- LLR extraction
- controller

### Drawing B: Datapath Inside The Tile

Show:
- branch metric generation
- pair gamma generation
- forward/backward ACS reuse
- alpha-seed BRAM
- local window buffers
- LLR extractor internals

### Drawing C: FSM / Schedule

Show the state chain:
- `IDLE`
- `LOAD`
- `DUMMY_FWD`
- `FWD_SEEDS`
- `PREP_WINDOW`
- `DUMMY_BWD`
- `LOAD_ALPHA_WAIT`
- `LOAD_ALPHA`
- `LOCAL_FWD`
- `LOCAL_BWD`
- `FINISH`

If you do these three separately, the final parallel architecture figure becomes much easier:
- one SISO tile
- replicated eight times
- surrounded by scheduler/router/memory blocks

## 14. Short Version

The clean one-line description is:

`siso_maxlogmap` is a fixed-point, radix-4, windowed max-log-MAP constituent decoder that buffers one segment, precomputes per-window alpha seeds, derives per-window beta seeds through dummy backward recursion, replays each window locally, and emits scaled extrinsic/posterior LLRs pair by pair under a time-multiplexed FSM.

## 15. Next Useful Step

After you draw this SISO tile, the next module to explain for the parallel paper-aligned architecture should be:

1. `qpp_parallel_scheduler`
2. `batcher_master` / `batcher_slave` / `batcher_router`
3. `multiport_row_bram`
4. `turbo_iteration_ctrl`

## 16. Rendered Diagram Files

The repo now contains three rendered architecture views for this module:

- [`SISO_MAXLOGMAP_ARCHITECTURE.svg`](SISO_MAXLOGMAP_ARCHITECTURE.svg)
  - combined architecture overview
- [`SISO_MAXLOGMAP_DATAPATH.svg`](SISO_MAXLOGMAP_DATAPATH.svg)
  - datapath-only view
- [`SISO_MAXLOGMAP_CONTROL.svg`](SISO_MAXLOGMAP_CONTROL.svg)
  - control / FSM schedule view

The corresponding editable Graphviz sources are:

- [`SISO_MAXLOGMAP_ARCHITECTURE.dot`](SISO_MAXLOGMAP_ARCHITECTURE.dot)
- [`SISO_MAXLOGMAP_DATAPATH.dot`](SISO_MAXLOGMAP_DATAPATH.dot)
- [`SISO_MAXLOGMAP_CONTROL.dot`](SISO_MAXLOGMAP_CONTROL.dot)

That ordering matches the way the parallel architecture wraps around the SISO cores.
