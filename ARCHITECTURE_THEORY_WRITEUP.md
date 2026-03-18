# Turbo Decoder Architecture and Theory Write-Up (Implemented Baseline)

Date: 2026-03-10
Project: Parallel-Turbo-Decoder-ASIC-for-3GPP-LTE

## 1) Scope and Intent

This repository implements a synthesizable, modular turbo-decoder baseline aligned with the high-level architecture used in LTE turbo decoding and discussed in `11JSSC-turbo.pdf`.

What is implemented now:
- Two constituent SISO decoders (max-log-MAP baseline)
- Iterative exchange of extrinsic information between SISOs
- QPP interleaver addressing using the recursive LTE/paper-friendly form
- Fixed-point metrics and saturating arithmetic
- End-to-end simulation with encoder-consistent LTE-like vectors

What is intentionally simplified at this stage:
- Radix-2 schedule instead of radix-4 throughput architecture
- No full banked contention-free 8-way memory system
- No full sliding-window boundary exchange optimization
- No complete LTE block-size/QPP table yet (subset + overrides in vector tool)

This is a functionally coherent baseline suitable for continued evolution.

## 2) High-Level Architecture

Main RTL blocks:
- `turbo_decoder_top.vhd`
- `turbo_iteration_ctrl.vhd`
- `siso_maxlogmap.vhd` (instantiated twice)
- `qpp_interleaver.vhd`
- `llr_ram.vhd`
- `turbo_pkg.vhd` (types, trellis, arithmetic helpers)

Conceptual dataflow per iteration:
1. **SISO1 half-iteration (original domain)**
   - Inputs: `L_sys(original)`, `L_par1(original)`, a-priori (baseline starts from zero)
   - Output: extrinsic `L_e1(original)`
2. **Interleave + store/read**
   - `L_e1` written to RAM by original index
   - SISO2 request stream generates QPP addresses
   - RAM read returns `L_e1` aligned as SISO2 a-priori
3. **SISO2 half-iteration (interleaved domain)**
   - Inputs: `L_sys(interleaved)`, `L_par2(interleaved)`, `L_apri2(interleaved)`
   - Output: extrinsic `L_e2(interleaved)`
4. **Posterior output**
   - `L_post(interleaved) = L_e2 + L_sys(interleaved) + L_apri2(interleaved)`

`turbo_iteration_ctrl` repeats this for `n_iter` full iterations.

## 3) SISO Decoder Theory (Detailed)

This is the critical part.

### 3.1 Trellis model used

The constituent code is LTE-like 8-state RSC with:
- Feedback polynomial: 13 (octal)
- Feedforward polynomial: 15 (octal)

In `turbo_pkg.vhd`:
- `rsc_next_state(cur_state, u)` computes trellis transition
- `rsc_parity(cur_state, u)` computes parity bit for transition

So each state has two outgoing branches (`u=0`, `u=1`).

### 3.2 Max-log-MAP decomposition

For each symbol index `k`, decoder computes branch metric `gamma_k`, forward metric `alpha_k`, backward metric `beta_k`, and then extrinsic LLR.

#### Branch metric

For candidate `(u,p)`:
- Exact log-MAP would need `log(sum(exp(.)))`
- Max-log approximation replaces `log-sum-exp` with `max`

Implemented metric form (proportional):
- `gamma ~ 0.5 * ((1-2u)*(L_sys + L_apri) + (1-2p)*L_par)`

`bm_for_transition(...)` computes this for a state/input transition.

#### Forward recursion (`alpha`)

Definition:
- `alpha_{k+1}(s') = max over predecessors s and input u leading to s' of [alpha_k(s) + gamma_k(s->s')]`

Implementation notes:
- Initial condition at start of block:
  - State 0 metric = 0
  - Other states = large negative (`-1024` in metric domain)
- At each `k`, updated alpha is normalized by subtracting global max (`max8`) to avoid growth/overflow.

Important indexing fix applied:
- Store `alpha(k)` for symbol `k` (not `alpha(k+1)`), because LLR at symbol `k` must use `alpha(k)`.

#### Backward recursion (`beta`)

Definition:
- `beta_k(s) = max over u of [beta_{k+1}(s_next) + gamma_k(s->s_next)]`

Initialization used:
- End condition approximated with known zero final state:
  - `beta_K(0)=0`, others large negative.
- This is consistent with terminated trellis assumption in LTE constituent decoding.

Again normalized each step by subtracting max.

#### Extrinsic/posterior separation

For each `k`, compute:
- `M0 = max metrics over all paths with u=0`
- `M1 = max metrics over all paths with u=1`
- Posterior LLR approx: `L_post ~ M1 - M0`
- Extrinsic output: `L_e = L_post - L_sys - L_apri`

In implementation, LLR generation uses:
- `alpha(k)`
- `gamma(k)`
- `beta(k+1)`

That exact alignment was corrected for structural correctness.

### 3.3 Fixed-point and numerical behavior

Types (`turbo_pkg.vhd`):
- `llr_t`: signed 8-bit
- `metric_t`: signed 12-bit

Operations:
- Saturating metric add: `sat_add`
- Metric->LLR saturation: `metric_to_llr_sat`
- Normalization of alpha/beta each trellis step

Why this matters:
- Without normalization/saturation, metrics can diverge and overflow.
- Fixed-point max-log is stable enough for RTL while preserving sign reliability.

## 4) Iterative Control and Scheduling

Controller states (`turbo_iteration_ctrl`):
- `IDLE`
- `RUN1` (SISO1 active)
- `RUN2` (SISO2 active)
- `FINISH`

Behavior:
- On `start`, enter `RUN1` and pulse `run_siso_1` for one clock
- Wait `siso_done_1`, then enter `RUN2` and pulse `run_siso_2` for one clock
- Wait `siso_done_2`, increment iteration count
- If `iter+1 >= n_iter`, assert `done`

Important implementation detail:
- The controller no longer holds `run_siso_1` or `run_siso_2` high for the whole half-iteration.
- Those outputs are now launch pulses.
- The top-level converts each launch pulse into a full-symbol replay by setting `feed1_active` or `feed2_active` and then streaming until the local symbol counter reaches `k_len`.

This split is structurally clean:
- controller = iteration sequencing
- top-level = data replay scheduling and pipeline alignment

## 5) QPP and Memory Alignment

### 5.1 QPP block

`qpp_interleaver.vhd` now follows the recursive form that is architecturally closer to the paper:
- `pi(0) = 0`
- `delta(0) = (f1 + f2) mod K`
- `b = (2 * f2) mod K`
- `pi(k+1) = (pi(k) + delta(k)) mod K`
- `delta(k+1) = (delta(k) + b) mod K`

Why this is useful in hardware:
- You do not multiply by `k` or `k^2` every cycle.
- After initialization, each new address is produced using only modular additions and conditional subtracts.
- This matches the streaming nature of SISO2 input scheduling much better than recomputing the quadratic formula from scratch.

This recursive sequence is mathematically equivalent to:
- `pi(i) = f1*i + f2*i^2 mod K`

but it is the recurrence, not the closed-form equation, that is implemented in RTL.

### 5.2 RAM and pipeline alignment

`llr_ram.vhd` is synchronous read/write.

Top-level adds alignment pipeline so that for SISO2:
- first request symbol -> QPP `start` pulse -> output `pi(0)=0`
- later request symbols -> QPP `valid` pulses -> recursive address advance
- QPP output -> RAM read address
- RAM data (a-priori) captured with matching interleaved systematic/parity sample

This is why `turbo_decoder_top` has staged signals (`s2_stage1`, `s2_stage2`) and explicit QPP control signals:
- `pi_start`: asserted only for the first SISO2 request of a half-iteration
- `pi_step`: asserted for the remaining SISO2 request symbols
- `feed2_active`: stays high locally until all `k_len` SISO2 request symbols have been issued

## 6) LTE-Like Stimulus/Reference Flow

To evaluate decoder behavior with realistic origin of LLRs:

`tools/gen_lte_vectors.py` performs:
1. Generate random information bits
2. QPP interleave for second constituent
3. Encode both constituent streams with 8-state RSC
4. Apply trellis termination (3 tail bits each constituent)
5. BPSK modulation + AWGN channel
6. Compute channel LLRs (`2*y/sigma^2`)
7. Quantize to int8 for RTL input vectors
8. Also run floating max-log reference and dump reference outputs

Files produced:
- `sim_vectors/lte_frame_input_vectors.txt`
- `sim_vectors/lte_frame_generation_report.txt`
- `sim_vectors/reference_interleaved.txt`
- `sim_vectors/reference_original.txt`

## 7) Assumptions (Explicit)

1. **Max-log approximation** instead of full log-MAP.
2. **Radix-2 trellis processing** (throughput simplification).
3. **Terminated trellis assumption** for beta initialization (`state 0` favored at end).
4. **Fixed-point widths**: 8-bit LLR, 12-bit state metric.
5. **No full LTE banked-memory contention-free schedule** yet.
6. **No full sliding-window border metric exchange** yet.
7. **QPP table subset in tooling** (can override `f1,f2` via CLI).
8. **Tail bits are generated in vector tooling**, while RTL decode core currently operates on provided block LLRs without explicit separate tail-phase control states.

## 8) Current Validation Interpretation

With the present baseline and `n_iter=6` run:
- Structural compile/elaboration passes
- Synth checks pass (`ghdl --synth`) for all major entities
- All TBs pass
- End-to-end output coverage is complete (`K` symbols decoded)

Reference mismatch still exists vs floating model (hard/sign differences). This is expected at this stage due to simplifications and fixed-point baseline behavior. The framework now makes these gaps measurable and traceable.

## 9) If You Are Studying SISO (Practical mental model)

Use this 4-step mental loop at symbol `k`:
1. **Forward confidence**: how likely each state is before seeing symbol `k` (`alpha(k)`).
2. **Branch evidence**: what this symbol says about `u=0/1` for each state transition (`gamma(k)`).
3. **Backward confidence**: how likely future observations are after this symbol (`beta(k+1)`).
4. **Bit decision evidence**:
   - best path metric among all `u=1` paths minus best among all `u=0` paths.
   - subtract prior/systematic parts to isolate extrinsic information.

That is exactly what max-log SISO computes in hardware-friendly form.

## 10) Next technical upgrades (toward closer paper matching)

- Radix-4 path-computation datapath (two trellis steps/cycle)
- Windowed/parallel SISO with boundary metric exchange
- Full LTE `(K,f1,f2)` table integration in tooling and RTL config
- Explicit tail-phase handling in decode control
- Wider/fractional fixed-point design-space tuning with BER sweeps
