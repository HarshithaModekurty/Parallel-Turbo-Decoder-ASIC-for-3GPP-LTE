# Final Validation Report

Date: 2026-03-20
Project: Parallel-Turbo-Decoder-ASIC-for-3GPP-LTE
Worktree: `codex-worktree`
Branch: `codex-branch`

## 1. Scope

This validation covers the current paper-oriented codex-branch implementation after the latest structural follow-up:
- full LTE QPP table added to the Python flow
- overflow-safe `qpp_value` helper in `turbo_pkg.vhd`
- explicit terminated-state seeding at the outer frame boundaries of the active segmented SISO path
- windowed radix-4 `M = 30` SISO still active
- folded-memory top-level path still active
- explicit master/slave Batcher path still active
- half-iteration control through `n_half_iter`

This report does not claim full LTE-standard end-to-end fidelity yet. The public RTL interface still does not deliver explicit overlap-window or tail-symbol inputs.

## 2. Structural Status

Compile/elaborate passes for the active RTL:
- `rtl/turbo_pkg.vhd`
- `rtl/branch_metric_unit.vhd`
- `rtl/qpp_interleaver.vhd`
- `rtl/llr_ram.vhd`
- `rtl/folded_llr_ram.vhd`
- `rtl/qpp_parallel_scheduler.vhd`
- `rtl/batcher_master.vhd`
- `rtl/batcher_slave.vhd`
- `rtl/batcher_router.vhd`
- `rtl/radix4_bmu.vhd`
- `rtl/radix4_acs.vhd`
- `rtl/radix4_extractor.vhd`
- `rtl/siso_maxlogmap.vhd`
- `rtl/turbo_iteration_ctrl.vhd`
- `rtl/turbo_decoder_top.vhd`

Compile/elaborate also passes for all active TBs:
- `tb_qpp_interleaver`
- `tb_qpp_parallel_scheduler`
- `tb_batcher_router`
- `tb_folded_llr_ram`
- `tb_radix4_acs`
- `tb_radix4_extractor`
- `tb_siso_smoke`
- `tb_turbo_top`

## 3. Synthesizability

Checked command:
- `ghdl --synth --std=08 turbo_decoder_top > synth_check.log 2> synth_stderr.log`

Status:
- PASS

Important synthesis observations:
- no synthesis-blocking RTL errors remain in the checked path
- the previous `batcher_master` logical-loop warning is gone
- remaining messages are non-blocking memory/ROM notes from GHDL synthesis

## 4. Current Architecture State

What is active now:
- scalar external top-level stream interface
- internal `N = 8` segmented datapath for `K % 8 = 0`
- folded-memory storage for systematic, parity, extrinsic, and final posterior values
- parallel QPP scheduling plus master/slave Batcher routing in the interleaved half-iteration
- windowed radix-4 SISO with `M = 30`
- dummy forward warm-up and dummy backward seeding
- odd-step reconstruction in the LLR path
- half-iteration decode-stop semantics through `n_half_iter`

Boundary model currently implemented:
- first internal segment starts from a terminated-state seed
- last internal segment ends with a terminated-state seed
- interior segment/window boundaries still use internal assumptions because overlap/tail context is not a public input

## 5. Verified Regression Points

### `K = 40`

- `f1 = 3`, `f2 = 10`
- `tb_turbo_top`: PASS at `3146 ns`
- `total_outputs = 40`
- `final_decision_symbols = 40`
- `bit_errors_vs_original = 36`
- `hard_errors_vs_fixed_reference = 0`
- `sign_mismatch_vs_fixed_reference = 0`
- `hard_errors_vs_floating_reference = 6`

Conclusion:
- exact RTL vs fixed-point closure holds at this checked point

### `K = 3200`

- `f1 = 111`, `f2 = 240`
- `tb_turbo_top`: PASS at `176126 ns`
- `total_outputs = 3200`
- `final_decision_symbols = 3200`
- `bit_errors_vs_original = 2370`
- `hard_errors_vs_fixed_reference = 830`
- `sign_mismatch_vs_fixed_reference = 830`
- `hard_errors_vs_floating_reference = 829`

Conclusion:
- structurally stable
- not exact to the current fixed-point model

### `K = 6144`

- `f1 = 263`, `f2 = 480`
- `tb_turbo_top`: PASS at `337526 ns`
- `total_outputs = 6144`
- `final_decision_symbols = 6144`
- `bit_errors_vs_original = 4570`
- `hard_errors_vs_fixed_reference = 1571`
- `sign_mismatch_vs_fixed_reference = 1571`
- `hard_errors_vs_floating_reference = 1573`

Conclusion:
- structurally stable
- not exact to the current fixed-point model

## 6. What Was Closed In This Step

- full LTE QPP table is now present in the Python flow
- large-K QPP integer overflow is fixed in the shared VHDL helper
- failing large-K regressions now execute completely instead of aborting in the TB
- pipeline log capture now preserves failing command output
- `batcher_master` synth cleanup is complete in the checked GHDL flow
- outer frame boundary seeding is now explicit in the active SISO and fixed-point model

## 7. What Is Still Open

- exact fixed-point closure is still open for larger blocks (`K = 3200`, `K = 6144`)
- the public RTL interface still omits explicit overlap-window and tail-symbol delivery
- the next real debugging target is the large-K divergence between:
  - the active windowed SISO / folded top-level RTL
  - the current fixed-point reference model

## 8. Artifacts

Primary artifacts:
- `SIMULATION_RESULTS.md`
- `tb_turbo_top_io_trace.txt`
- `tb_turbo_top_report.txt`
- `sim_vectors/rtl_vs_reference_report.txt`
- `synth_check.log`
- `synth_stderr.log`

Archived per-K artifacts:
- `sim_vectors/rtl_vs_reference_report_k40.txt`
- `sim_vectors/rtl_vs_reference_report_k3200.txt`
- `sim_vectors/rtl_vs_reference_report_k6144.txt`
- `sim_vectors/tb_turbo_top_report_k40.txt`
- `sim_vectors/tb_turbo_top_report_k3200.txt`
- `sim_vectors/tb_turbo_top_report_k6144.txt`
- `sim_logs/tb_turbo_top_k40.log`
- `sim_logs/tb_turbo_top_k3200.log`
- `sim_logs/tb_turbo_top_k6144.log`

## 9. Bottom Line

The repository is currently in a better structural state than before this step:
- synthesizable in the checked VHDL-2008 flow
- large-K QPP-safe
- free of the earlier `batcher_master` synth warning
- regression-tested at `K = 40`, `3200`, and `6144`

The repository is not yet at full paper-faithful validation closure:
- exact fixed-point agreement currently holds only at `K = 40`
- large-K exactness and standards-faithful boundary delivery remain open
