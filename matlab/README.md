# MATLAB Turbo Decoder

This folder contains a self-contained MATLAB reference model for the LTE-style turbo decoder used in this repo.

Implemented assumptions:
- LTE QPP interleaver table up to `K = 6144`
- terminated 8-state RSC constituent encoders
- ideal floating-point log-MAP / BCJR reference path
- max-log-MAP constituent decoding
- RTL-style fixed-point radix-4/windowed decoding path
- iterative turbo decoding with configurable half-iterations
- optional repo-style 5-bit channel/parity input LLR quantization
- optional extrinsic scaling, default `11/16`

Main entry points:
- `run_turbo_ber_demo.m`
  - quick BER/FER example with floating and RTL-style fixed curves
- `run_turbo_ber_k3200_heavy.m`
  - heavier `K = 3200` BER/FER run
- `run_turbo_ber_k6144_heavy.m`
  - heavier `K = 6144` BER run
- `run_compare_model_vs_rtl_k3200.m`
  - overlays MATLAB model BER with the actual RTL BER sweep already stored in `sim_vectors/ber_sweep/ber_sweep_summary.csv`
- `run_compare_model_vs_rtl_k6144.m`
  - overlays MATLAB model BER with the actual RTL BER sweep for `K = 6144`
- `lte_turbo_ber_sweep.m`
  - reusable simulation function that returns BER/FER data
- `plot_lte_turbo_results.m`
  - BER plot helper for one or more sweep results
- `load_rtl_ber_summary.m`
  - loads actual RTL BER summary CSV
- `compare_rtl_llr_dump.m`
  - computes BER from one `tb_turbo_top_final_llrs.txt` dump

Typical usage from MATLAB:

```matlab
addpath("matlab");
run("matlab/run_turbo_ber_demo.m");
run("matlab/run_turbo_ber_k3200_heavy.m");
run("matlab/run_turbo_ber_k6144_heavy.m");
run("matlab/run_compare_model_vs_rtl_k3200.m");
run("matlab/run_compare_model_vs_rtl_k6144.m");
```

Custom sweep example:

```matlab
addpath("matlab");
cfg = struct();
cfg.k = 3200;
cfg.snrDbList = 0:0.25:2.5;
cfg.nHalfIter = 11;
cfg.numFrames = 80;
cfg.maxBitErrors = 1500;
cfg.maxFrameErrors = 60;
cfg.decoderMode = "rtl_fixed";
cfg.llrScale = 2.0;
cfg.extrinsicScale = 11/16;
results = lte_turbo_ber_sweep(cfg);
plot_lte_turbo_results(results, "matlab/results/ber_k3200.png");
```

Notes:
- The hard-decision rule matches the repo convention: decoded bit is `1` if posterior LLR `> 0`, else `0`.
- `decoderMode = "floating"` uses a straight max-log-MAP reference model.
- `decoderMode = "ideal_logmap"` uses a floating-point log-MAP / BCJR-style model and is the closest MATLAB approximation here to the paper’s ideal reference curve.
- `decoderMode = "rtl_fixed"` mimics the current fixed-point RTL assumptions:
  `5`-bit channel LLR, `6`-bit extrinsic, `7`-bit posterior, `10`-bit state metrics, modulo-normalized metric arithmetic, radix-4 pair processing, and `30`-step windows.
- The fixed model matches the active segmented/windowed RTL assumptions, but it is still an algorithmic model, not a cycle-accurate reproduction of the full top-level FSM.
- Default BER ranges are chosen to be practical for LTE-like turbo waterfall curves. Increase frame count for smoother curves.
