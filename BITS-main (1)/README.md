# BITS — Parallel Radix-4 LTE Turbo Decoder on FPGA

> A fully verified, FPGA-synthesized parallel turbo decoder implementing the Radix-4 Max-Log M-BCJR algorithm for 3GPP-LTE, with cycle-accurate RTL, bit-exact Python reference models, Monte Carlo BER validation, and Zynq-7010 hardware bring-up.

---

## Project Summary

BITS is a ground-up hardware implementation of a **parallel LTE turbo decoder** targeting the Xilinx Zynq-7010 FPGA. The design splits a 3200-bit LTE code block across two parallel SISO (Soft-Input Soft-Output) cores using the sliding-window Max-Log MAP algorithm with radix-4 trellis processing, achieving 2× throughput over radix-2 at the same clock frequency. The RTL is backed by a comprehensive verification stack — a bit-exact Python reference model, deterministic regression vectors, Monte Carlo BER sweeps, an AXI4-Lite processor interface, and physical FPGA validation on a Zybo Z7-10 board with ILA-based output capture.

The project demonstrates end-to-end digital design competence: algorithm study from IEEE publications, architectural decisions under real FPGA resource constraints, ~5,000 lines of production-quality Verilog, ~3,400 lines of Python verification infrastructure, and timing-clean hardware running at 100 MHz.

---

## Problem Statement

Turbo codes are the standard forward error correction (FEC) scheme in 3GPP-LTE, delivering near-Shannon-limit BER performance. However, turbo decoding is computationally intense — the iterative BCJR algorithm requires forward and backward trellis recursions with large state-metric memories, repeated across multiple half-iterations. Meeting LTE data-rate requirements demands parallelism (multiple SISO cores decoding simultaneously), which introduces non-trivial architectural challenges: segment-boundary initialization, QPP interleaver routing, extrinsic memory exchange, and fixed-point quantization — all while fitting within the tight resource budget of a small FPGA.

This project addresses these challenges by implementing and verifying a complete parallel turbo decoder datapath from algorithm to silicon.

---

## Motivation

Turbo decoders are among the most resource-intensive blocks in any LTE baseband processor. Published ASIC implementations (Studer et al., IEEE JSSC 2011; Shrestha & Paily, IEEE TCAS-I 2014) report sophisticated architectures but rarely provide open-source RTL or reproducible verification flows. This project bridges that gap by:

- Implementing the core architecture described in Studer et al. (radix-4 M-BCJR, sliding-window, parallel SISO, QPP interleaving) as synthesizable Verilog
- Building a bit-exact Python model that matches RTL output to zero mismatches, enabling confident algorithm exploration
- Targeting a real, resource-constrained FPGA (Zynq-7010, 17,600 LUTs) to force practical engineering trade-offs
- Providing a complete FPGA bring-up path with AXI register interface and Vitis bare-metal software

---

## Key Features

- **Radix-4 Max-Log M-BCJR Engine** — Processes two trellis steps per clock cycle using radix-4 branch metric composition, halving decode latency compared to radix-2
- **2-Core Parallel SISO Architecture** — Splits K=3200 across two independent BCJR cores with QPP-interleaver-based extrinsic exchange; scalable to 8 cores
- **Sliding-Window Decoding (W=30)** — Pipelined forward/backward/dummy-backward recursion with double-buffered alpha and gamma memories
- **Modulo-Normalized ACS** — Avoids per-cycle subtraction-based normalization; uses 10-bit modulo arithmetic with NEG_INF=−256 for correct comparison under wrap-around
- **LTE-Compliant Tail Bit Handling** — Proper 12-bit LTE trellis termination (6 per constituent encoder) with BER measured only over information bits
- **Paper-Mode Boundary Initialization** — Dummy forward recursion for non-zero cores and cross-segment dummy backward recursion, matching the Studer et al. boundary protocol
- **Zero-Mismatch RTL Verification** — RTL output matches two independent Python reference models (full-block and windowed radix-4) with 0/3200 mismatches across intrinsic LLRs, hard decisions, and extrinsic values
- **Monte Carlo BER Validation** — Multi-SNR sweep framework with configurable frame counts, error thresholds, and parallel execution
- **FPGA-Proven at 100 MHz** — Timing-clean implementation on Zynq-7010 (WNS = +0.300 ns), verified via ILA output capture matching RTL simulation
- **AXI4-Lite Processor Interface** — Full register map for PS-controlled input loading, decode triggering, and hard-decision readback; Vitis bare-metal test application included

---

## Tech Stack / Tools Used

| Category | Details |
|----------|---------|
| **HDL** | Verilog-2001, ~5,000 lines RTL + ~1,200 lines testbench |
| **FPGA Target** | Xilinx Zynq-7010 (xc7z010clg400-1) on Digilent Zybo Z7-10 |
| **EDA Tools** | Vivado 2024.1 (synthesis, implementation, ILA debug), Vitis 2024.1 (bare-metal ARM software) |
| **Simulation** | Icarus Verilog (iverilog/vvp) for behavioral and post-synthesis simulation |
| **Verification** | Python 3.10+ (NumPy, SciPy, Matplotlib) — bit-exact reference models and BER framework |
| **Interface** | AXI4-Lite slave with custom register map for Zynq PS ↔ PL communication |
| **Reference Papers** | Studer et al. (IEEE JSSC 2011), Shrestha & Paily (IEEE TCAS-I 2014), Shrestha (IEEE TVLSI 2021) |
| **Standard** | 3GPP TS 36.212 (LTE turbo coding), QPP interleaver |

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                         turbo_decoder (Top)                             │
│                                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌──────────┐    ┌────────────┐  │
│  │  8 Input     │───▶│  BCJR Core  │───▶│ Extrinsic│───▶│ Hard-Bit   │  │
│  │  BRAMs       │    │  #0 (SISO)  │    │  BRAMs   │    │ Decision   │  │
│  │  (sys/par    │    ├─────────────┤    │  (×2)    │    │  RAM       │  │
│  │   folded)    │───▶│  BCJR Core  │───▶│          │    │            │  │
│  │              │    │  #1 (SISO)  │    │          │    │            │  │
│  └─────────────┘    └──────┬──────┘    └────┬─────┘    └────────────┘  │
│         ▲                  │                │                           │
│         │           ┌──────┴──────┐         │                           │
│         │           │  QPP LUT    │◀────────┘                           │
│         │           │  (Interl.)  │  Extrinsic exchange                 │
│         │           └─────────────┘  via master/slave nets              │
│         │                                                               │
│  ┌──────┴────────────────────────────────────────────────────────────┐  │
│  │                  Top-Level FSM                                    │  │
│  │  Half-iteration control · Memory address generation               │  │
│  │  Natural ↔ Interleaved switching · Output write-back              │  │
│  └───────────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────────┘
```

**Each BCJR Core internally:**

```
Input LLRs ──▶ bm_preproc ──▶ bm_radix2 ──▶ bm_radix4
                                                  │
                 ┌────────────────────────────────┘
                 ▼
    ┌────────────────────────┐
    │  Forward Recursion (FR) │──▶ alpha_mem (double-buffered)
    │  8× acs_r4 units        │──▶ gamma_mem (double-buffered)
    └────────────────────────┘
    ┌────────────────────────┐
    │  Dummy Backward (DBR)   │──▶ beta_init for BR
    │  8× acs_r4 units        │
    └────────────────────────┘
    ┌────────────────────────┐
    │  Backward Recursion (BR)│──▶ llr_compute ──▶ Extrinsic LLR out
    │  8× acs_r4 units        │    (pipelined)
    └────────────────────────┘
```

---

## Implementation Details

### Radix-4 Branch Metric Pipeline

The branch metric computation uses BPSK-substituted preprocessing to eliminate multipliers entirely. Four pre-computed values `PRE[0..3]` encode all (x_s, x_p) bit hypotheses as signed sums of channel LLRs. These are wired (zero logic) into 16 radix-2 branch metrics per trellis step via a fixed predecessor lookup table, then composed pairwise into 32 radix-4 branch metrics (8-bit signed) covering two trellis steps simultaneously.

### Modulo-Normalized Add-Compare-Select

Each ACS unit selects the maximum of 4 radix-4 candidates using modulo arithmetic on 10-bit state metrics. Six pairwise differences generate a 6-bit comparison key, which indexes into a 24-entry LUT to select the winner. This avoids the critical-path penalty of subtraction-based normalization across all 8 states. The scheme is valid as long as the true metric spread stays below 512, guaranteed by the NEG_INF = −256 initialization gap.

### Sliding-Window Schedule

The 1600-step segment per core is divided into 54 windows of 30 trellis steps (15 radix-4 cycles). Three recursion units operate in a pipelined schedule: FR writes alpha/gamma for window *m*, DBR traverses window *m+1* backward to produce converged beta initialization, and BR decodes window *m−1* using stored alpha/gamma plus DBR-supplied beta. Double-buffered memories ensure FR and BR never contend for the same bank.

### Fixed-Point Quantization Strategy

| Signal | Width | Range |
|--------|-------|-------|
| Input / a-priori LLRs | 5-bit signed | [−16, +15] |
| Preprocessed BMs | 7-bit signed | [−64, +63] |
| Radix-4 BMs | 8-bit signed | [−128, +127] |
| State metrics (α, β) | 10-bit signed | [−512, +511] |
| Extrinsic LLR output | 6-bit signed | [−32, +31] |

Extrinsic scaling uses the shift-add approximation `L_e − (L_e >>> 2) − (L_e >>> 4)` ≈ 0.6875 × L_e, matching the LTE correction factor without a hardware multiplier.

### QPP Interleaver

The Quadratic Permutation Polynomial interleaver for K=3200 uses parameters f1=111, f2=240, precomputed into a 1600-entry ROM (`qpp_3200.hex`). The master/slave network routes extrinsic LLRs between natural-order and interleaved-order BRAMs across half-iterations.

### AXI4-Lite Integration

The `turbo_decoder_axi_lite` wrapper exposes a 10-register memory map for Zynq PS control: input BRAM loading (address/data/select/commit), decode start/status polling, and hard-decision readback. A separate PL-only bring-up top (`turbo_decoder_button_bringup`) embeds test vectors in ROM and uses physical buttons and LEDs for standalone FPGA validation without ARM software.

---

## Results

### Functional Verification

| Metric | Value |
|--------|-------|
| Channel hard BER (Eb/N0 = 1.0 dB) | 544 / 3200 = 0.170 |
| RTL decoded BER (11 half-iterations) | 1 / 3200 = 0.000313 |
| RTL vs Python reference (intrinsic) | **0 mismatches** / 3200 |
| RTL vs Python reference (hard bits) | **0 mismatches** / 3200 |
| RTL vs Python reference (extrinsic) | **0 mismatches** / 3200 |
| FPGA ILA capture vs RTL simulation | **0 mismatches** / 3200 |

### Monte Carlo BER Sweep (RTL-Equivalent Fixed-Point Model, R=0.375)

| Eb/N0 (dB) | BER | Errors | Bits | Frames |
|-------------|-----|--------|------|--------|
| 0.00 | 9.53 × 10⁻² | 2,745 | 28,800 | 9 |
| 0.25 | 6.08 × 10⁻² | 1,947 | 32,000 | 10 |
| 0.50 | 7.56 × 10⁻³ | 653 | 86,400 | 27 |
| 0.75 | 1.90 × 10⁻³ | 573 | 300,800 | 94 |
| 1.00 | 2.13 × 10⁻⁴ | 68 | 320,000 | 100 |

### FPGA Resource Utilization (Zynq-7010, xc7z010clg400-1)

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| Slice LUTs | 15,473 | 17,600 | 87.9% |
| Registers | 8,190 | 35,200 | 23.3% |
| Block RAM | 18.5 | 60 | 30.8% |
| DSPs | 6 | 80 | 7.5% |

### Timing

| Metric | Value |
|--------|-------|
| Clock target | 100 MHz |
| WNS (post-route) | +0.300 ns |
| WHS (post-route) | +0.023 ns |
| Timing met | **Yes** |

---

## Repository Structure

```
BITS-main/
├── rtl/                            # Synthesizable Verilog RTL (~5,000 lines)
│   ├── turbo_decoder.v             # Top-level: 2-core parallel decoder + memories + FSM
│   ├── bcjr_core.v                 # Single SISO core: 6-state FSM + window scheduler
│   ├── forward_recursion_unit.v    # FR: BM pipeline + 8 forward ACS units
│   ├── backward_recursion_unit.v   # BR: backward ACS + LLR output path
│   ├── dummy_backward_recursion_unit.v  # DBR: beta initialization via convergence
│   ├── llr_compute.v              # 1-stage pipelined LLR from α, β, γ
│   ├── acs_r4.v                   # Radix-4 ACS with modulo-normalized comparison
│   ├── bm_preproc.v               # BPSK-substituted preprocessing (4 PRE values)
│   ├── bm_radix2.v                # Radix-2 BM selection (wiring only)
│   ├── bm_radix4.v                # Radix-4 BM composition (R2 pair sums)
│   ├── alpha_mem.v                # Double-buffered alpha memory (register array)
│   ├── gamma_mem.v                # Double-buffered gamma memory (register array)
│   ├── input_bram.v               # Input LLR BRAM with host load interface
│   ├── extrinsic_bram.v           # Extrinsic exchange BRAM
│   ├── ld_bram.v                  # Final copied extrinsic output BRAM
│   ├── qpp_lut.v                  # QPP interleaver ROM
│   ├── master_net.v / slave_net.v # Interleaver routing network
│   ├── turbo_decoder_axi_lite.v   # AXI4-Lite wrapper for Zynq PS interface
│   └── turbo_decoder_button_bringup.v  # PL-only bring-up top (buttons + LEDs + ILA)
│
├── tb/                             # Testbenches (~1,200 lines)
│   ├── tb_turbo_decoder.v         # Full decoder testbench with BRAM loading
│   ├── tb_bcjr_core.v             # Standalone BCJR core testbench
│   ├── tb_button_bringup.v        # Button bring-up behavioral verification
│   ├── tb_dbr_standalone.v        # Isolated DBR unit testbench
│   └── tb_turbo_decoder_post_synth.v  # Post-synthesis timing simulation
│
├── scripts/                        # Python verification & tooling (~3,400 lines)
│   ├── windowed_parallel_ber.py   # RTL-bit-accurate BER model + Monte Carlo sweep
│   ├── turbo_ref_model.py         # Full-block Max-Log reference decoder
│   ├── gen_encoded_test_vectors.py # LTE encoder + AWGN + quantizer → BRAM hex files
│   ├── monte_carlo_ber.py         # Monte Carlo BER simulation driver
│   ├── full_block_float_turbo.py  # Floating-point turbo decoder (algorithm baseline)
│   ├── plot_windowed_parallel_ber.py  # BER curve plotting
│   ├── qpp_lut_gen.py             # QPP ROM generator for any K
│   └── *.tcl                      # Vivado synthesis/implementation/timing scripts
│
├── constraints/                    # FPGA constraint files
│   ├── Zybo-Z7-Master.xdc        # Full Zybo board master constraints
│   ├── turbo_decoder_button_bringup.xdc  # Button/LED/clock pin constraints
│   └── turbo_decoder_axi_ooc.xdc # Out-of-context AXI wrapper constraints
│
├── data/                           # Active test vectors (K=3200, N=2)
│   ├── qpp_3200.hex               # QPP interleaver LUT
│   ├── sys_*_ram.hex, par*_ram.hex # Input BRAM LLR data
│   ├── rtl_final_*.txt            # RTL output artifacts
│   ├── ref_final_*.txt            # Python reference outputs
│   └── ber_results.txt            # Current regression summary
│
├── fpga_bringup/                   # Zynq hardware bring-up
│   ├── vitis_app_src/             # Bare-metal C application (main.c, AXI drivers)
│   └── scripts/                   # ILA capture conversion, Vitis vector generation
│
├── docs/                           # Design documentation
│   ├── implementation_report.md   # Detailed architectural specification
│   ├── debug_changes.md           # RTL debug history and fix log
│   ├── windowed_parallel_ber_validation.md  # BER validation methodology
│   ├── rtl_gap_analysis_windowed_parallel_decoder.md  # RTL vs model gap tracking
│   └── zybo_axi_integration.md    # AXI register map and software sequence
│
├── archive/                        # Historical K=6144 data, earlier runs, legacy plots
└── *.pdf                           # Reference IEEE papers (Studer, Shrestha)
```

---

## How to Run the Project

### Prerequisites

- **Simulation:** Icarus Verilog (`iverilog`, `vvp`)
- **Python:** Python 3.10+ with `numpy`, `scipy`, `matplotlib`
- **FPGA (optional):** Vivado 2024.1+, Vitis 2024.1+, Digilent Zybo Z7-10 board

### Deterministic RTL Regression

```bash
# Generate QPP LUT
python scripts/qpp_lut_gen.py --K 3200

# Generate encoded test vectors (AWGN channel at Eb/N0 = 1.0 dB)
python scripts/gen_encoded_test_vectors.py --K 3200 --num-siso 2 \
    --ebn0-db 1.0 --channel-rate 0.375 --seed 57

# Compile and run RTL simulation
iverilog -g2012 -o tb/tb_turbo_decoder.vvp tb/tb_turbo_decoder.v rtl/*.v
vvp tb/tb_turbo_decoder.vvp

# Verify against Python reference models
python scripts/turbo_ref_model.py
python scripts/windowed_parallel_ber.py --decoder radix4 --K 3200 \
    --num-siso 2 --window-size 30 --half-iters 11 --quantize \
    --boundary-mode paper --from-bram-dir data
```

Expected: `0` mismatches across intrinsic, hard-bit, and extrinsic outputs.

### Monte Carlo BER Sweep

```bash
python scripts/windowed_parallel_ber.py --decoder radix4 --K 3200 \
    --num-siso 2 --window-size 30 --half-iters 11 --quantize \
    --boundary-mode paper --snr-rate-mode custom --channel-rate 0.375 \
    --ebn0-start 0.0 --ebn0-stop 1.0 --ebn0-step 0.25 \
    --max-frames 100 --min-errors 500 --jobs 8
```

### FPGA Synthesis (Vivado)

```bash
vivado -mode batch -source scripts/synth_timing_100mhz.tcl
```

### FPGA Bring-up (PL-only, no ARM software)

1. Create a Zybo Z7-10 Vivado project with all `rtl/*.v` and `data/*.hex` files
2. Set top module to `turbo_decoder_button_bringup`
3. Add `constraints/turbo_decoder_button_bringup.xdc`
4. Synthesize, implement, and generate bitstream
5. Program FPGA → Press BTN0 (load) → Wait for LED0 → Press BTN1 (decode) → LED2 indicates done

---

## Challenges Faced

**Modulo arithmetic correctness.** The radix-4 ACS uses modulo-normalized comparison instead of explicit subtraction normalization. Getting the NEG_INF initialization value right (−256, not −512) was critical — too large a gap causes wrap-around comparison failures, too small loses dynamic range. The 6-comparison-bit LUT covering all 24 valid orderings of 4 elements required careful enumeration.

**Partial-window synchronization.** The last window of each segment is shorter than W=30 trellis steps. An early design used a shared shortened step counter, which desynchronized FR, BR, and DBR since they operate on different windows simultaneously. The fix was to always run full 15-cycle windows and suppress out-of-range outputs via address filtering — architecturally simpler and immune to the synchronization bug.

**Branch metric mapping fidelity.** The radix-2 predecessor table and path metric grouping (xs=0 vs xs=1) must exactly match the LTE trellis polynomial. Early mismatches between the branch metric generator and the LLR compute unit caused subtle BER degradation that only showed up in Monte Carlo sweeps, not single-frame tests.

**FPGA resource pressure.** The Zynq-7010 has only 17,600 LUTs. The 2-core decoder with ILA debug probes initially exceeded the device. The solution was a packed 5-bit single-probe ILA configuration and aggressive area optimization strategies (`Flow_AreaOptimized_high`, `FLATTEN_HIERARCHY full`), bringing utilization to 87.9%.

**Vivado `$readmemh` path resolution.** Synthesis and simulation resolve hex file paths from different working directories. A pre-synthesis Tcl hook was developed to copy data files into the active run directory, ensuring consistent behavior across project configurations.

---

## What I Learned

- **Algorithm-to-hardware thinking:** Translating a published paper's algorithm into synthesizable RTL requires understanding not just what the math says, but how it maps to real datapath constraints — bit widths, pipeline hazards, memory banking, and initialization timing.
- **Bit-exact verification methodology:** Building a Python reference model that is not just "close" but produces identical outputs to the RTL (0/3200 mismatches) is far harder than building one that is "approximately correct." Every quantization, saturation, and rounding decision must match exactly.
- **Fixed-point design trade-offs:** The interplay between quantization (5-bit input → 10-bit metrics → 6-bit extrinsic) and BER performance requires systematic analysis. The 0.6875 scaling factor approximation via shift-add is a classic VLSI trick that I now understand from first principles.
- **FPGA bring-up discipline:** The gap between "simulation passes" and "hardware works" is real. AXI register ordering, BRAM initialization file paths, ILA probe sizing, and clock domain assumptions all required methodical debugging on physical hardware.
- **Monte Carlo simulation design:** Statistically meaningful BER measurement requires careful seed management, error-count stopping criteria, and SNR normalization — not just "run more frames."

---

## Future Improvements

- **Scale to 8 parallel SISO cores** — The architecture and QPP interleaver already support N=8; the routing network and memory duplication are the main implementation tasks
- **Post-synthesis timing simulation** — Extend the existing post-synth testbench to run full BER regression, not just functional smoke tests
- **K=6144 support** — Parameterized RTL already accepts different frame lengths; validated vectors and QPP ROM for K=6144 are archived and ready for re-activation
- **Log-MAP implementation** — Replace max-log approximation with correction-term lookup for ~0.1 dB BER improvement
- **DMA-based input loading** — Replace the current register-by-register AXI BRAM loading with AXI DMA for practical throughput in a real baseband pipeline
- **ASIC synthesis exploration** — Run the RTL through a standard-cell flow (e.g., FreePDK45) to obtain area, power, and timing estimates comparable to published ASIC results

---

## Conclusion

BITS demonstrates a complete FPGA digital design lifecycle — from studying IEEE-published turbo decoder architectures, through microarchitectural design of a parallel radix-4 Max-Log M-BCJR engine, to verified Verilog RTL, bit-exact multi-model verification, Monte Carlo BER validation, and timing-clean FPGA hardware running on a Zynq-7010 board. The project exercises skills across algorithm design, RTL engineering, fixed-point arithmetic, FPGA resource optimization, hardware bring-up, and systematic verification methodology — the core competencies of a digital design or communications systems engineer.

---

<p align="center">
  <img src="https://img.shields.io/badge/HDL-Verilog--2001-blue" />
  <img src="https://img.shields.io/badge/Target-Zynq--7010-green" />
  <img src="https://img.shields.io/badge/Clock-100%20MHz-orange" />
  <img src="https://img.shields.io/badge/Timing-Met-brightgreen" />
  <img src="https://img.shields.io/badge/RTL%20Mismatches-0%2F3200-brightgreen" />
</p>
