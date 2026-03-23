#!/usr/bin/env python3
"""Compare RTL turbo decoder outputs against fixed-point and floating references."""

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


def parse_rtl_trace(path: Path) -> tuple[dict[int, tuple[int, int, int]], int]:
    # idx -> (pass, llr, hard) using last pass seen
    out = {}
    malformed = 0
    for raw in path.read_text(encoding="ascii").splitlines():
        line = raw.strip()
        if not line.startswith("OUT "):
            continue
        p = line.split()
        # OUT seq idx_orig pi_inv bit_orig bit_int_at_pi_inv l_sys l_par1 l_par2 l_post hard
        if len(p) < 11:
            malformed += 1
            continue
        idx = int(p[2])
        llr = int(p[9])
        hard = int(p[10])
        out[idx] = (0, llr, hard)
    return out, malformed


def main() -> None:
    ap = argparse.ArgumentParser(description="Compare RTL outputs with reference")
    ap.add_argument("--rtl-trace", type=Path, default=Path("tb_turbo_top_io_trace.txt"))
    ap.add_argument("--reference", type=Path, default=Path("sim_vectors/reference_fixed_original.txt"))
    ap.add_argument("--floating-reference", type=Path, default=Path("sim_vectors/reference_original.txt"))
    ap.add_argument("--out", type=Path, default=Path("sim_vectors/rtl_vs_reference_report.txt"))
    args = ap.parse_args()

    ref = parse_reference(args.reference)
    rtl, malformed = parse_rtl_trace(args.rtl_trace)

    idxs = sorted(ref.keys())
    cov = 0
    hard_err = 0
    sign_mismatch = 0
    mae = 0.0
    lines = [
        "RTL vs Fixed-Point Reference (Original Domain)",
        "idx bit_orig ref_hard rtl_hard ref_llr rtl_llr sign_match",
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
        f"malformed_out_lines={malformed}",
        f"hard_errors_vs_reference={hard_err}",
        f"sign_mismatch_vs_reference={sign_mismatch}",
        f"mean_abs_llr_delta={mae:.6f}",
    ]

    if args.floating_reference.exists():
        ref_float = parse_reference(args.floating_reference)
        cov_f = 0
        hard_err_f = 0
        sign_mismatch_f = 0
        mae_f = 0.0
        for idx in idxs:
            if idx not in rtl or idx not in ref_float:
                continue
            _, ref_llr_f, ref_hard_f = ref_float[idx]
            _, rtl_llr, rtl_hard = rtl[idx]
            cov_f += 1
            if rtl_hard != ref_hard_f:
                hard_err_f += 1
            if ((ref_llr_f < 0) and (rtl_llr >= 0)) or ((ref_llr_f >= 0) and (rtl_llr < 0)):
                sign_mismatch_f += 1
            mae_f += abs(rtl_llr - ref_llr_f)
        mae_f = mae_f / cov_f if cov_f else 0.0
        summary.extend(
            [
                f"floating_coverage={cov_f}",
                f"hard_errors_vs_floating={hard_err_f}",
                f"sign_mismatch_vs_floating={sign_mismatch_f}",
                f"mean_abs_llr_delta_vs_floating={mae_f:.6f}",
            ]
        )

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(summary + [""] + lines) + "\n", encoding="ascii")
    print("Wrote", args.out)


if __name__ == "__main__":
    main()
