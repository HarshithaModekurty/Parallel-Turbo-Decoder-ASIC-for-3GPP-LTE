# Paper Implementation Report

## 1. Paper Understanding and Architecture Summary

Primary source:
- `11JSSC-turbo.pdf`

Implementation-critical references called out by the paper:
- LTE turbo-code and QPP interleaver definition from 3GPP TS 36.212 / ETSI TS 136 212. This is required for the legal `(K, f1, f2)` table and for the QPP address law.
- The paper's reduced-search / windowed BCJR reference (cited as [13] in the paper). This is required to justify dummy-recursion window seeding rather than full-frame metric storage.
- The paper's maximally vectorizable / contention-free interleaver reference (cited as [24]). This is required to justify why one folded row can feed all `N=8` SISOs when the QPP addresses are grouped correctly.

Paper architecture, in plain words:
- The decoder is a parallel LTE turbo decoder using `N = 8` SISO processors.
- Each SISO uses radix-4 max-log-MAP / M-BCJR style processing, so one radix-4 step covers two trellis sections.
- The constituent trellis is processed in windows of `M = 30` trellis steps.
- Backward recursion for window `m` is seeded by a dummy backward recursion over window `m + 1`.
- A dummy forward warm-up is used so each segment can start from a locally reconstructed state-metric boundary instead of requiring a full-frame forward pass.
- QPP interleaving is implemented from the recursive address law instead of direct multiply-square evaluation.
- Interleaved accesses are organized through folded memories plus a master-slave Batcher routing network so one folded row can serve all parallel SISOs without address collisions.
- The paper uses an aggressive fixed-point contract: 5-bit channel LLRs, 6-bit extrinsic LLRs, 10-bit state metrics, and extrinsic scaling by `0.6875`.

Hardware-relevant content vs non-hardware content:
- Synthesizable digital logic: SISO datapaths, branch metrics, state-metric recursions, QPP address generation, permutation network, folded memories, half-iteration controller, top-level scheduling.
- Algorithmic content that must be converted into RTL: BCJR / max-log / M-BCJR recursions, radix-4 pair processing, window scheduling, dummy recursions, extrinsic extraction, QPP recursion.
- ASIC-specific content that is approximated in RTL: SRAM macro implementation, floorplan, custom clocking, CTS, physical timing closure, measured throughput/area/power tables.
- Reporting-only content that is not coded: silicon test chip measurements, post-layout performance tables, die photo, energy and area numbers.

## 2. List of Required Modules

Implemented module groups:
- Package and math support: `rtl/turbo_pkg.vhd`
- Branch-metric generation: `rtl/branch_metric_unit.vhd`, `rtl/radix4_bmu.vhd`
- State-metric recursion: `rtl/radix4_acs.vhd`
- LLR / extrinsic extraction: `rtl/radix4_extractor.vhd`
- SISO decoder core: `rtl/siso_maxlogmap.vhd`
- QPP address generation: `rtl/qpp_interleaver.vhd`, `rtl/qpp_parallel_scheduler.vhd`
- Interleaver routing: `rtl/batcher_master.vhd`, `rtl/batcher_slave.vhd`, `rtl/batcher_router.vhd`
- Memory wrappers: `rtl/llr_ram.vhd`, `rtl/folded_llr_ram.vhd`
- Iteration / phase control: `rtl/turbo_iteration_ctrl.vhd`
- Integration top level: `rtl/turbo_decoder_top.vhd`

Top-level functional blocks extracted from the paper and mapped into RTL:
- Natural-order input memories for systematic and parity-1 streams
- Interleaved-order access path for systematic and parity-2 streams
- Eight parallel SISOs
- QPP recursive scheduler
- Batcher sort / permutation path
- Extrinsic storage and feedback path
- Final posterior writeback path
- Half-iteration controller and serializer

## 3. Assumptions and Ambiguities

Full assumption log:
- `ASSUMPTION_LOG.md`

Most important active assumptions:
- The implementation uses max-log-MAP, not full log-MAP. This matches the paper's practical hardware direction.
- The active public top level currently targets `K % 8 = 0`, because the paper's parallelism is specialized here to `N = 8` lanes.
- The external interface is scalar frame loading plus scalar result serialization; the paper's internal parallelism is preserved inside the core.
- The LTE QPP `(K, f1, f2)` table is sourced from the LTE standard rather than re-derived from the paper text.
- The active top level stores and reuses folded-row permutations, but it does not yet carry explicit overlap-window samples or explicit tail-symbol evidence into the interior segment boundaries.
- Outer frame boundaries are terminated-state aligned, but interior segment boundaries are still approximated from local seeds. This is the main reason large-`K` fixed-point closure is not exact yet.
- Extrinsic scaling is implemented as `11/16`, matching `0.6875`.
- The master emits both permutation vectors and Batcher switch-control bits; the active datapath uses the stored permutation vectors for forward and reverse routing.

Ambiguities resolved in a defensible way:
- The paper is high level about exact control sequencing. The RTL chooses an explicit load, seed, window-decode, and writeback schedule that preserves the paper's data dependencies.
- The paper is physical-design oriented about memory banking. The RTL uses inference-friendly folded row memories and wrappers instead of custom SRAM macros.
- The paper assumes architecture knowledge from prior BCJR work. The RTL makes midpoint reconstruction explicit in `radix4_extractor.vhd` so odd trellis steps are recovered faithfully from radix-4 processing.

## 4. RTL Implementation Plan

Module hierarchy:
- `turbo_decoder_top`
- `turbo_iteration_ctrl`
- `qpp_parallel_scheduler` x2 for even/odd folded rows during interleaved half-iteration
- `batcher_master` x2 and `batcher_slave` instances for read and write permutations
- `siso_maxlogmap` x8
- internal helpers: `radix4_bmu`, `radix4_acs`, `radix4_extractor`

Interfaces and widths:
- Channel/systematic/parity inputs: 5-bit signed `chan_llr_t`
- Extrinsic values: 6-bit signed `ext_llr_t`
- Posterior outputs: 7-bit signed `post_llr_t`
- State metrics: 10-bit signed `metric_t` / `state_metric_t`
- Address width: 13 bits to cover LTE `K <= 6144`
- Router lane-select width: `C_ROUTER_SEL_W`
- Batcher control width: `C_BATCHER_CTRL_W = 19` for the explicit 8-lane sorting network trace

Memory organization:
- Natural-order memories are folded into even-row and odd-row banks.
- Each folded row stores 8 lane values, one per SISO segment.
- Separate folded memories exist for systematic, parity-1, parity-2, extrinsic, and final posterior data.
- Interleaved half-iteration reads compute one QPP row-group, sort those addresses, fetch the matching folded row, and permute data into SISO-lane order.
- Interleaved writeback uses the inverse stored permutation to return extrinsic and posterior data to natural folded-row order.

Control sequencing:
- Frame load phase: scalar writes fill folded memories.
- Half-iteration 1: each SISO processes natural-order systematic + parity-1 + prior extrinsic.
- Half-iteration 2: QPP scheduler plus Batcher route systematic + parity-2 + prior extrinsic in interleaved order.
- `turbo_iteration_ctrl.vhd` alternates phase-1 and phase-2 until `n_half_iter` is exhausted.
- On the final half-iteration, posterior outputs are stored and serialized back out.

SISO / BCJR mapping:
- Two trellis steps are packed into one radix-4 pair cycle.
- `radix4_bmu.vhd` generates the pair-path branch metrics.
- `radix4_acs.vhd` performs forward and backward state recursion.
- `siso_maxlogmap.vhd` keeps per-segment pair samples, performs one dummy forward warm-up, builds per-window alpha seeds, then decodes windows from end to start.
- Dummy backward recursion over window `m + 1` seeds the real decode of window `m`.
- `radix4_extractor.vhd` reconstructs the midpoint state metrics so both even and odd bit LLRs are produced from the radix-4 schedule.
- Extrinsic LLR is `posterior - systematic - apriori`, followed by `11/16` scaling.

Scheduling and pipeline detail:
- Window size is `M = 30` trellis steps, which is 15 radix-4 pair cycles.
- Even and odd folded rows are stored separately so pair-wise streaming is simple.
- The active design is mostly cycle-scheduled rather than deeply pipelined; registers are inserted where required by the module boundaries and memory timing, but the code intentionally keeps the control/data dependency graph explicit.

## 5. VHDL Code for Each File

Core VHDL files:
- `rtl/turbo_pkg.vhd`: package constants, types, trellis helpers, saturation helpers, QPP helper, scaling helper.
- `rtl/branch_metric_unit.vhd`: single-step branch metric primitive.
- `rtl/radix4_bmu.vhd`: two-step branch metric vector generation.
- `rtl/radix4_acs.vhd`: radix-4 forward/backward add-compare-select engine.
- `rtl/radix4_extractor.vhd`: even/odd posterior and extrinsic computation with midpoint reconstruction.
- `rtl/qpp_interleaver.vhd`: scalar recursive QPP generator.
- `rtl/qpp_parallel_scheduler.vhd`: 8-lane folded-row QPP address generation and row-validity check.
- `rtl/batcher_master.vhd`: explicit 8-lane Batcher sorting network, output permutation, and switch-control trace.
- `rtl/batcher_slave.vhd`: forward / reverse permutation network driven by the stored permutation vector.
- `rtl/batcher_router.vhd`: convenience wrapper around master plus slave routing.
- `rtl/llr_ram.vhd`: generic inferred RAM helper.
- `rtl/folded_llr_ram.vhd`: folded row-word memory wrapper.
- `rtl/siso_maxlogmap.vhd`: windowed radix-4 SISO using dummy recursion.
- `rtl/turbo_iteration_ctrl.vhd`: half-iteration FSM.
- `rtl/turbo_decoder_top.vhd`: top-level integration, folded-memory organization, routing, SISO farm, serializer.

The synthesizable VHDL itself is in the files above under `rtl/`.

## 6. Testbenches

Implemented testbenches:
- `tb/tb_qpp_interleaver.vhd`: scalar recursive QPP address sanity.
- `tb/tb_qpp_parallel_scheduler.vhd`: grouped-address row-base and row-valid checks.
- `tb/tb_batcher_router.vhd`: address sort, permutation, forward route, reverse route.
- `tb/tb_folded_llr_ram.vhd`: folded RAM write/read behavior.
- `tb/tb_radix4_acs.vhd`: ACS state update sanity.
- `tb/tb_radix4_extractor.vhd`: zero case and nonzero midpoint-reconstruction case.
- `tb/tb_siso_smoke.vhd`: constituent SISO smoke test.
- `tb/tb_turbo_top.vhd`: full-frame integration test using generated LTE-like vectors.

## 7. Verification Notes

Main automated flow:
- `python tools/run_lte_pipeline.py`

What the flow does:
- Generates LTE-like terminated-frame vectors and floating/fixed references.
- Compiles all RTL and TBs with `ghdl --std=08`.
- Runs each testbench with `--assert-level=error` so assertion failures fail the pipeline.
- Compares `tb_turbo_top` output against the fixed-point and floating reference models.
- Runs `ghdl --synth --std=08 turbo_decoder_top` as a synthesis sanity check.
- Archives per-`K` reports for larger regressions.

Current checked results after the latest fixes:
- `K = 40`, `n_half_iter = 11`: exact fixed-point match, `hard_errors_vs_reference = 0`.
- `K = 3200`, `n_half_iter = 11`: `hard_errors_vs_reference = 830`.
- `K = 6144`, `n_half_iter = 11`: `hard_errors_vs_reference = 1571`.
- All active unit and integration TBs pass under strict assertion handling.
- `ghdl --synth --std=08 turbo_decoder_top` passes.

Why large-`K` is not exact yet:
- The active public datapath still approximates interior segment/window boundaries because overlap-window and explicit tail-symbol evidence are not yet fed into the internal segment handoff logic.
- This preserves a practical, synthesizable architecture, but it is not yet the final standards-faithful boundary treatment implied by the paper's full architectural context.

## 8. Remaining Risks / Open Issues

Remaining technical risks:
- Interior segment boundary seeding is still approximate, so large-block exact closure is not achieved.
- The public top level is specialized to `N = 8` and `K % 8 = 0`; broader parameterization would need additional address and tail handling.
- Memory inference is synthesis-friendly, but not tied to a specific ASIC SRAM macro strategy.
- The paper's physical timing/throughput claims are not re-created from RTL alone; they would require target-library synthesis, memory macro binding, and backend implementation.
- The active top level uses stored permutation vectors rather than a physically replayed switch-control slave network, although the master still exposes the switch controls for traceability to the paper architecture.

Near-term work required for a more exact paper-faithful implementation:
- Add explicit overlap-window delivery into the SISO boundary seed path.
- Add explicit treatment of constituent tail-symbol evidence at interior handoff points where needed.
- Re-run large-`K` regressions until the fixed-point reference and RTL close exactly beyond the `K = 40` baseline.
