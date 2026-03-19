# Turbo Decoder Architecture and Theory Write-Up (Parallel Radix-4 Edition)

Date: March 19, 2026
Project: Parallel-Turbo-Decoder-ASIC-for-3GPP-LTE

This document outlines the theoretical and structural details of the modern high-throughput Parallel Radix-4 Turbo Decoder architecture implemented in this repository. It is designed to match the expectations of leading ASIP hardware (like the JSSC 2011 paper), dropping the slow baseline techniques in favor of sliding-windows, modulo math, and parallel routing.

---

## 1. The Layman's Primer: How Turbo Decoding Works
Imagine two detectives (SISO Decoders) trying to read a long encrypted message that was corrupted by noise. 

- **Detective 1** reads the message from start to finish normally. 
- **Detective 2** reads a scrambled (interleaved) version of the same message. 

Because the noise affects the normal and scrambled messages differently, the detectives will have different clues. After Detective 1 finishes a pass, he writes down his *hunches* on sticky notes (this is the **Extrinsic Information**). Detective 2 uses those sticky notes as "prior knowledge" (A-Priori) before tackling his scrambled version. He then makes his own sticky notes, hands them back to Detective 1, and so on. After a few "Iterations" of passing notes back and forth, they will almost always agree on a perfectly error-free message.

### What is an LLR?
LLR stands for **Log-Likelihood Ratio**. It is our "confidence score." 
- If the LLR is `+15`, the hardware is absolutely sure the bit is a `0`.
- If the LLR is `-15`, it is absolutely sure the bit is a `1`.
- If the LLR is `0`, it has no clue.

---

## 2. Breaking the Speed Limit: High-Throughput Parallelism
The baseline algorithm takes *thousands* of clock cycles to decode one block because it walks the entire frame sequence (up to 6144 bits) one by one. Our new architecture solves this using three major upgrades:

### A. Parallel Cores (P=8)
Instead of one detective working alone, we hired 8 detectives (`siso_maxlogmap` cores). The 6144-bit frame is chopped into 8 equal slices. All 8 cores decode their slice at the exact same time.

### B. Folded Memory
When 8 cores finish their work, they need to write 8 sticky notes to memory simultaneously. If two cores try to write to the same memory bank, they crash (Memory Contentions). 
We use **Folded Memory**, dividing our storage into 8 independent dual-port RAM banks (`folded_llr_ram.vhd`). The mathematical magic of the LTE QPP Interleaver algorithm guarantees that no matter how scrambled the text gets, **no two cores will ever look in the same bank at the same time.**

### C. Master-Slave Batcher Router
Since Core 3 might need to read a sticky note that happens to be sitting in Bank 7, we need an instant switching network (`batcher_router.vhd`). 
- **The Master Router** acts as the switchboard logic. It takes the interleaver addresses and figures out who connects to whom.
- **The Slave Router** is the physical track switch. It takes the data and physically routes the wires instantly to the right processor.

---

## 3. Inside the Core: Radix-4 and Sliding Windows

### Radix-4 (Taking the stairs two at a time)
A standard decoder evaluates 1 bit (2 possible paths, 0 or 1) per clock cycle (Radix-2). 
Our **Radix-4** decoder evaluates **2 bits** simultaneously per cycle. That means 4 possible paths per state (00, 01, 10, 11), but it halves the time required to finish a frame! To manage this, `radix4_bmu` (Branch Metric Unit) calculates 16 possible path combinations instantly combining Systematic, Parity, and A-Priori scores.

### Overlapped Sliding Windows (W=30, L=16)
Turbo decoding requires calculating "Forward" probabilities (alpha metrics) and "Backward" probabilities (beta metrics) across the block before making a final decision. 
Storing the forward metrics for a massive 6144-bit frame requires absurd amounts of silicon area. 
**The Solution:** We break the decoding into tiny chunks (windows) of 30 Radix-4 stages (W=30). 

**The Learning Problem:** To walk backwards through a 30-stage window, you need to know exactly where you started... but how do you know the starting state if you are in the middle of a continuous frame?
**The "Dummy" Learning Fix:** We employ a Backward Learning Unit (`u_acs_ln`). We start L=16 stages *ahead* of our window, assume an arbitrary starting state, and calculate backwards. Thanks to Markov-Chain probability behavior, by the time we travel 16 steps back, the metrics mathematically "converge" on the correct answer. We then use this perfectly converged state metric to seed our true W=30 Backward Decoding Unit.

---

## 4. The Engineering Trick: Modulo Arithmetic
As we accumulate confidence scores inside the engine (forward and backward metrics), the numbers get infinitely bigger until they overflow the digital bits. Standard decoders calculate the maximum metric on every cycle and subtract it from everything to keep it normalized. Finding a maximum among 8 paths *while* subtracting is a massive delay that hurts the chip's max Clock Frequency.

**Our Fix:** Two's Complement Modulo Arithmetic.
We let the metrics overflow on purpose! We use a 10-bit integer. When it hits `+511`, it wraps around to `-512` (like a car odometer rolling from 9999 to 0000). 
Because of modular math rules, as long as the true difference between any two paths isn't larger than half the odometer, we can safely compare them by just doing a simple subtraction (`A - B`) and looking at the sign bit. If the sign bit is `0`, A is larger. If it is `1`, B is larger. This totally eliminates the normalization bottleneck!

---

## 5. System Specifications & Data Formats

### Numerical Precision & Widths
We aggressively quantized the signals to save silicon area while barely affecting the Signal-to-Noise Ratio (SNR) capabilities compared to floating-point Python models:

| Signal Type | VHDL Type | Width | Range | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Input Channel LLRs** | `llr_t` | 5-bit | -16 to +15 | Systematic and Parity scores streaming from the RF Demodulator. |
| **Extrinsic LLRs** | `ext_llr_t` | 6-bit | -32 to +31 | The "sticky notes" stored in Folded RAM passed between iterations. |
| **Internal Metrics** | `metric_t` | 10-bit | -512 to +511 | Modulo wrap-around metrics used deeply inside the ACS engines. |

### Architectural Parameters
| Parameter | Value | Definition |
| :--- | :--- | :--- |
| `G_P` | 8 | Number of concurrent Radix-4 Sliding Window Decoders tracking the block. |
| `G_W` | 30 | Window Depth (Radix-4 Stages). Represents 30 * 2 = 60 Bits. |
| `G_L` | 16 | Learning Depth. Represents 16 * 2 = 32 Bits converging backwards to find the state seed. |
| `RAM Banks` | 8 | Dual-Port Folded memory arrays. Width is 6-bits per bank. |

### Control Signal Execution
- `run1` / `run2`: Phase 1 activates linear index reading. Phase 2 engages the Interleaver polynomial QPP router engine and triggers the switch-matrix to cross paths.
- `clk` / `start`: Synchronous pipelined architecture. Data outputs pipeline latency equals the shift-buffer sizes (W + L = 46 stages) before popping out the `done` high flags.
