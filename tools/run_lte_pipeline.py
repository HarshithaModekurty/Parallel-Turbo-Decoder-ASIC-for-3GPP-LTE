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
    p = subprocess.run(cmd, cwd=cwd, check=False, text=True, capture_output=True)
    out_file.write_text((p.stdout or "") + (p.stderr or ""), encoding="ascii", errors="ignore")
    if p.returncode != 0:
      raise subprocess.CalledProcessError(p.returncode, cmd, output=p.stdout, stderr=p.stderr)


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

    ghdl_exe = shutil.which("ghdl")
    if ghdl_exe is None:
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
      if candidate.exists():
          ghdl_exe = str(candidate)
      else:
          raise SystemExit("Could not find ghdl executable. Install ghdl or add it to PATH.")

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
        "rtl/branch_metric_unit.vhd",
        "rtl/qpp_interleaver.vhd",
        "rtl/llr_ram.vhd",
        "rtl/folded_llr_ram.vhd",
        "rtl/qpp_parallel_scheduler.vhd",
        "rtl/batcher_master.vhd",
        "rtl/batcher_slave.vhd",
        "rtl/radix4_bmu.vhd",
        "rtl/radix4_acs.vhd",
        "rtl/radix4_extractor.vhd",
        "rtl/turbo_iteration_ctrl.vhd",
        "rtl/batcher_router.vhd",
        "rtl/siso_maxlogmap.vhd",
        "rtl/turbo_decoder_top.vhd",
        "tb/tb_qpp_interleaver.vhd",
        "tb/tb_qpp_parallel_scheduler.vhd",
        "tb/tb_batcher_router.vhd",
        "tb/tb_folded_llr_ram.vhd",
        "tb/tb_radix4_acs.vhd",
        "tb/tb_radix4_extractor.vhd",
        "tb/tb_siso_smoke.vhd",
        "tb/tb_turbo_top.vhd",
    ]
    for f in analyze_files:
        run([ghdl_exe, "-a", "--std=08", f], root)

    run([ghdl_exe, "-e", "--std=08", "tb_qpp_interleaver"], root)
    run([ghdl_exe, "-e", "--std=08", "tb_qpp_parallel_scheduler"], root)
    run([ghdl_exe, "-e", "--std=08", "tb_batcher_router"], root)
    run([ghdl_exe, "-e", "--std=08", "tb_folded_llr_ram"], root)
    run([ghdl_exe, "-e", "--std=08", "tb_radix4_acs"], root)
    run([ghdl_exe, "-e", "--std=08", "tb_radix4_extractor"], root)
    run([ghdl_exe, "-e", "--std=08", "tb_siso_smoke"], root)
    run([ghdl_exe, "-e", "--std=08", "tb_turbo_top"], root)

    run_capture([ghdl_exe, "-r", "--std=08", "tb_qpp_interleaver"], root, root / "sim_logs/tb_qpp_interleaver.log")
    run_capture([ghdl_exe, "-r", "--std=08", "tb_qpp_parallel_scheduler"], root, root / "sim_logs/tb_qpp_parallel_scheduler.log")
    run_capture([ghdl_exe, "-r", "--std=08", "tb_batcher_router"], root, root / "sim_logs/tb_batcher_router.log")
    run_capture([ghdl_exe, "-r", "--std=08", "tb_folded_llr_ram"], root, root / "sim_logs/tb_folded_llr_ram.log")
    run_capture([ghdl_exe, "-r", "--std=08", "tb_radix4_acs"], root, root / "sim_logs/tb_radix4_acs.log")
    run_capture([ghdl_exe, "-r", "--std=08", "tb_radix4_extractor"], root, root / "sim_logs/tb_radix4_extractor.log")
    run_capture([ghdl_exe, "-r", "--std=08", "tb_siso_smoke"], root, root / "sim_logs/tb_siso_smoke.log")
    run_capture([ghdl_exe, "-r", "--std=08", "tb_turbo_top"], root, root / "sim_logs/tb_turbo_top.log")

    run(["python", "tools/compare_rtl_reference.py"], root)

    print("Pipeline completed.")


if __name__ == "__main__":
    main()
