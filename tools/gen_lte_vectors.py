#!/usr/bin/env python3
"""Generate LTE-like turbo encoder/channel vectors and a floating max-log reference."""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

NEG_INF = -1.0e30

# Subset table (full LTE table can be added later as needed).
LTE_QPP_TABLE = {
    40: (3, 10),
    48: (7, 12),
    56: (19, 42),
    64: (7, 16),
    72: (7, 18),
    80: (11, 20),
    88: (5, 22),
    96: (11, 24),
    104: (7, 26),
    112: (41, 84),
    120: (103, 90),
    128: (15, 32),
    136: (9, 34),
    144: (17, 108),
    152: (9, 38),
    160: (21, 120),
}


def rsc_step(state: int, u: int) -> tuple[int, int]:
    s0 = state & 1
    s1 = (state >> 1) & 1
    s2 = (state >> 2) & 1
    fb = u ^ s0 ^ s2
    parity = fb ^ s1 ^ s2
    next_state = (fb << 2) | (s2 << 1) | s1
    return next_state, parity


def tail_input_for_state(state: int) -> int:
    s0 = state & 1
    s2 = (state >> 2) & 1
    return s0 ^ s2


def rsc_encode(bits: list[int]) -> tuple[list[int], list[int], list[int], int]:
    state = 0
    parity = []
    for u in bits:
        state, p = rsc_step(state, u)
        parity.append(p)

    tail_u = []
    tail_p = []
    for _ in range(3):
        u = tail_input_for_state(state)
        state, p = rsc_step(state, u)
        tail_u.append(u)
        tail_p.append(p)

    if state != 0:
        raise RuntimeError("Termination failed: non-zero final state")

    return parity, tail_u, tail_p, state


def qpp_permutation(k: int, f1: int, f2: int) -> list[int]:
    return [(f1 * i + f2 * i * i) % k for i in range(k)]


def build_inverse_permutation(pi: list[int]) -> list[int]:
    inv = [0] * len(pi)
    for k, idx in enumerate(pi):
        inv[idx] = k
    return inv


def q_llr(v: float, scale: float) -> int:
    q = int(round(v * scale))
    if q > 127:
        return 127
    if q < -128:
        return -128
    return q


def channel_llr(bits: list[int], sigma2: float, rng: random.Random) -> list[float]:
    sigma = math.sqrt(sigma2)
    out = []
    for b in bits:
        x = 1.0 - 2.0 * b
        y = x + rng.gauss(0.0, sigma)
        out.append(2.0 * y / sigma2)
    return out


def precompute_trellis() -> tuple[list[list[int]], list[list[int]]]:
    ns = [[0, 0] for _ in range(8)]
    par = [[0, 0] for _ in range(8)]
    for s in range(8):
        for u in (0, 1):
            nst, p = rsc_step(s, u)
            ns[s][u] = nst
            par[s][u] = p
    return ns, par


NS, PAR = precompute_trellis()


def gamma(lsys: float, lpar: float, lapri: float, u: int, p: int) -> float:
    su = 1.0 if u == 0 else -1.0
    sp = 1.0 if p == 0 else -1.0
    return 0.5 * (su * (lsys + lapri) + sp * lpar)


def siso_maxlog(lsys: list[float], lpar: list[float], lapri: list[float]) -> tuple[list[float], list[float]]:
    k_len = len(lsys)
    alpha = [[NEG_INF] * 8 for _ in range(k_len + 1)]
    beta = [[NEG_INF] * 8 for _ in range(k_len + 1)]

    alpha[0][0] = 0.0
    for k in range(k_len):
        for ps in range(8):
            a = alpha[k][ps]
            if a <= NEG_INF / 2:
                continue
            for u in (0, 1):
                ns = NS[ps][u]
                p = PAR[ps][u]
                m = a + gamma(lsys[k], lpar[k], lapri[k], u, p)
                if m > alpha[k + 1][ns]:
                    alpha[k + 1][ns] = m
        mmax = max(alpha[k + 1])
        alpha[k + 1] = [v - mmax for v in alpha[k + 1]]

    beta[k_len][0] = 0.0
    for k in range(k_len - 1, -1, -1):
        for ps in range(8):
            bbest = NEG_INF
            for u in (0, 1):
                ns = NS[ps][u]
                p = PAR[ps][u]
                m = beta[k + 1][ns] + gamma(lsys[k], lpar[k], lapri[k], u, p)
                if m > bbest:
                    bbest = m
            beta[k][ps] = bbest
        mmax = max(beta[k])
        beta[k] = [v - mmax for v in beta[k]]

    ext = [0.0] * k_len
    post = [0.0] * k_len
    for k in range(k_len):
        max0 = NEG_INF
        max1 = NEG_INF
        for ps in range(8):
            a = alpha[k][ps]
            if a <= NEG_INF / 2:
                continue
            for u in (0, 1):
                ns = NS[ps][u]
                p = PAR[ps][u]
                m = a + gamma(lsys[k], lpar[k], lapri[k], u, p) + beta[k + 1][ns]
                if u == 0:
                    if m > max0:
                        max0 = m
                else:
                    if m > max1:
                        max1 = m
        post[k] = max1 - max0
        ext[k] = post[k] - lsys[k] - lapri[k]

    return ext, post


def turbo_decode_reference(
    lsys_orig: list[float],
    lpar1_orig: list[float],
    lpar2_int: list[float],
    pi: list[int],
    n_iter: int,
) -> dict[str, list[float] | list[int]]:
    k_len = len(lsys_orig)
    lsys_int = [lsys_orig[pi[k]] for k in range(k_len)]

    lapri1 = [0.0] * k_len
    lapri2_last = [0.0] * k_len
    ext2_int = [0.0] * k_len

    for _ in range(n_iter):
        ext1_orig, _ = siso_maxlog(lsys_orig, lpar1_orig, lapri1)
        lapri2 = [ext1_orig[pi[k]] for k in range(k_len)]
        ext2_int, _ = siso_maxlog(lsys_int, lpar2_int, lapri2)
        lapri2_last = lapri2

        lapri1 = [0.0] * k_len
        for k in range(k_len):
            lapri1[pi[k]] = ext2_int[k]

    post_int = [lsys_int[k] + lapri2_last[k] + ext2_int[k] for k in range(k_len)]
    hard_int = [1 if v < 0.0 else 0 for v in post_int]

    post_orig = [0.0] * k_len
    hard_orig = [0] * k_len
    for k in range(k_len):
        post_orig[pi[k]] = post_int[k]
        hard_orig[pi[k]] = hard_int[k]

    return {
        "post_int": post_int,
        "hard_int": hard_int,
        "post_orig": post_orig,
        "hard_orig": hard_orig,
    }


def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate LTE-like turbo vectors for RTL TB")
    ap.add_argument("--k", type=int, default=40, help="Information block length")
    ap.add_argument("--n-iter", type=int, default=2, help="Turbo decoder iterations")
    ap.add_argument("--snr-db", type=float, default=1.5, help="AWGN Es/N0 in dB")
    ap.add_argument("--llr-scale", type=float, default=8.0, help="Scale before int8 quantization")
    ap.add_argument("--seed", type=int, default=12345, help="Random seed")
    ap.add_argument("--f1", type=int, default=None, help="QPP f1 (override table)")
    ap.add_argument("--f2", type=int, default=None, help="QPP f2 (override table)")
    ap.add_argument("--outdir", type=Path, default=Path("sim_vectors"), help="Output directory")
    args = ap.parse_args()

    if args.f1 is None or args.f2 is None:
        if args.k not in LTE_QPP_TABLE:
            raise SystemExit(f"K={args.k} not in internal QPP table. Provide --f1 and --f2 explicitly.")
        f1, f2 = LTE_QPP_TABLE[args.k]
    else:
        f1, f2 = args.f1, args.f2

    rng = random.Random(args.seed)
    bits_orig = [rng.getrandbits(1) for _ in range(args.k)]
    pi = qpp_permutation(args.k, f1, f2)
    inv = build_inverse_permutation(pi)
    bits_int = [bits_orig[pi[k]] for k in range(args.k)]

    par1, tail_u1, tail_p1, _ = rsc_encode(bits_orig)
    par2, tail_u2, tail_p2, _ = rsc_encode(bits_int)

    snr_lin = 10.0 ** (args.snr_db / 10.0)
    sigma2 = 1.0 / (2.0 * snr_lin)

    lsys_f = channel_llr(bits_orig, sigma2, rng)
    lpar1_f = channel_llr(par1, sigma2, rng)
    lpar2_int_f = channel_llr(par2, sigma2, rng)

    lsys_q = [q_llr(v, args.llr_scale) for v in lsys_f]
    lpar1_q = [q_llr(v, args.llr_scale) for v in lpar1_f]
    lpar2_q = [q_llr(v, args.llr_scale) for v in lpar2_int_f]

    ref = turbo_decode_reference(lsys_f, lpar1_f, lpar2_int_f, pi, args.n_iter)

    vec_lines = [f"{args.k} {args.n_iter} {f1} {f2}"]
    for i in range(args.k):
        vec_lines.append(
            f"{i} {bits_orig[i]} {bits_int[i]} {lsys_q[i]} {lpar1_q[i]} {lpar2_q[i]}"
        )
    write_lines(args.outdir / "lte_frame_input_vectors.txt", vec_lines)

    ref_int_lines = ["# idx_int bit_int post_llr hard"]
    for i in range(args.k):
        post = ref["post_int"][i]
        hard = ref["hard_int"][i]
        ref_int_lines.append(f"{i} {bits_int[i]} {post:.8f} {hard}")
    write_lines(args.outdir / "reference_interleaved.txt", ref_int_lines)

    ref_orig_lines = ["# idx_orig bit_orig post_llr hard"]
    for i in range(args.k):
        post = ref["post_orig"][i]
        hard = ref["hard_orig"][i]
        ref_orig_lines.append(f"{i} {bits_orig[i]} {post:.8f} {hard}")
    write_lines(args.outdir / "reference_original.txt", ref_orig_lines)

    meta_lines = [
        "LTE-like Turbo Frame Generation Summary",
        f"K={args.k} n_iter={args.n_iter} f1={f1} f2={f2}",
        f"seed={args.seed} snr_db={args.snr_db:.4f} sigma2={sigma2:.8f} llr_scale={args.llr_scale:.4f}",
        f"tail_u1={''.join(str(b) for b in tail_u1)} tail_p1={''.join(str(b) for b in tail_p1)}",
        f"tail_u2={''.join(str(b) for b in tail_u2)} tail_p2={''.join(str(b) for b in tail_p2)}",
        "Outputs:",
        "- lte_frame_input_vectors.txt (consumed by tb_turbo_top)",
        "- reference_interleaved.txt (floating max-log reference, interleaved domain)",
        "- reference_original.txt (floating max-log reference, original domain)",
    ]
    write_lines(args.outdir / "lte_frame_generation_report.txt", meta_lines)

    print("Generated vectors and reference in", args.outdir)


if __name__ == "__main__":
    main()
