# Parallel Turbo Decoder ASIC for 3GPP LTE (Research-to-RTL Implementation)

This repository contains a synthesizable VHDL-2008 implementation plan and baseline RTL for a parallel LTE turbo decoder architecture inspired by **Studer et al., JSSC 2011** (`11JSSC-turbo.pdf`).

## Architecture Summary

The implementation follows the paper's high-level partitioning:

1. Iterative turbo decoder with two constituent SISO decoders.
2. QPP interleaver/deinterleaver address generation.
3. Extrinsic LLR exchange between half-iterations through RAM.
4. Max-log-MAP state metric recursions with metric normalization.
5. Block-level iteration controller.
6. Routing primitive (batcher-style abstraction) for scalable parallelization.

## Implemented Modules

- `rtl/turbo_pkg.vhd`: shared constants/types/trellis helpers.
- `rtl/qpp_interleaver.vhd`: synthesizable QPP index generator.
- `rtl/branch_metric_unit.vhd`: branch metric equations for max-log-MAP.
- `rtl/siso_maxlogmap.vhd`: SISO decoder core (forward/backward recursions + extrinsic output).
- `rtl/llr_ram.vhd`: inferred RAM wrapper for LLR storage.
- `rtl/turbo_iteration_ctrl.vhd`: half-iteration/iteration sequencing FSM.
- `rtl/batcher_router.vhd`: generic routing primitive aligned with master-slave batcher concept.
- `rtl/turbo_decoder_top.vhd`: top-level integration.

## Testbenches

- `tb/tb_qpp_interleaver.vhd`: QPP address smoke test.
- `tb/tb_siso_smoke.vhd`: SISO streaming smoke test.
- `tb/tb_turbo_top.vhd`: top-level integration smoke test.

## Assumption Log

1. **Algorithmic kernel**: max-log-MAP is used as practical RTL approximation to log-MAP and aligned with paper implementation direction.
2. **Radix choice**: delivered SISO datapath is radix-2 style recursion baseline. The paper ASIC emphasizes radix-4 throughput optimization; this repository uses a modular form that can be upgraded to radix-4 ACS grouping with two trellis steps/cycle.
3. **Parallelism**: paper presents 8-way parallel decoding and contention-free scheduling. This baseline implements generic components and sequencing suitable for extension to multi-SISO banks.
4. **Interleaver network**: master-slave batcher is represented as a synthesizable deterministic router primitive (`batcher_router`) to keep RTL practical and parameterizable.
5. **Windowing**: block recursion baseline is implemented; sliding-window parallel boundary exchange is left as an optimization layer.
6. **Quantization**: default LLR=8 bit, state metric=12 bit signed fixed-point with max-subtraction normalization.

## Build Order (Typical)

1. Compile package first: `turbo_pkg.vhd`
2. Compile utility blocks (`qpp_interleaver`, `llr_ram`, `branch_metric_unit`, `batcher_router`)
3. Compile compute/control (`siso_maxlogmap`, `turbo_iteration_ctrl`)
4. Compile `turbo_decoder_top`
5. Compile and run testbenches.

## Known Limitations / Next Steps

- Add strict LTE block-length table and official `(f1,f2)` lookup ROM.
- Implement true radix-4 ACS and two-symbol branch metric packing.
- Add contention-free interleaver scheduling for `P=8` banked memories.
- Add tail-bit handling and windowed boundary metric exchange exactly as in throughput-optimized architecture.
- Add golden-model comparison (MATLAB/Python BCJR) and BER curve validation.
