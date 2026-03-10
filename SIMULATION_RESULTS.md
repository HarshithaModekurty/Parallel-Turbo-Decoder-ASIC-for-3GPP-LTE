# Simulation Results (Latest: n_iter=6)

Run command:
- `python tools/run_lte_pipeline.py --n-iter 6`

Status:
- `tb_qpp_interleaver`: PASS (`@106 ns`)
- `tb_siso_smoke`: PASS (`@695 ns`)
- `tb_turbo_top`: PASS (`@10836 ns`)

Top-level summary:
- `symbols=40`
- `n_iter=6`
- `total_outputs=240`
- `expected_outputs=240`
- `final_decision_symbols=40`
- `bit_errors_vs_interleaved=10`

Primary artifacts:
- `tb_turbo_top_io_trace.txt`
- `tb_turbo_top_report.txt`
- `sim_vectors/lte_frame_input_vectors.txt`
- `sim_vectors/lte_frame_generation_report.txt`
- `sim_vectors/reference_interleaved.txt`
- `sim_vectors/rtl_vs_reference_report.txt`
- `sim_logs/tb_qpp_interleaver.log`
- `sim_logs/tb_siso_smoke.log`
- `sim_logs/tb_turbo_top.log`

Detailed architecture/theory:
- `ARCHITECTURE_THEORY_WRITEUP.md`

Detailed validation write-up:
- `FINAL_VALIDATION_REPORT.md`
