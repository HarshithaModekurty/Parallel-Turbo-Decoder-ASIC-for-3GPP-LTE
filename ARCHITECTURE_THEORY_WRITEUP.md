# Parallel LTE Turbo Decoder: Architectural Theory & Debugging Synthesis

This document serves as the complete technical design log, architectural theory explanation, and simulation debugging history for the fully synthesizable Parallel Turbo Decoder specifically targeting 3GPP-LTE constraints ($K=6144$, Radix-4, 8-parallel workers). 

---

## 1. The Core Concept (Layman's Analogy)

Imagine two master detectives (the two decoding phases: Phase 0 and Phase 1) tasked with transcribing an unreadable, heavily smudged letter (the received signal damaged by noise). 
* **Phase 0 (Linear Decoder)** reads the letter from top left to bottom right. 
* **Phase 1 (Interleaved Decoder)** reads the same letter using a highly specific, scrambled code-book sequence (the **QPP Interleaver**). 

The trick? They don't do it just once. They do it **8 times iteratively**. On the first pass, Phase 0 makes a probabilistic (soft) guess on what each word is, and places these clues in a shared locker (**Extrinsic RAM**). Phase 1 then reads the letter using its scrambled pattern, looks at the clues Phase 0 left, and generates *better* clues. They swap hints back and forth. By the 8th pass, both detectives' probabilities converge onto a nearly perfect solution, and they declare the message fully decoded (`out_valid`).

To make this unimaginably fast, we do not read the letter one word at a time. We slice the letter into $P=8$ equal chunks and hire 16 total detectives (8 for Phase 0, 8 for Phase 1) to read their sections simultaneously.

---

## 2. Advanced Architectural Layout

### A. Radix-4 Soft-In Soft-Out (SISO) Core
Standard Viterbi algorithms process one bit at a time (Radix-2). Our architecture utilizes **Radix-4**, which consumes 2 bits per clock cycle, doubling the throughput without doubling the clock frequency. It computes the $\alpha$ (Forward), $\beta$ (Backward), and $\gamma$ (Branch) metrics. 

### B. The Pipelined LLR Extractor (Localized)
A major architectural decision was moving the **`radix4_extractor`** completely *inside* the `siso_maxlogmap` rather than placing it at the top-level. 
* **The Reason:** Calculating the final likelihood requires summing 32 combinations of $\alpha$, $\gamma$, and $\beta$ metrics. If placed at the top level, the SISO would have to route hundreds of intermediate large-bit-width signals across the FPGA fabric, destroying timing closure. 
* **The Fix:** The metrics are calculated deep within the SISO, collapsed into a strictly scaled 6-bit Extrinsic LLR, and only that clean mathematically condensed 6-bit vector is passed upwards to the routing network.

### C. QPP Interleaver & Batcher-Banyan Router
When 8 parallel processors finish their chunk of Phase 1, they attempt to write their 8 clues back to the shared memory. But because Phase 1 is scrambled, Worker 0 might need to write to Bank 5, while Worker 1 needs to write to Bank 2. 
To prevent memory collisions, we integrated a **Batcher sorting network**. The QPP accurately calculates the destination banks using the $f_1, f_2$ constants defined by the LTE standard (e.g., $f_1=263, f_2=480$ for $K=6144$), and dynamically steers the `ext_llr` data directly into the exact required memory bank collision-free.

---

## 3. The Simulation Reality: Overcoming Hardware Logic Bugs

While transitioning from purely theoretical equations to FPGA-synthesizable VHDL, we encountered and conquered several critical "Real-World" simulation hazards.

### Bug 1: The Combinatorial Black Hole
* **Issue:** Vivado detected combinatorial loops where `beta_decode` outputs fed directly back into their own inputs asynchronously, locking the synthesizer into infinite recursion.
* **Resolution:** Pure mathematical ACS (Add-Compare-Select) paths were intercepted by strict synchronous boundaries (`_next` signals latched strictly on `rising_edge(clk)`). This allowed the FPGA to map the block into deterministic D-Flip Flops.

### Bug 2: U to X Probability Poisoning
* **Issue:** In VHDL simulations, an uninitialized array starts exactly at `"U"`. In Iteration 1 of the Turbo decoding, the Extractor attempted to add the Systematic probability to an uninitialized Extrinsic RAM cell ($\text{Math} + U = X$). This `'X'` corruption wrote back to the RAM, permanently destroying all 8 iterations.
* **Resolution:** The `folded_llr_ram.vhd` multi-dimensional arrays were rigidly initialized to mathematical zeros `(others => (others => '0'))`. The first iteration now starts with purely neutral biases.

### Bug 3: The Delta-Cycle Array Crash (`Index 768 out of bound 0 to 767`)
* **Issue:** Each memory bank strictly holds 768 pieces of data. On exactly the 768th clock cycle, the controller synchronous logic incremented the counter one boundary too high before safely shutting off the pipeline. In that micro-second gap (Delta-Cycle), the unclocked combinatorial Phase logic tried to fetch index 768, instantly crashing the Vivado Simulator.
* **Resolution:** The `seq_count` counters were aggressively clamped using integer threshold limits, explicitly protecting hardware pointers from wandering outside the $P$ physical logic gates.

---

## 4. Precision Timing Breakdown: Justifying the 192 µs Simulation

Upon generating valid LTE evaluation waveforms natively, the output metrics behaved completely according to correct hardware theory constraints.

**Given Parameters:**
* Clock Period: $10\text{ ns}$ (100 MHz)
* Block Length ($K$): 6144
* Parallelism ($P$): 8 Windows ($\rightarrow 768$ cycles per phase)
* Iterations: $8$ full passes (16 total half-phases)
* Deep Pipeline Delay: 46 shift-register stages

**The Timeline:**
1. **$0 \text{ to } 61.44 \ \mu\text{s}$ (Memory Load):** The external host streams exactly $K=6144$ data triples (Systematic, Parity 1, Parity 2) serially into the dual-port memory. 
2. **$61 \ \mu\text{s} \text{ to } 180 \ \mu\text{s}$ (The Crunching Silence):** The core executes Iterations 1 through 7. You will observe the `l_post` bus rapidly vibrating with "garbage" values. **This is intentional.** In ASIC design, we do not clamp intermediate data buses to `0` artificially because multiplexing a 56-bit bus costs silicon space and wastes dynamic power. The external system correctly entirely ignores this vibrating bus because `out_valid = '0'`.
3. **$180 \ \mu\text{s} \text{ to } \sim191.6 \ \mu\text{s}$ (The Golden Output):** The iteration controller strikes Iteration 8, Phase 1. The mathematical limit has been reached. A solid stream of final, correct Likelihood Vectors pours out of the parallel bus and `out_valid` is gated high for exactly 768 clock cycles.
4. **$192 \ \mu\text{s}$ (Pipeline Flush):** The pipeline shift-registers finally report empty (`valid_sr=0`), the `out_valid` flag drops low, and a single `done = '1'` pulse cleanly flags the end of the operation.

---

## 5. Next Steps: Path to Physical FPGA Implementation

The RTL is now completely functionally verified against floating-point Python references and is **synthesizable**. To map this directly onto an FPGA (e.g., Xilinx Zynq / Kintex), the final implementation steps are:

1. **AXI4-Stream Wrappers:** Our interface uses raw `in_valid` and `in_idx` handshakes. A thin top-level wrapper module is needed to convert Xilinx's `TVALID/TREADY/TDATA` protocols to stream packets in from DMA/Processor memory dynamically.
2. **True Block RAM Instantiation (`BRAM`):** Vivado may attempt to synthesize `folded_llr_ram` and `input_ram` into distributed LUT elements (LUTRAM), causing massive logic bloat. We must add the explicit synthesis attribute `(* ram_style = "block" *)` to the arrays in VHDL to force mapping to dedicated hardware BRAMs.
3. **Clocking Wizard & Constraints (`.xdc` file):** Introduce an MMCM/PLL to safely lock the internal clock domain between $100$ and $250\text{ MHz}$, depending on target ASIC timing closure, and constrain setup/hold timings on the I/O pads.
