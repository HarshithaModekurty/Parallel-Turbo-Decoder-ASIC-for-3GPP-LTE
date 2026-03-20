#!/usr/bin/env python3
"""Generate LTE-like turbo encoder/channel vectors and reference outputs."""

from __future__ import annotations

import argparse
import math
import random
from pathlib import Path

from lte_qpp_table import LTE_QPP_TABLE

NEG_INF = -1.0e30
METRIC_INIT_NEG = -256


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
    if q > 15:
        return 15
    if q < -16:
        return -16
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


def turbo_decode_reference_half_iter(
    lsys_orig: list[float],
    lpar1_orig: list[float],
    lpar2_int: list[float],
    pi: list[int],
    n_half_iter: int,
) -> dict[str, list[float] | list[int]]:
    k_len = len(lsys_orig)
    lsys_int = [lsys_orig[pi[k]] for k in range(k_len)]

    lapri_orig = [0.0] * k_len
    lapri_int = [0.0] * k_len
    post_orig = [0.0] * k_len
    hard_orig = [0] * k_len
    post_int = [0.0] * k_len
    hard_int = [0] * k_len

    for half in range(n_half_iter):
        if (half % 2) == 0:
            ext1_orig, post1_orig = siso_maxlog(lsys_orig, lpar1_orig, lapri_orig)
            lapri_int = [ext1_orig[pi[k]] for k in range(k_len)]
            if half == n_half_iter - 1:
                post_orig = list(post1_orig)
                hard_orig = [1 if v < 0.0 else 0 for v in post_orig]
                post_int = [post_orig[pi[k]] for k in range(k_len)]
                hard_int = [hard_orig[pi[k]] for k in range(k_len)]
        else:
            ext2_int, post2_int = siso_maxlog(lsys_int, lpar2_int, lapri_int)
            lapri_orig = [0.0] * k_len
            for k in range(k_len):
                lapri_orig[pi[k]] = ext2_int[k]
            if half == n_half_iter - 1:
                post_int = list(post2_int)
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


def wrap_metric(v: int) -> int:
    return ((v + 512) & 0x3FF) - 512


def mod_add_i(a: int, b: int) -> int:
    return wrap_metric(a + b)


def mod_sub_i(a: int, b: int) -> int:
    return wrap_metric(a - b)


def mod_max_i(a: int, b: int) -> int:
    return a if mod_sub_i(a, b) >= 0 else b


def mod_max4_i(a: int, b: int, c: int, d: int) -> int:
    return mod_max_i(mod_max_i(a, b), mod_max_i(c, d))


def sat_ext_i(v: int) -> int:
    return max(-32, min(31, v))


def sat_post_i(v: int) -> int:
    return max(-64, min(63, v))


def scale_ext_i(v: int) -> int:
    return sat_ext_i((11 * v) >> 4)


def terminated_state_i() -> list[int]:
    return [0] + [METRIC_INIT_NEG] * 7


def branch_metric_unit_i(lsys: int, lpar: int, lapri: int) -> tuple[int, int, int, int]:
    tmp = mod_add_i(lsys, lapri)
    return (
        wrap_metric(mod_add_i(tmp, lpar) >> 1),
        wrap_metric(mod_add_i(tmp, -lpar) >> 1),
        wrap_metric(mod_add_i(mod_add_i(-lsys, -lapri), lpar) >> 1),
        wrap_metric(mod_add_i(mod_add_i(-lsys, -lapri), -lpar) >> 1),
    )


def radix4_bmu_i(sys_even: int, sys_odd: int, par_even: int, par_odd: int, apri_even: int, apri_odd: int) -> list[int]:
    g0 = branch_metric_unit_i(sys_even, par_even, apri_even)
    g1 = branch_metric_unit_i(sys_odd, par_odd, apri_odd)
    out = [0] * 16
    for u0 in (0, 1):
        for p0 in (0, 1):
            for u1 in (0, 1):
                for p1 in (0, 1):
                    idx = (u0 * 8) + (p0 * 4) + (u1 * 2) + p1
                    out[idx] = mod_add_i(g0[u0 * 2 + p0], g1[u1 * 2 + p1])
    return out


def build_radix4_trellis(is_backward: bool) -> list[list[tuple[int, int]]]:
    trellis: list[list[tuple[int, int]]] = [[] for _ in range(8)]
    for start_s in range(8):
        for u0 in (0, 1):
            for u1 in (0, 1):
                mid_s = NS[start_s][u0]
                nxt_s = NS[mid_s][u1]
                g_idx = radix4_gamma_index_i(start_s, u0, u1)
                if is_backward:
                    trellis[start_s].append((nxt_s, g_idx))
                else:
                    trellis[nxt_s].append((start_s, g_idx))
    return trellis


def radix4_gamma_index_i(cur_state: int, u0: int, u1: int) -> int:
    mid_s = NS[cur_state][u0]
    p0 = PAR[cur_state][u0]
    p1 = PAR[mid_s][u1]
    return (u0 * 8) + (p0 * 4) + (u1 * 2) + p1


FWD_TRELLIS_I = build_radix4_trellis(False)
BWD_TRELLIS_I = build_radix4_trellis(True)


def radix4_acs_i(state_in: list[int], gamma_in: list[int], mode_bwd: bool) -> list[int]:
    trellis = BWD_TRELLIS_I if mode_bwd else FWD_TRELLIS_I
    out = [0] * 8
    for s in range(8):
        paths = trellis[s]
        m0 = mod_add_i(state_in[paths[0][0]], gamma_in[paths[0][1]])
        m1 = mod_add_i(state_in[paths[1][0]], gamma_in[paths[1][1]])
        m2 = mod_add_i(state_in[paths[2][0]], gamma_in[paths[2][1]])
        m3 = mod_add_i(state_in[paths[3][0]], gamma_in[paths[3][1]])
        out[s] = mod_max4_i(m0, m1, m2, m3)
    return out


def radix4_next_state_i(cur_state: int, u0: int, u1: int) -> int:
    return NS[NS[cur_state][u0]][u1]


def radix4_extract_windowed_i(
    alpha_in: list[int],
    beta_in: list[int],
    sys_even: int,
    sys_odd: int,
    par_even: int,
    par_odd: int,
    apri_even: int,
    apri_odd: int,
) -> tuple[int, int, int, int]:
    g0 = branch_metric_unit_i(sys_even, par_even, apri_even)
    g1 = branch_metric_unit_i(sys_odd, par_odd, apri_odd)

    alpha_mid = [METRIC_INIT_NEG] * 8
    beta_mid = [METRIC_INIT_NEG] * 8
    alpha_mid_set = [False] * 8
    beta_mid_set = [False] * 8

    max0_u0 = 0
    max1_u0 = 0
    max0_u1 = 0
    max1_u1 = 0
    init0_u0 = True
    init1_u0 = True
    init0_u1 = True
    init1_u1 = True

    for start_s in range(8):
        for u in (0, 1):
            mid_s = NS[start_s][u]
            p = PAR[start_s][u]
            idx = u * 2 + p
            metric_v = mod_add_i(alpha_in[start_s], g0[idx])
            if not alpha_mid_set[mid_s]:
                alpha_mid[mid_s] = metric_v
                alpha_mid_set[mid_s] = True
            else:
                alpha_mid[mid_s] = mod_max_i(alpha_mid[mid_s], metric_v)

    for mid_s in range(8):
        for u in (0, 1):
            end_s = NS[mid_s][u]
            p = PAR[mid_s][u]
            idx = u * 2 + p
            metric_v = mod_add_i(g1[idx], beta_in[end_s])
            if not beta_mid_set[mid_s]:
                beta_mid[mid_s] = metric_v
                beta_mid_set[mid_s] = True
            else:
                beta_mid[mid_s] = mod_max_i(beta_mid[mid_s], metric_v)

    for start_s in range(8):
        for u in (0, 1):
            mid_s = NS[start_s][u]
            p = PAR[start_s][u]
            idx = u * 2 + p
            metric_v = mod_add_i(mod_add_i(alpha_in[start_s], g0[idx]), beta_mid[mid_s])
            if u == 0:
                if init0_u0:
                    max0_u0 = metric_v
                    init0_u0 = False
                else:
                    max0_u0 = mod_max_i(max0_u0, metric_v)
            else:
                if init1_u0:
                    max1_u0 = metric_v
                    init1_u0 = False
                else:
                    max1_u0 = mod_max_i(max1_u0, metric_v)

    for mid_s in range(8):
        for u in (0, 1):
            end_s = NS[mid_s][u]
            p = PAR[mid_s][u]
            idx = u * 2 + p
            metric_v = mod_add_i(mod_add_i(alpha_mid[mid_s], g1[idx]), beta_in[end_s])
            if u == 0:
                if init0_u1:
                    max0_u1 = metric_v
                    init0_u1 = False
                else:
                    max0_u1 = mod_max_i(max0_u1, metric_v)
            else:
                if init1_u1:
                    max1_u1 = metric_v
                    init1_u1 = False
                else:
                    max1_u1 = mod_max_i(max1_u1, metric_v)

    post0 = mod_sub_i(max1_u0, max0_u0)
    post1 = mod_sub_i(max1_u1, max0_u1)
    ext0 = mod_sub_i(mod_sub_i(post0, sys_even), apri_even)
    ext1 = mod_sub_i(mod_sub_i(post1, sys_odd), apri_odd)
    return scale_ext_i(ext0), scale_ext_i(ext1), sat_post_i(post0), sat_post_i(post1)


def window_pairs_for(seg_len: int, win_idx: int) -> int:
    start_bit = win_idx * 30
    if seg_len <= start_bit:
        return 0
    rem_bits = seg_len - start_bit
    if rem_bits > 30:
        rem_bits = 30
    return (rem_bits + 1) // 2


def siso_fixed_windowed(
    lsys: list[int],
    lpar: list[int],
    lapri: list[int],
    seg_first: bool,
    seg_last: bool,
) -> tuple[list[int], list[int]]:
    seg_len = len(lsys)
    pair_count = (seg_len + 1) // 2
    win_count = (seg_len + 29) // 30

    sys_even_mem = [0] * pair_count
    sys_odd_mem = [0] * pair_count
    par_even_mem = [0] * pair_count
    par_odd_mem = [0] * pair_count
    apri_even_mem = [0] * pair_count
    apri_odd_mem = [0] * pair_count
    gamma_mem: list[list[int]] = [[0] * 16 for _ in range(pair_count)]
    alpha_seed_mem: list[list[int]] = [[0] * 8 for _ in range(max(1, win_count))]

    for pair_idx in range(pair_count):
        even_idx = pair_idx * 2
        odd_idx = even_idx + 1
        sys_even_mem[pair_idx] = lsys[even_idx] if even_idx < seg_len else 0
        sys_odd_mem[pair_idx] = lsys[odd_idx] if odd_idx < seg_len else 0
        par_even_mem[pair_idx] = lpar[even_idx] if even_idx < seg_len else 0
        par_odd_mem[pair_idx] = lpar[odd_idx] if odd_idx < seg_len else 0
        apri_even_mem[pair_idx] = lapri[even_idx] if even_idx < seg_len else 0
        apri_odd_mem[pair_idx] = lapri[odd_idx] if odd_idx < seg_len else 0
        gamma_mem[pair_idx] = radix4_bmu_i(
            sys_even_mem[pair_idx],
            sys_odd_mem[pair_idx],
            par_even_mem[pair_idx],
            par_odd_mem[pair_idx],
            apri_even_mem[pair_idx],
            apri_odd_mem[pair_idx],
        )

    start_seed = terminated_state_i() if seg_first else [0] * 8
    end_seed = terminated_state_i() if seg_last else [0] * 8

    # Dummy forward warm-up on the first window. This mirrors the RTL startup
    # overhead. The actual forward seeds use the segment boundary model chosen
    # by seg_first/seg_last to match the active RTL.
    alpha_dummy = list(start_seed)
    for local_idx in range(window_pairs_for(seg_len, 0)):
        alpha_dummy = radix4_acs_i(alpha_dummy, gamma_mem[local_idx], False)

    alpha_seed_mem[0] = list(start_seed)
    alpha_cur = list(start_seed)
    for win_idx in range(win_count):
        start_pair = win_idx * 15
        win_pair_count = window_pairs_for(seg_len, win_idx)
        for local_idx in range(win_pair_count):
            alpha_cur = radix4_acs_i(alpha_cur, gamma_mem[start_pair + local_idx], False)
        if win_idx + 1 < win_count:
            alpha_seed_mem[win_idx + 1] = list(alpha_cur)

    ext = [0] * seg_len
    post = [0] * seg_len
    for win_idx in range(win_count - 1, -1, -1):
        start_pair = win_idx * 15
        win_pair_count = window_pairs_for(seg_len, win_idx)

        if win_idx == win_count - 1:
            beta_seed = list(end_seed)
        else:
            beta_seed = [0] * 8
            next_start_pair = (win_idx + 1) * 15
            next_pair_count = window_pairs_for(seg_len, win_idx + 1)
            for local_idx in range(next_pair_count - 1, -1, -1):
                beta_seed = radix4_acs_i(beta_seed, gamma_mem[next_start_pair + local_idx], True)

        alpha_local: list[list[int]] = [[METRIC_INIT_NEG] * 8 for _ in range(win_pair_count)]
        gamma_local: list[list[int]] = [[0] * 16 for _ in range(win_pair_count)]
        alpha_cur = list(alpha_seed_mem[win_idx])
        for local_idx in range(win_pair_count):
            pair_idx = start_pair + local_idx
            alpha_local[local_idx] = list(alpha_cur)
            gamma_local[local_idx] = list(gamma_mem[pair_idx])
            alpha_cur = radix4_acs_i(alpha_cur, gamma_local[local_idx], False)

        beta_cur = list(beta_seed)
        for local_idx in range(win_pair_count - 1, -1, -1):
            pair_idx = start_pair + local_idx
            ext_even, ext_odd, post_even, post_odd = radix4_extract_windowed_i(
                alpha_local[local_idx],
                beta_cur,
                sys_even_mem[pair_idx],
                sys_odd_mem[pair_idx],
                par_even_mem[pair_idx],
                par_odd_mem[pair_idx],
                apri_even_mem[pair_idx],
                apri_odd_mem[pair_idx],
            )
            even_idx = pair_idx * 2
            odd_idx = even_idx + 1
            if even_idx < seg_len:
                ext[even_idx] = ext_even
                post[even_idx] = post_even
            if odd_idx < seg_len:
                ext[odd_idx] = ext_odd
                post[odd_idx] = post_odd
            beta_cur = radix4_acs_i(beta_cur, gamma_local[local_idx], True)

    return ext, post


def turbo_decode_reference_half_iter_fixed(
    lsys_orig_q: list[int],
    lpar1_orig_q: list[int],
    lpar2_int_q: list[int],
    pi: list[int],
    n_half_iter: int,
) -> dict[str, list[int]]:
    k_len = len(lsys_orig_q)
    if k_len % 8 != 0:
        raise ValueError("Fixed-point paper-aligned model expects K divisible by 8")

    seg_len = k_len // 8
    lsys_int_q = [lsys_orig_q[pi[k]] for k in range(k_len)]
    ext_nat = [0] * k_len
    post_orig = [0] * k_len
    post_int = [0] * k_len

    for half in range(n_half_iter):
        if (half % 2) == 0:
            ext1_nat = [0] * k_len
            post1_nat = [0] * k_len
            for seg in range(8):
                base = seg * seg_len
                ext_seg, post_seg = siso_fixed_windowed(
                    lsys_orig_q[base:base + seg_len],
                    lpar1_orig_q[base:base + seg_len],
                    ext_nat[base:base + seg_len],
                    seg == 0,
                    seg == 7,
                )
                ext1_nat[base:base + seg_len] = ext_seg
                post1_nat[base:base + seg_len] = post_seg
            ext_nat = ext1_nat
            if half == n_half_iter - 1:
                post_orig = post1_nat
                post_int = [post_orig[pi[k]] for k in range(k_len)]
        else:
            apri_int = [ext_nat[pi[k]] for k in range(k_len)]
            ext2_int = [0] * k_len
            post2_int = [0] * k_len
            for seg in range(8):
                base = seg * seg_len
                ext_seg, post_seg = siso_fixed_windowed(
                    lsys_int_q[base:base + seg_len],
                    lpar2_int_q[base:base + seg_len],
                    apri_int[base:base + seg_len],
                    seg == 0,
                    seg == 7,
                )
                ext2_int[base:base + seg_len] = ext_seg
                post2_int[base:base + seg_len] = post_seg
            ext_nat = [0] * k_len
            for k in range(k_len):
                ext_nat[pi[k]] = ext2_int[k]
            if half == n_half_iter - 1:
                post_int = post2_int
                post_orig = [0] * k_len
                for k in range(k_len):
                    post_orig[pi[k]] = post2_int[k]

    return {
        "post_int": post_int,
        "hard_int": [1 if v < 0 else 0 for v in post_int],
        "post_orig": post_orig,
        "hard_orig": [1 if v < 0 else 0 for v in post_orig],
    }



def write_lines(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate LTE-like turbo vectors for RTL TB")
    ap.add_argument("--k", type=int, default=40, help="Information block length")
    ap.add_argument("--n-half-iter", type=int, default=11, help="Turbo decoder half-iterations")
    ap.add_argument("--n-iter", type=int, default=None, help="Deprecated alias; converted to 2*n_iter")
    ap.add_argument("--snr-db", type=float, default=1.5, help="AWGN Es/N0 in dB")
    ap.add_argument("--llr-scale", type=float, default=2.0, help="Scale before 5-bit quantization")
    ap.add_argument("--seed", type=int, default=12345, help="Random seed")
    ap.add_argument("--f1", type=int, default=None, help="QPP f1 (override table)")
    ap.add_argument("--f2", type=int, default=None, help="QPP f2 (override table)")
    ap.add_argument("--outdir", type=Path, default=Path("sim_vectors"), help="Output directory")
    args = ap.parse_args()
    if args.n_iter is not None:
        args.n_half_iter = args.n_iter * 2

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

    ref = turbo_decode_reference_half_iter(lsys_f, lpar1_f, lpar2_int_f, pi, args.n_half_iter)
    ref_fixed = turbo_decode_reference_half_iter_fixed(lsys_q, lpar1_q, lpar2_q, pi, args.n_half_iter)

    vec_lines = [f"{args.k} {args.n_half_iter} {f1} {f2}"]
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

    ref_fixed_int_lines = ["# idx_int bit_int post_llr_q hard"]
    for i in range(args.k):
        post = ref_fixed["post_int"][i]
        hard = ref_fixed["hard_int"][i]
        ref_fixed_int_lines.append(f"{i} {bits_int[i]} {post} {hard}")
    write_lines(args.outdir / "reference_fixed_interleaved.txt", ref_fixed_int_lines)

    ref_fixed_orig_lines = ["# idx_orig bit_orig post_llr_q hard"]
    for i in range(args.k):
        post = ref_fixed["post_orig"][i]
        hard = ref_fixed["hard_orig"][i]
        ref_fixed_orig_lines.append(f"{i} {bits_orig[i]} {post} {hard}")
    write_lines(args.outdir / "reference_fixed_original.txt", ref_fixed_orig_lines)

    meta_lines = [
        "LTE-like Turbo Frame Generation Summary",
        f"K={args.k} n_half_iter={args.n_half_iter} f1={f1} f2={f2}",
        f"seed={args.seed} snr_db={args.snr_db:.4f} sigma2={sigma2:.8f} llr_scale={args.llr_scale:.4f}",
        f"tail_u1={''.join(str(b) for b in tail_u1)} tail_p1={''.join(str(b) for b in tail_p1)}",
        f"tail_u2={''.join(str(b) for b in tail_u2)} tail_p2={''.join(str(b) for b in tail_p2)}",
        "Outputs:",
        "- lte_frame_input_vectors.txt (consumed by tb_turbo_top)",
        "- reference_interleaved.txt (floating max-log reference, interleaved domain)",
        "- reference_original.txt (floating max-log reference, original domain)",
        "- reference_fixed_interleaved.txt (5/6/7/10-bit fixed-point reference, interleaved domain)",
        "- reference_fixed_original.txt (5/6/7/10-bit fixed-point reference, original domain)",
    ]
    write_lines(args.outdir / "lte_frame_generation_report.txt", meta_lines)

    print("Generated vectors and reference in", args.outdir)


if __name__ == "__main__":
    main()
