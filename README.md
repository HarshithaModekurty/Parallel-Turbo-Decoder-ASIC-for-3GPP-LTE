# Parallel Turbo Decoder ASIC for 3GPP LTE

This repository contains a paper-oriented RTL implementation of the architecture described in `11JSSC-turbo.pdf`.

## Current Implemented Architecture

Implemented now:
- Scalar external top-level interface for the existing vector/test flow.
- Internal `N = 8` segmented parallel datapath for `K % 8 = 0`.
- Paper-aligned fixed-point contract:
  - channel/systematic/parity LLRs: 5-bit signed
  - extrinsic LLRs: 6-bit signed
  - posterior LLRs: 7-bit signed
  - state metrics: 10-bit signed
- An 8-lane parallel QPP scheduler.
- Explicit 8-lane master/slave Batcher interleaver path:
  - `batcher_master.vhd`
  - `batcher_slave.vhd`
  - `batcher_router.vhd`
- Folded-memory style top-level datapath for systematic, parity, extrinsic, and final-posterior storage.
- Half-iteration control through `n_half_iter`.
- Windowed radix-4 SISO with:
  - `M = 30` trellis-step windows
  - one dummy forward warm-up window
  - dummy backward recursion on window `m + 1` to seed window `m`
  - explicit odd-step LLR reconstruction from radix-2 branch metrics
- End-to-end LTE-like stimulus generation, RTL simulation, synth check, and floating/fixed reference comparison.

Implemented with explicit current assumptions:
- Outer frame boundaries use terminated-state seeds for the first and last internal segments.
- Interior segment boundaries still use approximated state metrics because the active top level does not yet deliver explicit overlap windows or tail-symbol evidence.
- Exact fixed-point agreement currently holds only for the checked `K = 40`, `n_half_iter = 11` regression point.

Not implemented yet:
- Standards-faithful overlap/tail delivery into the active RTL datapath.
- Exact fixed-point closure for larger deterministic regressions beyond the currently covered `K = 40` point.

## Main RTL Files

- `rtl/turbo_pkg.vhd`
  - fixed-point types, saturation helpers, modulo helpers, LTE trellis helpers, QPP helper, Batcher control width
- `rtl/siso_maxlogmap.vhd`
  - active windowed radix-4 SISO with dummy-recursion scheduling; this now contains the active branch-metric, ACS, and LLR-extraction logic internally
- `rtl/qpp_parallel_scheduler.vhd`
  - computes 8 QPP addresses for one folded row group
- `rtl/batcher_master.vhd`
  - 8-lane Batcher sorting network that emits sorted addresses, lane permutation, and switch controls
- `rtl/batcher_slave.vhd`
  - 8-lane permutation network that applies or reverses the stored lane permutation
- `rtl/batcher_router.vhd`
  - convenience wrapper around the master/slave Batcher path
- `rtl/folded_llr_ram.vhd`
  - retained folded row-word RAM wrapper
- `rtl/turbo_iteration_ctrl.vhd`
  - half-iteration controller
- `rtl/turbo_decoder_top.vhd`
  - scalar-stream external top with internal 8-core folded segmented datapath

## Testbenches

- `tb/tb_qpp_parallel_scheduler.vhd`
- `tb/tb_batcher_router.vhd`
- `tb/tb_folded_llr_ram.vhd`
- `tb/tb_siso_smoke.vhd`
- `tb/tb_siso_windowed_compare.vhd`
- `tb/tb_siso_vector_compare.vhd`
- `tb/tb_turbo_top.vhd`

## Default Regression Flow

Run:
- `python tools/run_lte_pipeline.py`

This performs:
1. LTE-like frame generation with terminated RSC encoders and AWGN channel.
2. 5-bit input LLR quantization.
3. Floating and fixed-point reference generation.
4. Full GHDL compile/elaborate/sim run for the active unit and integration TBs.
5. Fixed and floating reference comparison in original-domain indexing.
6. A synth check for `turbo_decoder_top`.
7. Per-`K` archiving of the top-level report and comparison logs.

## Current Default Regression Point

Command:
- `python tools/run_lte_pipeline.py --k 40 --n-half-iter 11 --snr-db 1.5 --seed 12345`

Default quantization setting:
- `llr_scale = 2.0`

Current results:
- all active RTL and TBs compile/elaborate with GHDL `--std=08`
- `ghdl --synth --std=08 turbo_decoder_top` passes
- all active TBs pass
- `tb_turbo_top` output coverage: `40/40`
- `bit_errors_vs_original = 36`
- `hard_errors_vs_fixed_reference = 0`
- `hard_errors_vs_floating_reference = 6`

Additional archived regression points:
- `K = 3200`: `hard_errors_vs_fixed_reference = 830`
- `K = 6144`: `hard_errors_vs_fixed_reference = 1571`
- see `MULTI_K_REGRESSION_REPORT.md`

## Output Artifacts

- `sim_vectors/lte_frame_input_vectors.txt`
- `sim_vectors/lte_frame_generation_report.txt`
- `sim_vectors/reference_interleaved.txt`
- `sim_vectors/reference_original.txt`
- `sim_vectors/reference_fixed_interleaved.txt`
- `sim_vectors/reference_fixed_original.txt`
- `sim_vectors/rtl_vs_reference_report.txt`
- `tb_turbo_top_io_trace.txt`
- `tb_turbo_top_report.txt`
- `sim_logs/*.log`
- `synth_check.log`
- `synth_stderr.log`

## Assumptions

See `ASSUMPTION_LOG.md` for the full assumption/deviation record. The short version is:

1. Max-log-MAP is used, not full log-MAP.
2. The active top-level currently targets `K % 8 = 0`.
3. `n_half_iter` is the canonical decode-stop contract.
4. Interior segment boundaries are still approximated because overlap-window and explicit tail-symbol delivery are not yet part of the active public RTL interface.
5. The QPP parameter table is sourced from the LTE standard.

## Documents

- `PAPER_IMPLEMENTATION_REPORT.md`
- `ARCHITECTURE_THEORY_WRITEUP.md`
- `SIMULATION_RESULTS.md`
- `FINAL_VALIDATION_REPORT.md`
- `MULTI_K_REGRESSION_REPORT.md`
- `ASSUMPTION_LOG.md`
