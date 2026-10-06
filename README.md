# WT-NPU — Water-Turbo & Ice-Wall INT8 NPU (62×62)

```
WT-NPU/
├── rtl/        SystemVerilog: wt_pe, wt_lane_steer, wt_skew, wt_systolic_array,
│               wt_thermal_fluid, wt_ice_wall_ctrl, wt_npu_top
├── tb/         tb_wt_pe (unit), tb_wt_npu (full-chip, self-dumping)
├── model/      Python: wt_golden, wt_gen_vectors, wt_cosim (bit-accurate), wt_check, wt_thermal_model
├── scripts/    run_all.sh
├── syn/        yosys_synth.ys, wt_npu.sdc
├── docs/       ARCHITECTURE.md (matematika & desain)
├── vectors/    a.hex b.hex c_golden.hex (dibuat otomatis)
└── build/      keluaran simulasi
```
## Cara pakai
```
make model            # hanya Python (tanpa simulator)
make small            # N=8 + uji auto-steer
make test             # PE unit + N=62 penuh
make stress           # ice-wall aktif sampai L4, hasil matriks harus tetap benar
./scripts/run_all.sh  # semua regresi
```
Butuh: Python 3 + numpy, Icarus Verilog ≥ 11 (`iverilog -g2012`).

## Status verifikasi
* Python model: **sudah dijalankan** (N=8, 16, 62; throttle sampai L4) — hasil == golden matmul.
* RTL SystemVerilog: **belum dikompilasi** di lingkungan pembuatan (tidak ada iverilog). Jalankan
  `make small` dahulu; `wt_check.py --strict` membandingkan statistik RTL vs model sampai bit.
