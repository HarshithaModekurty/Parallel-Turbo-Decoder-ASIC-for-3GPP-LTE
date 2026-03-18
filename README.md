# Parallel Turbo Decoder ASIC for 3GPP LTE (Research-to-RTL Implementation)

This repository contains a synthesizable VHDL-2008 implementation plan and baseline RTL for a parallel LTE turbo decoder architecture inspired by **Studer et al., JSSC 2011** (`11JSSC-turbo.pdf`).

## Architecture Summary

The implementation follows the paper's high-level partitioning:

1. Iterative turbo decoder with two constituent SISO decoders.
2. QPP interleaver/deinterleaver address generation using the recursive LTE form.
3. Extrinsic LLR exchange between half-iterations through RAM.
4. Max-log-MAP state metric recursions with metric normalization.
5. Block-level iteration controller with pulse-based half-iteration launch.
6. Routing primitive (batcher-style abstraction) for scalable parallelization.

## Implemented Modules

- `rtl/turbo_pkg.vhd`: shared constants/types/trellis helpers.
- `rtl/qpp_interleaver.vhd`: synthesizable recursive QPP index generator.
- `rtl/branch_metric_unit.vhd`: branch metric equations for max-log-MAP.
- `rtl/siso_maxlogmap.vhd`: SISO decoder core (forward/backward recursions + extrinsic output).
- `rtl/llr_ram.vhd`: inferred RAM wrapper for LLR storage.
- `rtl/turbo_iteration_ctrl.vhd`: half-iteration/iteration sequencing FSM.
- `rtl/batcher_router.vhd`: generic routing primitive aligned with master-slave batcher concept.
- `rtl/turbo_decoder_top.vhd`: top-level integration.

## Testbenches

- `tb/tb_qpp_interleaver.vhd`: QPP address smoke test.
- `tb/tb_siso_smoke.vhd`: SISO streaming smoke test.
- `tb/tb_turbo_top.vhd`: top-level end-to-end test with IO trace and hard-decision summary.

## End-to-End Outputs

Running `tb_turbo_top` generates:

- `tb_turbo_top_io_trace.txt`
  - Full mixed trace:
    - `IN idx bit_orig bit_int l_sys_orig l_par1_orig l_par2_int`
    - `OUT seq idx_int pass bit_int bit_orig_pi l_sys_pi l_par1_pi l_par2_int l_post hard`
- `tb_turbo_top_report.txt`
  - Human-readable summary with per-index final LLR, hard decision, and match status.
- `sim_vectors/rtl_vs_reference_report.txt`
  - RTL vs floating max-log reference comparison in interleaved domain.

## LTE Stimulus Pipeline

Added tooling to generate encoder-consistent LTE-like vectors (QPP + tail termination + AWGN LLRs) and run full simulation:

- `tools/gen_lte_vectors.py`
  - Generates:
    - `sim_vectors/lte_frame_input_vectors.txt` (TB input vectors)
    - `sim_vectors/lte_frame_generation_report.txt` (encoder/channel metadata including tail bits)
    - `sim_vectors/reference_interleaved.txt` and `sim_vectors/reference_original.txt` (floating max-log reference)
- `tools/compare_rtl_reference.py`
  - Compares RTL outputs against floating reference and writes:
    - `sim_vectors/rtl_vs_reference_report.txt`
- `tools/run_lte_pipeline.py`
  - Single-command end-to-end run:
    - vector generation
    - RTL compile/elaborate/sim
    - reference comparison

## Assumption Log

1. **Algorithmic kernel**: max-log-MAP is used as practical RTL approximation to log-MAP and aligned with paper implementation direction.
2. **Radix choice**: delivered SISO datapath is radix-2 style recursion baseline. The paper ASIC emphasizes radix-4 throughput optimization; this repository uses a modular form that can be upgraded to radix-4 ACS grouping with two trellis steps/cycle.
3. **Parallelism**: paper presents 8-way parallel decoding and contention-free scheduling. This baseline implements generic components and sequencing suitable for extension to multi-SISO banks.
4. **Interleaver network**: master-slave batcher is represented as a synthesizable deterministic router primitive (`batcher_router`) to keep RTL practical and parameterizable.
5. **Windowing**: block recursion baseline is implemented; sliding-window parallel boundary exchange is left as an optimization layer.
6. **Quantization**: default LLR=8 bit, state metric=12 bit signed fixed-point with max-subtraction normalization.
7. **QPP realization**: RTL uses the recursive interleaver sequence (`pi`, `delta`, `b`) instead of recomputing the quadratic formula every cycle, which is architecturally closer to the paper.
8. **Control handshake**: `turbo_iteration_ctrl` emits one-cycle launch pulses, while `turbo_decoder_top` maintains the full replay of each half-iteration using local active flags and counters.

## Build Order (Typical)

1. Compile package first: `turbo_pkg.vhd`
2. Compile utility blocks (`qpp_interleaver`, `llr_ram`, `branch_metric_unit`, `batcher_router`)
3. Compile compute/control (`siso_maxlogmap`, `turbo_iteration_ctrl`)
4. Compile `turbo_decoder_top`
5. Compile and run testbenches.

## GHDL Quick Run

Example (VHDL-2008):

1. Run full pipeline in one command:
   - `python tools/run_lte_pipeline.py`
2. Or run only vector generation:
   - `python tools/gen_lte_vectors.py --k 40 --n-iter 2 --snr-db 1.5 --llr-scale 8 --seed 12345`

## Known Limitations / Next Steps

- Add strict LTE block-length table and official `(f1,f2)` lookup ROM.
- Implement true radix-4 ACS and two-symbol branch metric packing.
- Add contention-free interleaver scheduling for `P=8` banked memories.
- Add tail-bit handling and windowed boundary metric exchange exactly as in throughput-optimized architecture.
- Extend reference-validation flow from max-log baseline to full LTE BER-curve validation.
