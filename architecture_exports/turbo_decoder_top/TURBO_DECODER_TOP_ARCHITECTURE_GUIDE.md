# `turbo_decoder_top` Architecture Guide

This note explains the **current active top** [`rtl/turbo_decoder_top.vhd`](../../rtl/turbo_decoder_top.vhd).

It is the folded single-SISO implementation, not the paper-aligned `parallel8` backup.

## 1. High-Level Role

`turbo_decoder_top` is a complete iterative LTE-style turbo decoder built around:
- one `siso_maxlogmap`
- BRAM-backed natural/interleaved channel memories
- BRAM-backed extrinsic and posterior memories
- QPP permutation logic implemented inside the top FSM

It performs:
1. input frame load into natural-domain memories
2. construction of interleaved systematic memory
3. alternating natural/interleaved half-iterations through one shared SISO
4. BRAM-based extrinsic permutation between domains
5. final natural-domain posterior serialization

## 2. Major Architectural Blocks

### 2.1 Input Memory System

Channel BRAM groups:
- `C_CH_SYS_NAT_E`, `C_CH_SYS_NAT_O`
- `C_CH_PAR1_NAT_E`, `C_CH_PAR1_NAT_O`
- `C_CH_SYS_INT_E`, `C_CH_SYS_INT_O`
- `C_CH_PAR2_INT_E`, `C_CH_PAR2_INT_O`

Extrinsic BRAM groups:
- `C_EXT_NAT_E`, `C_EXT_NAT_O`
- `C_EXT_INT_E`, `C_EXT_INT_O`

Posterior BRAM groups:
- `C_POST_INT_E`, `C_POST_INT_O`
- `C_FINAL_NAT_E`, `C_FINAL_NAT_O`

All of these are implemented with [`rtl/simple_dp_bram.vhd`](../../rtl/simple_dp_bram.vhd).

### 2.2 QPP / Permutation Controller

The top computes the QPP sequence with the rolling recurrence:
- `qpp_curr_i`
- `qpp_delta_i`
- `qpp_step_i`

This is used for:
- building `SYS_INT`
- `EXT_NAT -> EXT_INT`
- `EXT_INT -> EXT_NAT`
- `POST_INT -> FINAL_NAT`

### 2.3 Shared SISO Engine

The top instantiates one [`rtl/siso_maxlogmap.vhd`](../../rtl/siso_maxlogmap.vhd) as `siso_u`.

Important active setting:
- `G_USE_EXTERNAL_FETCH => true`

So the top no longer streams a whole segment into the SISO.
Instead it services pair requests on demand from its BRAMs.

### 2.4 SISO Fetch Service

During an active run:
- `siso_u` asserts `fetch_req_valid` and `fetch_req_pair_idx`
- the top issues BRAM reads for the requested pair
- after the read pipeline delay, the top returns:
  - `fetch_rsp_valid`
  - the requested `sys/par/apri` values on the SISO input ports

This is the main architectural change relative to the older folded top export.

### 2.5 Run Writeback

While `run_active = '1'` and `siso_out_valid = '1'`:
- natural run writes `EXT_NAT`
- interleaved run writes `EXT_INT` and `POST_INT`
- final natural run additionally writes `FINAL_NAT`

### 2.6 Final Serializer

The final stage reads `FINAL_NAT_E/O` and emits one bit-position posterior at a time on:
- `out_valid`
- `out_idx`
- `l_post`

## 3. Control States

Current state enum:
- `ST_IDLE`
- `ST_BUILD_SYS_INT`
- `ST_START_RUN`
- `ST_FEED_RUN`
- `ST_WAIT_RUN`
- `ST_EXT_NAT_TO_INT`
- `ST_EXT_INT_TO_NAT`
- `ST_FINAL_INT_TO_NAT`
- `ST_SERIALIZE`
- `ST_FINISH`

Important note:
- `ST_FEED_RUN` is now vestigial in the active behavior
- the fetch-based top transitions from `ST_START_RUN` directly to `ST_WAIT_RUN`

## 4. State Meaning

### `ST_IDLE`
- load incoming frame bits and channel/parity LLRs into BRAMs
- capture `k_len`, `n_half_iter`, `f1`, `f2`
- initialize QPP recurrence

### `ST_BUILD_SYS_INT`
- QPP-read natural `SYS`
- write interleaved `SYS_INT`

### `ST_START_RUN`
- configure natural vs interleaved run
- assert `siso_start_q`
- clear fetch pipeline state

### `ST_WAIT_RUN`
- keep `run_active`
- service SISO fetch requests from BRAM
- capture SISO outputs into extrinsic/posterior BRAMs
- wait for `siso_done`

### `ST_EXT_NAT_TO_INT`
- QPP-permute natural extrinsic to interleaved domain

### `ST_EXT_INT_TO_NAT`
- inverse-QPP-permute interleaved extrinsic back to natural domain

### `ST_FINAL_INT_TO_NAT`
- inverse-QPP-permute final interleaved posterior into `FINAL_NAT`

### `ST_SERIALIZE`
- read `FINAL_NAT_E/O`
- emit `l_post` by natural bit order

### `ST_FINISH`
- pulse `done`

## 5. Datapath View

The active top datapath is best drawn as:

```text
input loader
  -> natural/systematic/parity BRAMs
  -> interleaved systematic build path
  -> one shared SISO
  -> ext/post writeback BRAMs
  -> QPP permutation paths
  -> final serializer
```

What changed from the older folded-top description:
- there is no top-to-SISO bulk feed stage anymore
- the SISO is serviced through an on-demand fetch responder

## 6. Control View

The top control is a monolithic FSM plus a few service pipelines:
- main FSM `st`
- QPP recurrence registers
- SISO fetch-return pipeline:
  - `siso_fetch_rd_pending_q`
  - `siso_fetch_rsp_pending_q`
- serializer pipeline

## 7. Relationship To Exported Packages

- [`../parallel8_top/`](../parallel8_top/) documents the paper-aligned backup architecture
- [`../siso_maxlogmap/`](../siso_maxlogmap/) documents the updated rolling-window SISO used here

So the active folded-top architecture is:
- one current `siso_maxlogmap`
- reused across all half-iterations
- surrounded by BRAM-based natural/interleaved storage and QPP permutation control

## 8. Diagram Files

- [`TURBO_DECODER_TOP_ARCHITECTURE.svg`](TURBO_DECODER_TOP_ARCHITECTURE.svg)
- [`TURBO_DECODER_TOP_DATAPATH.svg`](TURBO_DECODER_TOP_DATAPATH.svg)
- [`TURBO_DECODER_TOP_CONTROL.svg`](TURBO_DECODER_TOP_CONTROL.svg)
