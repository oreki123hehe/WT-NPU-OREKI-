"""
WT-NPU | wt_cosim.py | Model siklus-akurat (bit-accurate) seluruh NPU:
systolic INT8 62x62 + skew + auto-steer + estimator termal 'virtual fluid' +
kontrol 'ice wall'.  Aritmetikanya identik dengan RTL (integer, Q8.8), sehingga
statistik (cycles, stalled, energy, tmax, level, ...) bisa dibandingkan 1:1.
"""
import argparse, os
import numpy as np
from wt_golden import matmul_int8, write_hex32

PC = np.array([bin(i).count("1") for i in range(256)], dtype=np.int64)
MASKS = {0: 0xFF, 1: 0xEE, 2: 0xAA, 3: 0x88, 4: 0x80}
S_IDLE, S_CLR, S_RUN, S_DONE = 0, 1, 2, 3

DEFAULTS = dict(N=62, K=128, ZS=2, TICK=16, HEAT_K=3, HEAT_SH=2, COOL_SH=6,
                DIFF_SH=3, DIFF_SH_TURBO=2, TURBO_T=12000, WARN=10240, HOT=14080,
                CRIT=16640, EMER=19200, HYST=512, PRED_SH=2)


def sgn8(x):
    return np.where(x >= 128, x - 256, x)


def thermal_step(T, zacc, tmax_q, c):
    NZ = T.shape[0]
    dsh = c["DIFF_SH_TURBO"] if tmax_q > c["TURBO_T"] else c["DIFF_SH"]
    P = np.pad(T, 1)
    lap = P[:-2, 1:-1] + P[2:, 1:-1] + P[1:-1, :-2] + P[1:-1, 2:] - 4 * T
    heat = (zacc * c["HEAT_K"]) >> c["HEAT_SH"]
    dT = heat + (lap >> dsh) - (T >> c["COOL_SH"])
    nt = np.clip(T + dT, 0, 65535)
    return nt, int(nt.max()), int(nt.sum() // (NZ * NZ))


def run(A, B, c, fault=False, start_edge=2, max_edges=5_000_000):
    N, K, ZS = c["N"], c["K"], c["ZS"]
    NZ = N // ZS
    Au = A.astype(np.int64) & 0xFF
    Bu = B.astype(np.int64) & 0xFF
    ar = np.arange(N)
    a_reg = np.zeros((N, N), np.int64); b_reg = np.zeros((N, N), np.int64)
    acc = np.zeros((N, N), np.int64)
    sa = np.zeros((N, N), np.int64); sb = np.zeros((N, N), np.int64)
    T = np.zeros((NZ, NZ), np.int64); zacc = np.zeros((NZ, NZ), np.int64)
    tmax_q = tavg_q = tprev = 0
    tick_q = False
    level = 0
    st, cnt, total = S_IDLE, 0, 0
    st_ = dict(cycles=0, stalled=0, energy=0, tmax=0, tavg=0, level=0,
               max_level=0, steer_fixed=0, steer_fault=0)
    mis_per_cycle = 4 if (fault and N > 5) else 0

    for e in range(max_edges):
        phase = e % 8
        ice_adv = (MASKS[level] >> phase) & 1
        run_ = st == S_RUN
        clr = st == S_CLR
        adv = run_ and bool(ice_adv)
        feed = run_ and cnt < K

        a_lane = Au[:, cnt] if feed else np.zeros(N, np.int64)
        b_lane = Bu[cnt, :] if feed else np.zeros(N, np.int64)
        sa_out = np.where(ar == 0, a_lane, sa[ar, np.maximum(ar - 1, 0)])
        sb_out = np.where(ar == 0, b_lane, sb[ar, np.maximum(ar - 1, 0)])
        a_in = np.empty((N, N), np.int64); b_in = np.empty((N, N), np.int64)
        a_in[:, 0] = sa_out; a_in[:, 1:] = a_reg[:, :-1]
        b_in[0, :] = sb_out; b_in[1:, :] = b_reg[:-1, :]

        if adv:
            tgl = PC[a_in ^ a_reg] + PC[b_in ^ b_reg]
            zact = tgl.reshape(NZ, ZS, NZ, ZS).sum(axis=(1, 3))
        else:
            zact = np.zeros((NZ, NZ), np.int64)
        zsum = int(zact.sum())

        # ----- estimator termal (tepi clock e) -----
        new_T, new_tmax, new_tavg, new_tick = T, tmax_q, tavg_q, False
        new_zacc = zacc + zact
        if e % c["TICK"] == c["TICK"] - 1:
            new_T, new_tmax, new_tavg = thermal_step(T, zacc + zact, tmax_q, c)
            new_zacc = np.zeros_like(zacc)
            new_tick = True

        # ----- ice wall (memakai tick_q & tmax_q pra-tepi) -----
        new_level, new_tprev = level, tprev
        if tick_q:
            pred = max(0, tmax_q + ((tmax_q - tprev) << c["PRED_SH"]))
            thr = [c["WARN"], c["HOT"], c["CRIT"], c["EMER"]]
            if level < 4 and pred >= thr[min(level, 3)]:
                new_level = level + 1
            elif level > 0 and (pred + c["HYST"]) < thr[min(level - 1, 3)]:
                new_level = level - 1
            new_tprev = tmax_q

        # ----- FSM -----
        done_now = False
        if st in (S_IDLE, S_DONE):
            if e == start_edge:
                st_new, cnt_new, total = S_CLR, 0, K + 2 * N - 2
                st_.update(cycles=0, stalled=0, energy=0, steer_fixed=0, max_level=0, steer_fault=0)
            else:
                st_new, cnt_new = st, cnt
        elif st == S_CLR:
            st_new, cnt_new = S_RUN, cnt
        else:
            st_new, cnt_new = st, cnt
            st_["cycles"] += 1
            if not ice_adv: st_["stalled"] += 1
            if level > st_["max_level"]: st_["max_level"] = level
            if feed: st_["steer_fixed"] += mis_per_cycle
            if adv:
                st_["energy"] += zsum
                if cnt == total - 1:
                    st_new = S_DONE
                    st_.update(tmax=tmax_q, tavg=tavg_q, level=level)
                    done_now = True
                else:
                    cnt_new = cnt + 1

        # ----- update register array -----
        if clr:
            a_reg[:] = 0; b_reg[:] = 0; acc[:] = 0; sa[:] = 0; sb[:] = 0
        elif adv:
            acc = ((acc + sgn8(a_in) * sgn8(b_in) + 2**31) % 2**32) - 2**31
            a_reg = a_in.copy(); b_reg = b_in.copy()
            sa[:, 1:] = sa[:, :-1].copy(); sa[:, 0] = a_lane
            sb[:, 1:] = sb[:, :-1].copy(); sb[:, 0] = b_lane

        T, zacc, tmax_q, tavg_q, tick_q = new_T, new_zacc, new_tmax, new_tavg, new_tick
        level, tprev, st, cnt = new_level, new_tprev, st_new, cnt_new
        if done_now:
            return acc.astype(np.int32), st_
    raise RuntimeError("model tidak selesai")


def main():
    ap = argparse.ArgumentParser()
    for k, v in DEFAULTS.items():
        ap.add_argument("--" + k.lower(), type=int, default=v)
    ap.add_argument("--fault", type=int, default=0)
    ap.add_argument("--vec", default="vectors")
    ap.add_argument("--out", default="build")
    a = ap.parse_args()
    c = {k: getattr(a, k.lower()) for k in DEFAULTS}
    A = np.load(os.path.join(a.vec, "a.npy")); B = np.load(os.path.join(a.vec, "b.npy"))
    assert A.shape == (c["N"], c["K"]), "dimensi vektor != N,K"
    C, stats = run(A, B, c, fault=bool(a.fault))
    assert np.array_equal(C, matmul_int8(A, B)), "MODEL SALAH: hasil != golden"
    os.makedirs(a.out, exist_ok=True)
    write_hex32(os.path.join(a.out, "c_model.hex"), C)
    with open(os.path.join(a.out, "stats_model.txt"), "w") as f:
        for k, v in stats.items():
            f.write(f"{k}={v}\n")
    print("model OK:", {k: int(v) for k, v in stats.items()})


if __name__ == "__main__":
    main()
