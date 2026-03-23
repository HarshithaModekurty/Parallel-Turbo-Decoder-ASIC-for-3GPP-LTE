## Plan: Parallel Radix-4 Turbo Decoder Architecture Rewrite

**TL;DR**
Replacing the full-frame, Radix-2, non-pipelined VHDL baseline with an ASIP-compatible P=8 Radix-4 sliding-window Turbo Decoder. This includes Radix-4 ACS branch/state units, 2's complement modulo normalization, folded memory architecture with Master-Slave Batcher routing.

**Steps**

**Phase 1: Foundation & Quantization Update**
1. Update `rtl/turbo_pkg.vhd` bit-widths: Define 5-bit input LLRs, 6-bit Ext LLRs, and 10-bit metrics.
2. Remove standard `max8` denormalization functions and replace them with two's complement modulo addition logic (`mod_add`) to handle state-metric wrap-around (as mandated by the paper to prevent overflow without the `max` delay).

**Phase 2: Radix-4 ACS & BMU Logic**
3. Create new `radix4_bmu.vhd`: Computes Radix-4 branch metrics ($\gamma$). Because Radix-4 processes two bits ($u_k, u_{k+1}$) per cycle, the BMU must generate combined transitional metrics.
4. Create new `radix4_acs.vhd`: Implement Add-Compare-Select logic. Uses the 10-bit modulo addition for $\alpha$ (Forward) and $\beta$ (Backward) state metric updates over the 8 states. Evaluates $max()$ correctly across wrapped two's complement values (by comparing the sign of the difference).

**Phase 3: Sliding-Window Sub-block SISO**
5. Rewrite `rtl/siso_maxlogmap.vhd` to discard the full-frame array and adopt a sliding window state-machine. 
   - *Window size:* $W=30$ Radix-4 stages.
   - *Learning length (Acquisition):* Implement a learning block of $L \approx 12-16$ Radix-4 stages (roughly 24-32 bits) for reliable metric convergence.
   - Architect 3 parallel sub-units inside: Forward Metric Unit, Backward Learning Unit, and Backward Decoding Unit (processing overlapped windows).

**Phase 4: Folded Memory & Interconnect Network**
6. Create new `folded_llr_ram.vhd`: Implement $M=8$ separated dual-port RAM banks to guarantee conflict-free memory access for the 8 parallel SISOs.
7. Refactor `rtl/batcher_router.vhd`: Implement the multi-stage Master-Slave Address/Data routing network exactly as structured in the paper to manage spatial-temporal alignments from the QPP interleaver.

**Phase 5: Top-Level Integration**
8. Rewrite `rtl/turbo_decoder_top.vhd`: Instantiate the grid of 8 parallel `siso_maxlogmap` cores. 
9. Connect the 8 memory banks through the Batcher Router to the SISO inputs/outputs.
10. Update `rtl/turbo_iteration_ctrl.vhd` to synchronize window processing across the parallel grid.

**Relevant files**
- `rtl/turbo_pkg.vhd` — Update quantization and arithmetic (modulo).
- `rtl/radix4_bmu.vhd` (New) — 2-bit branch metric generation.
- `rtl/radix4_acs.vhd` (New) — Radix-4 modulo Add-Compare-Select logic.
- `rtl/siso_maxlogmap.vhd` — Redesign into a sliding-window dataflow.
- `rtl/folded_llr_ram.vhd` (New) — Banked memory (8 banks).
- `rtl/batcher_router.vhd` — Implement multi-stage contention-free switching.
- `rtl/turbo_decoder_top.vhd` — Instantiate 8 SISOs and routers.

**Verification**
1. **Modulo Math Testing:** Inject sequences that artificially inflate $\alpha/\beta$ to ensure the new 2's complement wrapping logic correctly identifies the maximum metric without actual numerical overflow.
2. **Bank Conflict Checking:** Synthesize the `batcher_router` + `folded_llr_ram` + `qpp_interleaver` on vector traces from `tools/gen_lte_vectors.py` to assert $100\%$ contention-free hits per clock cycle.
3. **End-to-End Validation:** Run `tools/run_lte_pipeline.py` to compare the Radix-4 sliding window RTL output with the existing Python reference models to guarantee Bit Error Rate (BER) matches expectations.

**Decisions**
- Stick with VHDL for the rewrite since it's the easiest option given the solid existing baseline.
- Assumed a standard sliding-window learning length ($L \approx 12-16$ Radix-4 stages) is sufficient for reliable metrics convergence (LTE standard allows this approximation).
