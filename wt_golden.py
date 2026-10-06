"""WT-NPU | wt_golden.py | Model emas matematis INT8 (referensi matmul) + util hex."""
import numpy as np


def matmul_int8(A, B):
    """C = A @ B, A,B int8; akumulasi INT32 dengan wrap-around (sama dgn RTL)."""
    c = A.astype(np.int64) @ B.astype(np.int64)
    c = ((c + 2**31) % 2**32) - 2**31
    return c.astype(np.int32)


def write_hex8(path, arr):
    with open(path, "w") as f:
        for v in arr.reshape(-1):
            f.write("%02x\n" % (int(v) & 0xFF))


def write_hex32(path, arr):
    with open(path, "w") as f:
        for v in arr.reshape(-1):
            f.write("%08x\n" % (int(v) & 0xFFFFFFFF))


def read_hex32(path):
    out = []
    with open(path) as f:
        for ln in f:
            ln = ln.strip()
            if ln:
                v = int(ln, 16)
                out.append(v - (1 << 32) if v >= (1 << 31) else v)
    return np.array(out, dtype=np.int64)
