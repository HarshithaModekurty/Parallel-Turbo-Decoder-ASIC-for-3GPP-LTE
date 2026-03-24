#!/usr/bin/env python3
"""Run full LTE-like vector generation + RTL simulation + comparison pipeline."""

from __future__ import annotations

import argparse
import shutil
import subprocess
from pathlib import Path


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


def run_capture_split(cmd: list[str], cwd: Path, out_file: Path, err_file: Path) -> None:
    print("+", " ".join(cmd), ">", out_file, "2>", err_file)
    out_file.parent.mkdir(parents=True, exist_ok=True)
    err_file.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(cmd, cwd=cwd, check=False, text=True, capture_output=True)
    out_file.write_text(proc.stdout or "", encoding="ascii", errors="ignore")
    err_file.write_text(proc.stderr or "", encoding="ascii", errors="ignore")
    if proc.returncode != 0:
        raise subprocess.CalledProcessError(proc.returncode, cmd, output=proc.stdout, stderr=proc.stderr)


def archive_file(src: Path, dst: Path) -> None:
    if not src.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(src, dst)


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


def main() -> None:
    ap = argparse.ArgumentParser(description="Run full LTE-like turbo pipeline")
    ap.add_argument("--k", type=int, default=40)
    ap.add_argument("--n-half-iter", type=int, default=11)
    ap.add_argument("--n-iter", type=int, default=None, help="Deprecated alias; converted to 2*n_iter")
    ap.add_argument("--snr-db", type=float, default=1.5)
    ap.add_argument("--llr-scale", type=float, default=2.0)
    ap.add_argument("--seed", type=int, default=12345)
    args = ap.parse_args()
    if args.n_iter is not None:
        args.n_half_iter = args.n_iter * 2

    root = Path(__file__).resolve().parents[1]
    ghdl_exe = resolve_ghdl_exe()

    run(
        [
            "python",
            "tools/gen_lte_vectors.py",
            "--k",
            str(args.k),
            "--n-half-iter",
            str(args.n_half_iter),
            "--snr-db",
            str(args.snr_db),
            "--llr-scale",
            str(args.llr_scale),
            "--seed",
            str(args.seed),
        ],
        root,
    )

    run([ghdl_exe, "--remove"], root)

    analyze_files = [
        "rtl/turbo_pkg.vhd",
        "rtl/folded_llr_ram.vhd",
        "rtl/multiport_row_bram.vhd",
        "rtl/qpp_parallel_scheduler.vhd",
        "rtl/batcher_master.vhd",
        "rtl/batcher_slave.vhd",
        "rtl/turbo_iteration_ctrl.vhd",
        "rtl/batcher_router.vhd",
        "rtl/siso_maxlogmap.vhd",
        "rtl/turbo_decoder_top.vhd",
        "tb/tb_qpp_parallel_scheduler.vhd",
        "tb/tb_batcher_router.vhd",
        "tb/tb_folded_llr_ram.vhd",
        "tb/tb_siso_smoke.vhd",
        "tb/tb_siso_windowed_compare.vhd",
        "tb/tb_siso_vector_compare.vhd",
        "tb/tb_turbo_top.vhd",
    ]
    for file_name in analyze_files:
        run([ghdl_exe, "-a", "--std=08", file_name], root)

    tb_names = [
        "tb_qpp_parallel_scheduler",
        "tb_batcher_router",
        "tb_folded_llr_ram",
        "tb_siso_smoke",
        "tb_siso_windowed_compare",
        "tb_siso_vector_compare",
        "tb_turbo_top",
    ]
    for tb_name in tb_names:
        run([ghdl_exe, "-e", "--std=08", tb_name], root)
        run_capture([ghdl_exe, "-r", "--std=08", tb_name, "--assert-level=error"], root, root / f"sim_logs/{tb_name}.log")

    run(["python", "tools/compare_rtl_reference.py"], root)
    run_capture_split(
        [ghdl_exe, "--synth", "--std=08", "turbo_decoder_top"],
        root,
        root / "synth_check.log",
        root / "synth_stderr.log",
    )

    archive_file(root / "sim_vectors/rtl_vs_reference_report.txt", root / f"sim_vectors/rtl_vs_reference_report_k{args.k}.txt")
    archive_file(root / "tb_turbo_top_report.txt", root / f"sim_vectors/tb_turbo_top_report_k{args.k}.txt")
    archive_file(root / "sim_logs/tb_turbo_top.log", root / f"sim_logs/tb_turbo_top_k{args.k}.log")

    print("Pipeline completed.")


if __name__ == "__main__":
    main()
