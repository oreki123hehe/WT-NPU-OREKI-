"""WT-NPU | wt_thermal_model.py | Studi termal float (kontinu) utk memilih parameter.
Membandingkan: tanpa kontrol vs dengan ice-wall (duty-cycle) pada beban seragam."""
import numpy as np

def simulate(steps=4000, n=31, q=0.9, alpha=0.125, cool=1/64, wall=True,
             warn=40.0, hot=55.0, crit=65.0):
    T = np.zeros((n, n)); duty = 1.0; trace = []
    for s in range(steps):
        P = np.pad(T, 1)
        lap = P[:-2,1:-1] + P[2:,1:-1] + P[1:-1,:-2] + P[1:-1,2:] - 4*T
        T = T + q*duty + alpha*lap - cool*T
        tm = T.max()
        if wall:
            duty = 1.0 if tm < warn else 0.75 if tm < hot else 0.5 if tm < crit else 0.25
        trace.append((s, tm, duty))
    return np.array(trace)

if __name__ == "__main__":
    for w in (False, True):
        tr = simulate(wall=w)
        print(f"ice-wall={'ON ' if w else 'OFF'} Tmax akhir={tr[-1,1]:6.1f} C  Tmax puncak={tr[:,1].max():6.1f} C  duty akhir={tr[-1,2]:.2f}")
