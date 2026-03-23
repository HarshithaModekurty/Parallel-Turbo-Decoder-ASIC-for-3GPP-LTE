# Multi-K Regression Report

Date: 2026-03-20
Worktree: `codex-worktree`
Branch: `codex-branch`

## Commands

- `python tools/run_lte_pipeline.py --k 40 --n-half-iter 11 --snr-db 1.5 --seed 12345`
- `python tools/run_lte_pipeline.py --k 3200 --n-half-iter 11 --snr-db 1.5 --seed 12345`
- `python tools/run_lte_pipeline.py --k 6144 --n-half-iter 11 --snr-db 1.5 --seed 12345`

Common settings:
- `n_half_iter = 11`
- `snr_db = 1.5`
- `llr_scale = 2.0`
- `seed = 12345`

## Summary Table

| K | f1 | f2 | tb_turbo_top | outputs | err vs original | hard err vs fixed | hard err vs floating |
|---|---:|---:|---|---:|---:|---:|---:|
| 40 | 3 | 10 | PASS @ `3146 ns` | 40 | 36 | 0 | 6 |
| 3200 | 111 | 240 | PASS @ `176126 ns` | 3200 | 2370 | 830 | 829 |
| 6144 | 263 | 480 | PASS @ `337526 ns` | 6144 | 4570 | 1571 | 1573 |

## Readout

- `K = 40` is the current exact fixed-point closure point.
- `K = 3200` and `K = 6144` are structurally healthy and complete end-to-end, but they are not yet exact to the current fixed-point model.
- The active QPP path is now safe for large block lengths; the previous overflow in `qpp_value` is gone.
- The synthesis check passes, and the earlier `batcher_master` warning is no longer present.

## Archived Files

- `sim_vectors/rtl_vs_reference_report_k40.txt`
- `sim_vectors/rtl_vs_reference_report_k3200.txt`
- `sim_vectors/rtl_vs_reference_report_k6144.txt`
- `sim_vectors/tb_turbo_top_report_k40.txt`
- `sim_vectors/tb_turbo_top_report_k3200.txt`
- `sim_vectors/tb_turbo_top_report_k6144.txt`
- `sim_logs/tb_turbo_top_k40.log`
- `sim_logs/tb_turbo_top_k3200.log`
- `sim_logs/tb_turbo_top_k6144.log`
