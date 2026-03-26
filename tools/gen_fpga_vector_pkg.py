#!/usr/bin/env python3
"""Generate a VHDL package with fixed test vectors for FPGA smoke testing."""

from __future__ import annotations

import argparse
from pathlib import Path


def parse_vector_file(path: Path) -> tuple[int, int, int, int, list[tuple[int, int, int, int, int, int]]]:
    rows: list[tuple[int, int, int, int, int, int]] = []
    lines = [line.strip() for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    if not lines:
        raise ValueError(f"Vector file is empty: {path}")

    header = lines[0].split()
    if len(header) < 4:
        raise ValueError(f"Malformed vector header in {path}: {lines[0]}")

    k = int(header[0])
    n_half_iter = int(header[1])
    f1 = int(header[2])
    f2 = int(header[3])

    for raw in lines[1:]:
        parts = raw.split()
        if len(parts) < 6:
            raise ValueError(f"Malformed vector row in {path}: {raw}")
        idx = int(parts[0])
        bit_orig = int(parts[1])
        bit_int = int(parts[2])
        l_sys = int(parts[3])
        l_par1 = int(parts[4])
        l_par2 = int(parts[5])
        rows.append((idx, bit_orig, bit_int, l_sys, l_par1, l_par2))

    if len(rows) != k:
        raise ValueError(f"Vector file {path} has {len(rows)} rows, expected {k}")
    return k, n_half_iter, f1, f2, rows


def emit_signed_array(name: str, arr_type_name: str, elem_type_name: str, rows: list[tuple[int, int, int, int, int, int]], field_idx: int) -> str:
    body = ",\n".join(
        f"    {idx} => to_signed({row[field_idx]}, {elem_type_name}'length)"
        for idx, row in enumerate(rows)
    )
    return (
        f"  constant {name} : {arr_type_name}(0 to C_FPGA_VEC_K-1) := (\n"
        f"{body}\n"
        f"  );\n"
    )


def emit_bit_array(name: str, rows: list[tuple[int, int, int, int, int, int]], field_idx: int) -> str:
    body = ",\n".join(
        f"    {idx} => '{'1' if row[field_idx] else '0'}'"
        for idx, row in enumerate(rows)
    )
    return (
        f"  constant {name} : bit_vec_t(0 to C_FPGA_VEC_K-1) := (\n"
        f"{body}\n"
        f"  );\n"
    )


def build_package(pkg_name: str, k: int, n_half_iter: int, f1: int, f2: int, rows: list[tuple[int, int, int, int, int, int]]) -> str:
    return f"""library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.turbo_pkg.all;

package {pkg_name} is
  type bit_vec_t is array (natural range <>) of std_logic;
  type chan_arr_t is array (natural range <>) of chan_llr_t;
  constant C_FPGA_VEC_K : natural := {k};
  constant C_FPGA_VEC_HALF_ITER : natural := {n_half_iter};
  constant C_FPGA_VEC_F1 : natural := {f1};
  constant C_FPGA_VEC_F2 : natural := {f2};
{emit_bit_array("C_FPGA_BIT_ORIG", rows, 1)}{emit_bit_array("C_FPGA_BIT_INT", rows, 2)}{emit_signed_array("C_FPGA_L_SYS", "chan_arr_t", "chan_llr_t", rows, 3)}{emit_signed_array("C_FPGA_L_PAR1", "chan_arr_t", "chan_llr_t", rows, 4)}{emit_signed_array("C_FPGA_L_PAR2", "chan_arr_t", "chan_llr_t", rows, 5)}end package;
"""


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate a VHDL package from an RTL vector file")
    ap.add_argument("--vec-file", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--package-name", default="fpga_smoke_vectors_pkg")
    args = ap.parse_args()

    k, n_half_iter, f1, f2, rows = parse_vector_file(args.vec_file)
    text = build_package(args.package_name, k, n_half_iter, f1, f2, rows)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(text, encoding="ascii")
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
