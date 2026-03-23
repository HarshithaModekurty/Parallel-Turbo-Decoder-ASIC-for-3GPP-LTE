#!/usr/bin/env python3
"""Compute BER from tb_turbo_top final-LLR dump files."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class BerSummary:
    k: int
    valid_outputs: int
    missing_outputs: int
    bit_errors: int
    ber_total: float
    ber_seen_only: float
    ber_with_missing_as_errors: float
    hard_one_count: int


@dataclass(frozen=True)
class BerDetail:
    idx: int
    bit_orig: int
    final_llr: int
    seen: int
    hard: int
    match: bool


def parse_vector_bits(path: Path) -> tuple[int, dict[int, int]]:
    lines = [line.strip() for line in path.read_text(encoding="ascii").splitlines() if line.strip()]
    if not lines:
        raise ValueError(f"Vector file is empty: {path}")

    header = lines[0].split()
    if len(header) < 1:
        raise ValueError(f"Malformed vector header in {path}")
    k = int(header[0])

    bits: dict[int, int] = {}
    for raw in lines[1:]:
        if raw.startswith("#"):
            continue
        parts = raw.split()
        if len(parts) < 2:
            raise ValueError(f"Malformed vector line in {path}: {raw}")
        idx = int(parts[0])
        bit_orig = int(parts[1])
        bits[idx] = bit_orig

    if len(bits) < k:
        raise ValueError(f"Vector file {path} has only {len(bits)} symbols, expected {k}")
    return k, bits


def parse_final_llr_dump(path: Path) -> tuple[dict[int, tuple[int, int]], int]:
    llrs: dict[int, tuple[int, int]] = {}
    malformed = 0
    for raw in path.read_text(encoding="ascii").splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 3:
            malformed += 1
            continue
        idx = int(parts[0])
        llr = int(parts[1])
        seen = int(parts[2])
        llrs[idx] = (llr, seen)
    return llrs, malformed


def hard_decision_from_llr(llr: int) -> int:
    return 1 if llr > 0 else 0


def compute_ber_from_files(vec_file: Path, llr_file: Path) -> tuple[BerSummary, list[BerDetail], int]:
    k, bits = parse_vector_bits(vec_file)
    llrs, malformed = parse_final_llr_dump(llr_file)

    details: list[BerDetail] = []
    valid_outputs = 0
    missing_outputs = 0
    bit_errors = 0
    hard_one_count = 0

    for idx in range(k):
        bit_orig = bits[idx]
        llr, seen = llrs.get(idx, (0, 0))
        hard = hard_decision_from_llr(llr)
        match = (hard == bit_orig) if seen == 1 else False

        if seen == 1:
            valid_outputs += 1
            hard_one_count += hard
            if not match:
                bit_errors += 1
        else:
            missing_outputs += 1

        details.append(
            BerDetail(
                idx=idx,
                bit_orig=bit_orig,
                final_llr=llr,
                seen=seen,
                hard=hard,
                match=match,
            )
        )

    seen_den = valid_outputs if valid_outputs > 0 else 1
    summary = BerSummary(
        k=k,
        valid_outputs=valid_outputs,
        missing_outputs=missing_outputs,
        bit_errors=bit_errors,
        ber_total=bit_errors / k,
        ber_seen_only=bit_errors / seen_den,
        ber_with_missing_as_errors=(bit_errors + missing_outputs) / k,
        hard_one_count=hard_one_count,
    )
    return summary, details, malformed


def format_report(
    vec_file: Path,
    llr_file: Path,
    summary: BerSummary,
    details: list[BerDetail],
    malformed_lines: int,
) -> str:
    lines = [
        "BER Report From Final LLR Dump",
        f"vector_file={vec_file}",
        f"llr_file={llr_file}",
        "hard_decision_rule=bit_1_if_llr_gt_0_else_0",
        f"total_bits={summary.k}",
        f"valid_outputs={summary.valid_outputs}",
        f"missing_outputs={summary.missing_outputs}",
        f"malformed_llr_lines={malformed_lines}",
        f"bit_errors={summary.bit_errors}",
        f"ber_total={summary.ber_total:.12f}",
        f"ber_seen_only={summary.ber_seen_only:.12f}",
        f"ber_with_missing_as_errors={summary.ber_with_missing_as_errors:.12f}",
        f"hard_one_count={summary.hard_one_count}",
        "",
        "idx bit_orig final_llr seen hard match",
    ]
    for item in details:
        lines.append(
            f"{item.idx} {item.bit_orig} {item.final_llr} {item.seen} {item.hard} {'OK' if item.match else 'ERR'}"
        )
    return "\n".join(lines) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser(description="Compute BER from tb_turbo_top final-LLR dump")
    ap.add_argument("--vec-file", type=Path, default=Path("sim_vectors/lte_frame_input_vectors.txt"))
    ap.add_argument("--llr-file", type=Path, default=Path("tb_turbo_top_final_llrs.txt"))
    ap.add_argument("--out", type=Path, default=Path("sim_vectors/ber_report.txt"))
    args = ap.parse_args()

    summary, details, malformed = compute_ber_from_files(args.vec_file, args.llr_file)
    report_text = format_report(args.vec_file, args.llr_file, summary, details, malformed)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(report_text, encoding="ascii")

    print(f"Wrote {args.out}")
    print(
        f"BER total={summary.ber_total:.12f} bit_errors={summary.bit_errors}/{summary.k} "
        f"valid_outputs={summary.valid_outputs} missing_outputs={summary.missing_outputs}"
    )


if __name__ == "__main__":
    main()
