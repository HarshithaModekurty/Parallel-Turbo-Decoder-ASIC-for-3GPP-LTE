# Parallel Turbo Decoder ASIC for 3GPP LTE

This `codex-branch` worktree contains the current paper-oriented RTL rewrite for the architecture described in `11JSSC-turbo.pdf`.

## Current Implemented Architecture

Implemented now:
- Scalar external top-level interface for compatibility with the existing vector/test flow.
- Internal `N = 8` segmented parallel datapath for `K % 8 = 0`.
- Paper-aligned fixed-point contract:
  - channel/systematic/parity LLRs: 5-bit signed
  - extrinsic LLRs: 6-bit signed
  - posterior LLRs: 7-bit signed
  - state metrics: 10-bit signed
- Recursive scalar QPP generator and an 8-lane parallel QPP scheduler.
- Explicit master/slave Batcher path:
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
- Outer frame boundaries now use terminated-state seeds for the first and last internal segments.
- Interior segment boundaries still use uniform state-metric assumptions because the current public RTL interface does not carry overlap-window or explicit tail-symbol inputs.
- The fixed-point Python model is exact for the active `K = 40`, `n_half_iter = 11` regression and matches the RTL bit-for-bit in original-domain outputs.

Not implemented yet:
- Standards-faithful overlap/tail delivery into the active RTL datapath.
- Exact fixed-point closure for larger deterministic regressions beyond the currently covered `K = 40` point.

## Main RTL Files

- `rtl/turbo_pkg.vhd`
  - fixed-point types, saturation helpers, modulo helpers, LTE trellis helpers, QPP helper
- `rtl/branch_metric_unit.vhd`
  - radix-2 branch-metric primitive
- `rtl/radix4_bmu.vhd`
  - 16-entry radix-4 branch-metric vector generation
- `rtl/radix4_acs.vhd`
  - radix-4 forward/backward ACS update
- `rtl/radix4_extractor.vhd`
  - pairwise posterior and scaled extrinsic computation
- `rtl/siso_maxlogmap.vhd`
  - active windowed radix-4 SISO with dummy-recursion scheduling
- `rtl/qpp_interleaver.vhd`
  - recursive scalar QPP address generator
- `rtl/qpp_parallel_scheduler.vhd`
  - computes 8 QPP addresses for one folded row group
- `rtl/batcher_master.vhd`
  - sorts interleaved addresses and emits permutation order
- `rtl/batcher_slave.vhd`
  - applies the permutation or its reverse for writeback
- `rtl/folded_llr_ram.vhd`
  - folded row-word RAM wrapper
- `rtl/turbo_iteration_ctrl.vhd`
  - half-iteration controller
- `rtl/turbo_decoder_top.vhd`
  - scalar-stream external top with internal 8-core folded segmented datapath

## Testbenches

- `tb/tb_qpp_interleaver.vhd`
- `tb/tb_qpp_parallel_scheduler.vhd`
- `tb/tb_batcher_router.vhd`
- `tb/tb_folded_llr_ram.vhd`
- `tb/tb_radix4_acs.vhd`
- `tb/tb_radix4_extractor.vhd`
- `tb/tb_siso_smoke.vhd`
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

## Assumptions

1. Max-log-MAP is used, not full log-MAP.
2. The active top-level is exact only for `K % 8 = 0`.
3. `n_half_iter` is the canonical decode-stop contract.
4. The active windowed SISO uses uniform segment-boundary metrics because overlap-window / tail-symbol ports are not part of the current public interface.
5. The Python QPP table now includes the full LTE table used by the current generator flow.

## Documents

- `ARCHITECTURE_THEORY_WRITEUP.md`
- `SIMULATION_RESULTS.md`
- `FINAL_VALIDATION_REPORT.md`
- `MULTI_K_REGRESSION_REPORT.md`
