"""WT-NPU | wt_gen_vectors.py | Bangkitkan vektor uji: a.hex, b.hex, c_golden.hex"""
import argparse, os
import numpy as np
from wt_golden import matmul_int8, write_hex8, write_hex32

ap = argparse.ArgumentParser()
ap.add_argument("--n", type=int, default=62)
ap.add_argument("--k", type=int, default=128)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--mode", choices=["random", "extreme", "sparse", "max"], default="random")
ap.add_argument("--out", default="vectors")
a = ap.parse_args()

rng = np.random.default_rng(a.seed)
N, K = a.n, a.k
if a.mode == "random":
    A = rng.integers(-128, 128, (N, K), dtype=np.int16).astype(np.int8)
    B = rng.integers(-128, 128, (K, N), dtype=np.int16).astype(np.int8)
elif a.mode == "extreme":      # hanya -128 / 127 (stres tanda & overflow-path)
    A = rng.choice([-128, 127], (N, K)).astype(np.int8)
    B = rng.choice([-128, 127], (K, N)).astype(np.int8)
elif a.mode == "sparse":       # 85% nol -> uji zero-gating
    A = rng.integers(-128, 128, (N, K), dtype=np.int16).astype(np.int8) * (rng.random((N, K)) > 0.85)
    B = rng.integers(-128, 128, (K, N), dtype=np.int16).astype(np.int8) * (rng.random((K, N)) > 0.85)
    A, B = A.astype(np.int8), B.astype(np.int8)
else:                          # pola toggle maksimum 0x55 / 0xAA bergantian
    A = np.where((np.arange(K)[None, :] % 2) == 0, 0x55, -86).repeat(N, 0).astype(np.int8)
    B = np.where((np.arange(K)[:, None] % 2) == 0, 0x55, -86).repeat(N, 1).astype(np.int8)

os.makedirs(a.out, exist_ok=True)
write_hex8(os.path.join(a.out, "a.hex"), A)
write_hex8(os.path.join(a.out, "b.hex"), B)
write_hex32(os.path.join(a.out, "c_golden.hex"), matmul_int8(A, B))
np.save(os.path.join(a.out, "a.npy"), A)
np.save(os.path.join(a.out, "b.npy"), B)
print(f"vektor: N={N} K={K} mode={a.mode} seed={a.seed} -> {a.out}/")
