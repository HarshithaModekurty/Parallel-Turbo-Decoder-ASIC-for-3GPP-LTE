#!/usr/bin/env python3
"""Compare RTL turbo decoder outputs against floating reference (interleaved domain)."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_reference(path: Path) -> dict[int, tuple[int, float, int]]:
    ref = {}
    for raw in path.read_text(encoding="ascii").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        idx = int(parts[0])
        bit = int(parts[1])
        llr = float(parts[2])
        hard = int(parts[3])
        ref[idx] = (bit, llr, hard)
    return ref


def parse_rtl_trace(path: Path) -> dict[int, tuple[int, int, int]]:
    # idx -> (pass, llr, hard) using last pass seen
    out = {}
    for raw in path.read_text(encoding="ascii").splitlines():
        line = raw.strip()
        if not line.startswith("OUT "):
            continue
        p = line.split()
        # OUT seq idx pass bit_int bit_orig_pi l_sys l_par1 l_par2 l_post hard
        idx = int(p[2])
        pas = int(p[3])
        llr = int(p[9])
        hard = int(p[10])
        prev = out.get(idx)
        if prev is None or pas >= prev[0]:
            out[idx] = (pas, llr, hard)
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description="Compare RTL outputs with reference")
    ap.add_argument("--rtl-trace", type=Path, default=Path("tb_turbo_top_io_trace.txt"))
    ap.add_argument("--reference", type=Path, default=Path("sim_vectors/reference_interleaved.txt"))
    ap.add_argument("--out", type=Path, default=Path("sim_vectors/rtl_vs_reference_report.txt"))
    args = ap.parse_args()

    ref = parse_reference(args.reference)
    rtl = parse_rtl_trace(args.rtl_trace)

    idxs = sorted(ref.keys())
    cov = 0
    hard_err = 0
    sign_mismatch = 0
    mae = 0.0
    lines = [
        "RTL vs Floating Reference (Interleaved Domain)",
        "idx bit_int ref_hard rtl_hard ref_llr rtl_llr sign_match",
    ]

    for idx in idxs:
        bit, ref_llr, ref_hard = ref[idx]
        if idx not in rtl:
            lines.append(f"{idx} {bit} {ref_hard} MISSING {ref_llr:.8f} MISSING ERR")
            continue
        cov += 1
        _, rtl_llr, rtl_hard = rtl[idx]
        sign_ok = (ref_llr < 0 and rtl_llr < 0) or (ref_llr >= 0 and rtl_llr >= 0)
        if not sign_ok:
            sign_mismatch += 1
        if rtl_hard != ref_hard:
            hard_err += 1
        mae += abs(rtl_llr - ref_llr)
        lines.append(
            f"{idx} {bit} {ref_hard} {rtl_hard} {ref_llr:.8f} {rtl_llr} {'OK' if sign_ok else 'ERR'}"
        )

    total = len(idxs)
    mae = mae / cov if cov else 0.0
    summary = [
        f"total_symbols={total}",
        f"rtl_coverage={cov}",
        f"hard_errors_vs_reference={hard_err}",
        f"sign_mismatch_vs_reference={sign_mismatch}",
        f"mean_abs_llr_delta={mae:.6f}",
    ]

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(summary + [""] + lines) + "\n", encoding="ascii")
    print("Wrote", args.out)


if __name__ == "__main__":
    main()
