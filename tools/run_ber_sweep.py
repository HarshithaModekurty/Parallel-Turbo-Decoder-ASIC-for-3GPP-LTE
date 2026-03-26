#!/usr/bin/env python3
"""Run BER sweeps for tb_turbo_top over multiple K and SNR points."""

from __future__ import annotations

import argparse
import csv
import shutil
import subprocess
from pathlib import Path

from compute_ber_from_llr_dump import compute_ber_from_files


ANALYZE_FILES = [
    "rtl/turbo_pkg.vhd",
    "rtl/folded_llr_ram.vhd",
    "rtl/simple_dp_bram.vhd",
    "rtl/multiport_row_bram.vhd",
    "rtl/qpp_parallel_scheduler.vhd",
    "rtl/batcher_master.vhd",
    "rtl/batcher_slave.vhd",
    "rtl/turbo_iteration_ctrl.vhd",
    "rtl/batcher_router.vhd",
    "rtl/siso_maxlogmap.vhd",
    "rtl/turbo_decoder_top.vhd",
    "tb/tb_turbo_top.vhd",
]


def run(cmd: list[str], cwd: Path) -> None:
    print("+", " ".join(cmd))
    subprocess.run(cmd, cwd=cwd, check=True)


def run_capture(cmd: list[str], cwd: Path, out_file: Path) -> None:
    print("+", " ".join(cmd), ">", out_file)
    out_file.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(cmd, cwd=cwd, check=False, text=True, capture_output=True)
    out_file.write_text((proc.stdout or "") + (proc.stderr or ""), encoding="ascii", errors="ignore")
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd, output=proc.stdout, stderr=proc.stderr)


def resolve_ghdl_exe() -> str:
    ghdl_exe = shutil.which("ghdl")
    if ghdl_exe is not None:
        return ghdl_exe

    candidate = (
        Path.home()
        / "AppData"
        / "Local"
        / "Microsoft"
        / "WinGet"
        / "Packages"
        / "ghdl.ghdl.ucrt64.mcode_Microsoft.Winget.Source_8wekyb3d8bbwe"
        / "bin"
        / "ghdl.exe"
    )
    try:
        if candidate.exists():
            return str(candidate)
    except PermissionError:
        return str(candidate)

    raise SystemExit("Could not find ghdl executable. Install ghdl or add it to PATH.")


def parse_k_list(raw: str) -> list[int]:
    out = []
    for part in raw.split(","):
        part = part.strip()
        if part:
            out.append(int(part))
    if not out:
        raise ValueError("k-list must not be empty")
    return out


def snr_points(start: float, stop: float, step: float) -> list[float]:
    vals = []
    cur = start
    while cur <= stop + 1.0e-12:
        vals.append(round(cur, 10))
        cur += step
    return vals


def snr_tag(snr_db: float) -> str:
    return f"snr{snr_db:.1f}".replace("-", "m").replace(".", "p")


def frame_tag(frame_idx: int) -> str:
    return f"frame{frame_idx:03d}"


def frame_seed(base_seed: int, k: int, snr_db: float, frame_idx: int) -> int:
    return base_seed + (k * 1000) + int(round(snr_db * 10.0)) * 100000 + frame_idx


def write_case_report(
    out_file: Path,
    *,
    k: int,
    snr_db: float,
    frames_run: int,
    bit_errors: int,
    total_bits: int,
    frame_errors: int,
    valid_outputs: int,
    missing_outputs: int,
    malformed_llr_lines: int,
) -> None:
    ber_total = bit_errors / total_bits if total_bits > 0 else 0.0
    ber_with_missing = (bit_errors + missing_outputs) / total_bits if total_bits > 0 else 0.0
    fer = frame_errors / frames_run if frames_run > 0 else 0.0
    out_file.write_text(
        "\n".join(
            [
                "BER Sweep Aggregate Summary",
                f"k={k}",
                f"snr_db={snr_db:.4f}",
                f"frames_run={frames_run}",
                f"bit_errors={bit_errors}",
                f"total_bits={total_bits}",
                f"frame_errors={frame_errors}",
                f"fer={fer:.12f}",
                f"valid_outputs={valid_outputs}",
                f"missing_outputs={missing_outputs}",
                f"malformed_llr_lines={malformed_llr_lines}",
                f"ber_total={ber_total:.12f}",
                f"ber_with_missing_as_errors={ber_with_missing:.12f}",
                "",
            ]
        ),
        encoding="ascii",
    )


def build_tb(ghdl_exe: str, root: Path) -> None:
    run([ghdl_exe, "--remove"], root)
    for file_name in ANALYZE_FILES:
        run([ghdl_exe, "-a", "--std=08", file_name], root)
    run([ghdl_exe, "-e", "--std=08", "tb_turbo_top"], root)


def load_frame_rows(path: Path) -> list[dict[str, object]]:
    with path.open("r", encoding="ascii", newline="") as fh:
        reader = csv.DictReader(fh)
        rows: list[dict[str, object]] = []
        for row in reader:
            rows.append(
                {
                    "frame_idx": int(row["frame_idx"]),
                    "seed": int(row["seed"]),
                    "bit_errors": int(row["bit_errors"]),
                    "total_bits": int(row["total_bits"]),
                    "ber_total": row["ber_total"],
                    "valid_outputs": int(row["valid_outputs"]),
                    "missing_outputs": int(row["missing_outputs"]),
                    "malformed_llr_lines": int(row["malformed_llr_lines"]),
                    "case_dir": row["case_dir"],
                }
            )
    return rows


def aggregate_frame_rows(frame_rows: list[dict[str, object]]) -> dict[str, int]:
    bit_errors = sum(int(row["bit_errors"]) for row in frame_rows)
    total_bits = sum(int(row["total_bits"]) for row in frame_rows)
    frame_errors = sum(1 for row in frame_rows if int(row["bit_errors"]) > 0)
    valid_outputs = sum(int(row["valid_outputs"]) for row in frame_rows)
    missing_outputs = sum(int(row["missing_outputs"]) for row in frame_rows)
    malformed_llr_lines = sum(int(row["malformed_llr_lines"]) for row in frame_rows)
    return {
        "bit_errors": bit_errors,
        "total_bits": total_bits,
        "frame_errors": frame_errors,
        "valid_outputs": valid_outputs,
        "missing_outputs": missing_outputs,
        "malformed_llr_lines": malformed_llr_lines,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Run BER sweep using tb_turbo_top final-LLR dumps")
    ap.add_argument("--k-list", default="3200,6144", help="Comma-separated block lengths")
    ap.add_argument("--snr-start", type=float, default=0.0)
    ap.add_argument("--snr-stop", type=float, default=2.5)
    ap.add_argument("--snr-step", type=float, default=0.5)
    ap.add_argument("--n-half-iter", type=int, default=11)
    ap.add_argument("--llr-scale", type=float, default=2.0)
    ap.add_argument("--seed", type=int, default=12345)
    ap.add_argument("--frames-per-snr", type=int, default=8, help="Number of randomized frames per SNR point")
    ap.add_argument("--resume", action="store_true", help="Reuse completed case frame_summary.csv files when present")
    ap.add_argument("--outdir", type=Path, default=Path("sim_vectors/ber_sweep"))
    args = ap.parse_args()

    root = Path(__file__).resolve().parents[1]
    ghdl_exe = resolve_ghdl_exe()
    ks = parse_k_list(args.k_list)
    snrs = snr_points(args.snr_start, args.snr_stop, args.snr_step)

    build_tb(ghdl_exe, root)

    rows: list[dict[str, object]] = []
    for k in ks:
        for snr_db in snrs:
            case_dir = args.outdir / f"k{k}" / snr_tag(snr_db)
            case_dir.mkdir(parents=True, exist_ok=True)

            frame_rows: list[dict[str, object]] = []
            frame_csv = root / case_dir / "frame_summary.csv"
            if args.resume and frame_csv.exists():
                frame_rows = load_frame_rows(frame_csv)
                if len(frame_rows) == args.frames_per_snr:
                    print(f"Reusing existing case {case_dir.as_posix()} with {len(frame_rows)} frames")
                else:
                    frame_rows = []

            if not frame_rows:
                for frame_idx in range(args.frames_per_snr):
                    frame_dir = case_dir / frame_tag(frame_idx)
                    frame_dir.mkdir(parents=True, exist_ok=True)

                    vec_rel = frame_dir / "lte_frame_input_vectors.txt"
                    report_rel = frame_dir / "tb_turbo_top_report.txt"
                    llr_rel = frame_dir / "tb_turbo_top_final_llrs.txt"
                    trace_rel = frame_dir / "tb_turbo_top_io_trace.txt"
                    ber_rel = frame_dir / "ber_report.txt"
                    log_rel = frame_dir / "tb_turbo_top.log"
                    seed_i = frame_seed(args.seed, k, snr_db, frame_idx)

                    run(
                        [
                            "python",
                            "tools/gen_lte_vectors.py",
                            "--k",
                            str(k),
                            "--n-half-iter",
                            str(args.n_half_iter),
                            "--snr-db",
                            str(snr_db),
                            "--llr-scale",
                            str(args.llr_scale),
                            "--seed",
                            str(seed_i),
                            "--outdir",
                            str(frame_dir),
                        ],
                        root,
                    )

                    run_capture(
                        [
                            ghdl_exe,
                            "-r",
                            "--std=08",
                            "tb_turbo_top",
                            "--assert-level=error",
                            f"-gG_VEC_PATH={vec_rel.as_posix()}",
                            f"-gG_IO_TRACE_PATH={trace_rel.as_posix()}",
                            f"-gG_REPORT_PATH={report_rel.as_posix()}",
                            f"-gG_FINAL_LLR_PATH={llr_rel.as_posix()}",
                        ],
                        root,
                        root / log_rel,
                    )

                    summary, _, malformed = compute_ber_from_files(root / vec_rel, root / llr_rel)
                    (root / ber_rel).write_text(
                        "\n".join(
                            [
                                "BER Sweep Frame Summary",
                                f"k={k}",
                                f"snr_db={snr_db:.4f}",
                                f"frame_idx={frame_idx}",
                                f"seed={seed_i}",
                                f"vector_file={vec_rel.as_posix()}",
                                f"llr_file={llr_rel.as_posix()}",
                                f"valid_outputs={summary.valid_outputs}",
                                f"missing_outputs={summary.missing_outputs}",
                                f"malformed_llr_lines={malformed}",
                                f"bit_errors={summary.bit_errors}",
                                f"ber_total={summary.ber_total:.12f}",
                                f"ber_seen_only={summary.ber_seen_only:.12f}",
                                f"ber_with_missing_as_errors={summary.ber_with_missing_as_errors:.12f}",
                                "",
                            ]
                        ),
                        encoding="ascii",
                    )

                    frame_rows.append(
                        {
                            "frame_idx": frame_idx,
                            "seed": seed_i,
                            "bit_errors": summary.bit_errors,
                            "total_bits": summary.k,
                            "ber_total": f"{summary.ber_total:.12f}",
                            "valid_outputs": summary.valid_outputs,
                            "missing_outputs": summary.missing_outputs,
                            "malformed_llr_lines": malformed,
                            "case_dir": frame_dir.as_posix(),
                        }
                    )

                with frame_csv.open("w", encoding="ascii", newline="") as fh:
                    writer = csv.DictWriter(
                        fh,
                        fieldnames=[
                            "frame_idx",
                            "seed",
                            "bit_errors",
                            "total_bits",
                            "ber_total",
                            "valid_outputs",
                            "missing_outputs",
                            "malformed_llr_lines",
                            "case_dir",
                        ],
                    )
                    writer.writeheader()
                    writer.writerows(frame_rows)

            agg = aggregate_frame_rows(frame_rows)
            agg_bit_errors = agg["bit_errors"]
            agg_total_bits = agg["total_bits"]
            agg_frame_errors = agg["frame_errors"]
            agg_valid_outputs = agg["valid_outputs"]
            agg_missing_outputs = agg["missing_outputs"]
            agg_malformed = agg["malformed_llr_lines"]

            write_case_report(
                root / case_dir / "ber_report.txt",
                k=k,
                snr_db=snr_db,
                frames_run=args.frames_per_snr,
                bit_errors=agg_bit_errors,
                total_bits=agg_total_bits,
                frame_errors=agg_frame_errors,
                valid_outputs=agg_valid_outputs,
                missing_outputs=agg_missing_outputs,
                malformed_llr_lines=agg_malformed,
            )

            ber_total = agg_bit_errors / agg_total_bits if agg_total_bits > 0 else 0.0
            ber_with_missing = (agg_bit_errors + agg_missing_outputs) / agg_total_bits if agg_total_bits > 0 else 0.0
            fer = agg_frame_errors / args.frames_per_snr if args.frames_per_snr > 0 else 0.0

            row = {
                "k": k,
                "snr_db": f"{snr_db:.1f}",
                "frames_run": args.frames_per_snr,
                "frame_errors": agg_frame_errors,
                "fer": f"{fer:.12f}",
                "bit_errors": agg_bit_errors,
                "total_bits": agg_total_bits,
                "ber_total": f"{ber_total:.12f}",
                "ber_with_missing_as_errors": f"{ber_with_missing:.12f}",
                "valid_outputs": agg_valid_outputs,
                "missing_outputs": agg_missing_outputs,
                "malformed_llr_lines": agg_malformed,
                "case_dir": case_dir.as_posix(),
            }
            rows.append(row)
            print(
                f"k={k} snr_db={snr_db:.1f} frames={args.frames_per_snr} "
                f"bit_errors={agg_bit_errors}/{agg_total_bits} frame_errors={agg_frame_errors} "
                f"ber={ber_total:.12f} fer={fer:.12f} "
                f"valid={agg_valid_outputs} missing={agg_missing_outputs}"
            )

    summary_csv = root / args.outdir / "ber_sweep_summary.csv"
    summary_csv.parent.mkdir(parents=True, exist_ok=True)
    with summary_csv.open("w", encoding="ascii", newline="") as fh:
        writer = csv.DictWriter(
            fh,
            fieldnames=[
                "k",
                "snr_db",
                "frames_run",
                "frame_errors",
                "fer",
                "bit_errors",
                "total_bits",
                "ber_total",
                "ber_with_missing_as_errors",
                "valid_outputs",
                "missing_outputs",
                "malformed_llr_lines",
                "case_dir",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)

    print(f"Wrote {summary_csv}")


if __name__ == "__main__":
    main()
