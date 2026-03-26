# FPGA Bring-Up Notes

Date: 2026-03-25

## Current State

After narrowing the control and QPP arithmetic widths, the active full decoder top, `rtl/turbo_decoder_top.vhd`, now synthesizes to:

- Slice LUTs: 17666 / 17600 = 100.38%
- LUT as Logic: 15330
- LUT as Memory: 2336
- RAMB36: 16
- Bonded IOB: 98 / 100 = 98.00%

This is a major improvement from the earlier 22282 LUT result. The core is now only 66 LUT above the `xc7z010clg400-1` limit.

## What Was Added For Board Bring-Up

Added files:

- `rtl/turbo_decoder_zybo_smoke_top.vhd`
- `rtl/fpga_smoke_vectors_pkg.vhd`
- `constraints/turbo_decoder_zybo_smoke_top.xdc`
- `tools/gen_fpga_vector_pkg.py`

Purpose:

- `turbo_decoder_zybo_smoke_top.vhd` is a minimal Zybo-facing wrapper.
- It runs a fixed `K = 40` smoke vector set from ROM-like constants, not the full `K = 6144` frame flow.
- It uses only:
  - `sysclk`
  - `btn[0]` as reset
  - `btn[1]` as start
  - `led[3:0]` as status

Status LEDs:

- `led[0]`: loading input frame
- `led[1]`: decoder waiting/running
- `led[2]`: decode completed
- `led[3]`: all expected outputs observed

The smoke wrapper synthesizes comfortably on the same Zybo target:

- Slice LUTs: 152
- Slice Registers: 75
- Bonded IOB: 7

This wrapper is for board smoke testing only. It is not the full-size production test path.

## Why The Smoke Wrapper Is Small

The full decoder core is already near the Z7-10 LUT limit. So the wrapper was intentionally kept small:

- no wide top-level frame input pins,
- no full-frame PL-side capture RAM,
- no PL-side UART block,
- no large replay controller for `K = 6144`.

That keeps the board-facing top practical while the full core is still being pushed toward fit closure.

## Best Way To Feed Input LLRs On FPGA

For real full-frame testing on Zybo Z7, the best approach is:

1. Use BRAM as the storage for `l_sys`, `l_par1`, and `l_par2`.
2. Use the Zynq PS to write those BRAMs before starting the PL decoder.
3. Start the decoder from a small control register or GPIO pulse.
4. Capture `out_idx` and `l_post` into an output BRAM.
5. Let the PS read that BRAM back and write a text dump.

Why this is the best path:

- It avoids exposing huge frame interfaces on FPGA pins.
- It avoids adding a large PL-side stimulus engine when the design is already near resource limit.
- It uses the Zynq architecture the way the board is intended to be used.

## Alternative Input Methods

If you do not want to use the PS first, the next-best options are:

### 1. Preinitialized BRAM/ROM Replay

- Store one test frame in BRAM or ROM initialized at bitstream generation time.
- Use a small FSM to replay one symbol per cycle into `turbo_decoder_top`.
- This is good for fixed regression frames.

Tradeoff:

- Good for smoke tests.
- Not flexible for many frames unless you keep rebuilding the bitstream.

### 2. JTAG Debug Path

- Use JTAG-to-AXI, Debug Bridge, VIO, or ILA.
- Good for observing internal activity or hand-loading small experiments.

Tradeoff:

- Useful for debug.
- Not efficient for repeated BER experiments.

## UART Note On Zybo Z7

The easiest USB-UART path on Zybo Z7 is typically through the Zynq PS side, not as a raw PL pin-level UART. If you want a pure-PL UART, use a PMOD/UART bridge or route through a PS-assisted design instead of assuming the onboard USB-UART is directly connected to PL GPIO.

## Best Way To Observe Output LLRs

For serious testing, do not try to look at final LLRs only on LEDs. Instead:

1. Capture the streamed outputs `out_valid`, `out_idx`, and `l_post` into an output BRAM.
2. Read them back through the PS.
3. Write a dump file with this format:

```text
# idx_orig final_llr seen
0 12 1
1 -7 1
2 0 0
...
```

That matches the expectation of the existing BER tool.

## How To Decode LLRs Into Bits

Use the same hard-decision rule already used by the repository tooling:

- decoded bit = `1` if `final_llr > 0`
- decoded bit = `0` otherwise

This is the rule implemented in `tools/compute_ber_from_llr_dump.py`.

## How To Compare FPGA Results Against Expected Bits

Use the same vector file that was used to feed the FPGA run. Then compare the captured LLR dump with:

- `tools/compute_ber_from_llr_dump.py`

Recommended flow:

1. Keep the FPGA output dump in the same `idx llr seen` format as the testbench dump.
2. Run:

```text
python tools/compute_ber_from_llr_dump.py --vec-file <your_vector_file> --llr-file <your_fpga_dump> --out <report_file>
```

This gives:

- valid output count
- missing output count
- hard-decision bit errors
- BER totals

## Recommended Next Step

For immediate progress:

1. Keep using `rtl/turbo_decoder_top.vhd` as the core.
2. Use the new smoke wrapper for first board programming.
3. For real full-frame testing, move to a PS-written BRAM input path and PS-read BRAM output path.
4. Continue core LUT cleanup until the full decoder fits below the Z7-10 limit with margin.

The core is now close enough to fit that the next iterations should focus on:

- removing the remaining 66-LUT overrun,
- and, if possible, pushing the six SISO frame memories out of LUTRAM and into explicit BRAM structures.
