# Assumption Log

Date: 2026-03-22
Project: Parallel-Turbo-Decoder-ASIC-for-3GPP-LTE

This file records every material implementation assumption or paper-to-RTL approximation in the active VHDL codebase.

## A1. LTE Constituent Code

Assumption:
- The constituent recursive systematic convolutional code is the standard LTE 8-state RSC with feedback polynomial `13_o` and feedforward polynomial `15_o`.

Reason:
- The JSSC paper references the LTE standard but does not restate the encoder polynomials inside the architecture section.
- The trellis helpers in `rtl/turbo_pkg.vhd` and the vector generator in `tools/gen_lte_vectors.py` implement this exact LTE constituent code.

Impact:
- All state-transition, parity, branch-metric, radix-4 path, and LLR computations are tied to this trellis.

## A2. QPP Table Source

Assumption:
- `tools/lte_qpp_table.py` is treated as the project source of truth for `(K, f1, f2)` LTE QPP parameters.

Reason:
- The paper gives the QPP formula and recursion but not the full parameter table.
- The table was extracted from ETSI TS 136 212 / 3GPP TS 36.212.

Impact:
- Automatic vector generation and default regressions use the official LTE QPP tuples.

## A3. Fixed-Point Widths

Assumption:
- Channel/systematic/parity LLRs use 5-bit signed quantization.
- Extrinsic LLRs use 6-bit signed quantization.
- Posterior outputs use 7-bit signed quantization.
- State metrics use 10-bit signed arithmetic with wraparound modulo-normalized comparisons.

Reason:
- These values are stated explicitly in Section VI-A of the paper for the measured implementation.

Impact:
- The entire RTL datapath and fixed-point reference model use this contract.

## A4. Extrinsic Scaling

Assumption:
- Extrinsic scaling is fixed to `0.6875 = 11/16` and implemented as shift/add.

Reason:
- The paper states that a hardware-friendly constant of `0.6875` was used.

Impact:
- `rtl/turbo_pkg.vhd` and `rtl/siso_maxlogmap.vhd` apply this scaling in the active RTL.

## A5. Master-Slave Batcher Scope

Assumption:
- The implemented master-slave Batcher network is fixed to `N = 8`, which is the paper's chosen parallelism point.

Reason:
- The paper's measured architecture is an `8x` parallel decoder.
- A specialized 8-lane switching network is more faithful than a generic selection-sort fabric for this repository.

Impact:
- `rtl/batcher_master.vhd` and `rtl/batcher_slave.vhd` now model an explicit 8-lane stage-by-stage Batcher network.

## A6. Internal Radix-4 Extraction Mapping

Assumption:
- Odd-step midpoint reconstruction is implemented directly inside the active `siso_maxlogmap` core rather than as a standalone reusable RTL block.

Reason:
- The repository was cleaned so the active SISO owns the branch-metric, ACS, and extraction logic that actually participates in the top-level decoder path.

Impact:
- The active RTL remains mathematically aligned with the paper's midpoint reconstruction requirement, but the logic now lives inside `rtl/siso_maxlogmap.vhd` instead of a separate standalone extractor module.

## A7. Public Top-Level Interface

Assumption:
- The top-level decoder interface remains a scalar frame load/store API instead of exposing the ASIC's internal wide memory ports directly.

Reason:
- This keeps the repository test flow practical while preserving the internal folded-memory and 8-core parallel architecture.

Impact:
- The implementation is architecturally faithful internally, but not pin-faithful to a physical SoC integration wrapper.

## A8. Segment Boundary Model

Assumption:
- Outer frame boundaries use terminated-state seeds.
- Interior segment boundaries still use internal approximations because explicit overlap-window delivery is not yet wired through the active top-level datapath.

Reason:
- The paper's dummy-forward wording implies an acquisition/overlap requirement for arbitrary segment starts.
- The current public RTL top level does not yet transport those overlap windows into each active SISO instance.

Impact:
- The design is synthesizable and structurally complete, but large-K exact closure remains open.
- This is the main known reason why `K = 3200` and `K = 6144` do not yet match the fixed-point model bit-for-bit.

## A9. Tail-Symbol Handling

Assumption:
- The active decoder uses terminated-state seeds instead of explicit received tail-symbol LLR inputs.

Reason:
- The repository currently loads only the information-bit and parity-bit streams used by the main code block path.
- Full termination-symbol transport was not part of the restored public interface.

Impact:
- The endpoint trellis constraint is modeled, but the exact received tail-symbol evidence is not yet consumed explicitly.

## A10. Supported Block Sizes

Assumption:
- The active top-level requires `K % 8 = 0`.

Reason:
- The paper's `N = 8` parallel segmentation assumes equal trellis segments.
- The current folded-memory top-level is organized around equal 8-way partitioning.

Impact:
- All LTE sizes used in the repository regressions satisfy this constraint, but the top-level does not currently cover non-divisible exploratory cases.
