# Simulation Results

Date: 2026-03-20
Worktree: `codex-worktree`
Branch: `codex-branch`

## Checked Commands

- `python tools/run_lte_pipeline.py --k 40 --n-half-iter 11 --snr-db 1.5 --seed 12345`
- `python tools/run_lte_pipeline.py --k 3200 --n-half-iter 11 --snr-db 1.5 --seed 12345`
- `python tools/run_lte_pipeline.py --k 6144 --n-half-iter 11 --snr-db 1.5 --seed 12345`
- `ghdl --synth --std=08 turbo_decoder_top > synth_check.log 2> synth_stderr.log`

Common generator settings:
- `n_half_iter = 11`
- `snr_db = 1.5`
- `llr_scale = 2.0`
- `seed = 12345`

## Testbench Status

All active TBs pass in the checked flow:
- `tb_qpp_interleaver`
- `tb_qpp_parallel_scheduler`
- `tb_batcher_router`
- `tb_folded_llr_ram`
- `tb_radix4_acs`
- `tb_radix4_extractor`
- `tb_siso_smoke`
- `tb_turbo_top`

## Multi-K Summary

### `K = 40`

- `f1 = 3`, `f2 = 10`
- `tb_turbo_top`: PASS at `3146 ns`
- `total_outputs = 40`
- `final_decision_symbols = 40`
- `bit_errors_vs_original = 36`
- `hard_errors_vs_fixed_reference = 0`
- `sign_mismatch_vs_fixed_reference = 0`
- `hard_errors_vs_floating_reference = 6`

### `K = 3200`

- `f1 = 111`, `f2 = 240`
- `tb_turbo_top`: PASS at `176126 ns`
- `total_outputs = 3200`
- `final_decision_symbols = 3200`
- `bit_errors_vs_original = 2370`
- `hard_errors_vs_fixed_reference = 830`
- `sign_mismatch_vs_fixed_reference = 830`
- `hard_errors_vs_floating_reference = 829`

### `K = 6144`

- `f1 = 263`, `f2 = 480`
- `tb_turbo_top`: PASS at `337526 ns`
- `total_outputs = 6144`
- `final_decision_symbols = 6144`
- `bit_errors_vs_original = 4570`
- `hard_errors_vs_fixed_reference = 1571`
- `sign_mismatch_vs_fixed_reference = 1571`
- `hard_errors_vs_floating_reference = 1573`

## Interpretation

- The active RTL is structurally stable across the checked sizes `40`, `3200`, and `6144`.
- The overflow in the shared `qpp_value` helper is fixed; large-K regressions now run without QPP integer overflow.
- The `batcher_master` logical-loop synth warning is removed.
- Exact RTL vs fixed-point agreement currently holds for the checked `K = 40` point only.
- Larger block sizes still diverge from the fixed-point model, so exact large-K closure is not complete yet.
- Outer frame boundaries now use terminated-state seeds for first/last internal segments, but full overlap/tail delivery is still not present in the public RTL interface.

## Synthesis Check

Status:
- PASS

Observed notes in `synth_stderr.log`:
- non-blocking memory-width notes in `turbo_decoder_top.vhd`
- non-blocking inferred-ROM notes in `siso_maxlogmap.vhd`

Observed non-issues:
- no synthesis-blocking RTL errors
- no residual `batcher_master` logical-loop warning

## Artifacts

Current default outputs:
- `sim_vectors/rtl_vs_reference_report.txt`
- `tb_turbo_top_report.txt`
- `tb_turbo_top_io_trace.txt`
- `sim_logs/tb_turbo_top.log`

Archived per-K outputs:
- `sim_vectors/rtl_vs_reference_report_k40.txt`
- `sim_vectors/rtl_vs_reference_report_k3200.txt`
- `sim_vectors/rtl_vs_reference_report_k6144.txt`
- `sim_vectors/tb_turbo_top_report_k40.txt`
- `sim_vectors/tb_turbo_top_report_k3200.txt`
- `sim_vectors/tb_turbo_top_report_k6144.txt`
- `sim_logs/tb_turbo_top_k40.log`
- `sim_logs/tb_turbo_top_k3200.log`
- `sim_logs/tb_turbo_top_k6144.log`

Synthesis artifacts:
- `synth_check.log`
- `synth_stderr.log`

## Remaining Gaps

- Large-block exact fixed-point closure is still open for `K = 3200` and `K = 6144`.
- The active public RTL interface still does not carry explicit overlap-window or tail-symbol inputs.
- The next debugging target is the large-K divergence between the windowed SISO/top-level datapath and the fixed-point model.
