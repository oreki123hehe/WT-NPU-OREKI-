"""WT-NPU | wt_check.py | Bandingkan keluaran RTL vs golden (+ statistik vs model)."""
import sys, os
import numpy as np
from wt_golden import read_hex32

def load_stats(p):
    d = {}
    for ln in open(p):
        if "=" in ln:
            k, v = ln.strip().split("=")
            d[k] = int(v)
    return d

strict = "--strict" in sys.argv
g = read_hex32("vectors/c_golden.hex")
r = read_hex32("build/c_out.hex")
ok = g.shape == r.shape and np.array_equal(g, r)
print("[C-matrix] RTL vs golden :", "PASS" if ok else f"FAIL ({int((g != r).sum())} elemen salah)")
rc = 0 if ok else 1
if os.path.exists("build/stats_rtl.txt") and os.path.exists("build/stats_model.txt"):
    s1, s2 = load_stats("build/stats_rtl.txt"), load_stats("build/stats_model.txt")
    diff = {k: (s1.get(k), s2.get(k)) for k in s2 if s1.get(k) != s2.get(k)}
    print("[stats]    RTL vs model  :", "PASS (identik)" if not diff else f"BEDA {diff}")
    if diff and strict:
        rc = 1
sys.exit(rc)
