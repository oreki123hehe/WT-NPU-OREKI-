# WT-NPU — Arsitektur & Matematika

## 1. Dataflow (output-stationary systolic, INT8 → INT32)
C[i][j] = Σ_k A[i][k]·B[k][j].  PE(i,j) menerima A[i][k] dan B[k][j] pada siklus **k+i+j**
(skew lorong i = i siklus). Total siklus run = K + 2N − 2 (tanpa stall).
Akumulator 32-bit aman untuk K ≤ 131071 (|a·b| ≤ 16384 = 2^14).

## 2. Auto-Steering (Channel ID)
Paket {ID, data} di slot fisik i → lorong ID. Crossbar berbasis pembanding ID (N² comparator).
Deteksi: misroute (ID≠slot), collision (dua paket → satu lorong; data dibuang =0), id_err, lane_miss.
Pada tabrakan, hasil TIDAK dijamin benar → flag `stat_steer_fault` naik (fail-safe, bukan fail-silent).

## 3. Virtual Fluid (estimator termal)
Zona z = blok ZS×ZS PE. Persamaan panas diskret (Q8.8 °C):

  T'[z] = T[z] + ⌊E[z]·K_h / 2^h⌋ + ⌊Σ_{n∈N4}(T[n]−T[z]) / 2^s⌋ − ⌊T[z] / 2^c⌋

E[z] = Σ Hamming(a_in⊕a_reg) + Hamming(b_in⊕b_reg) dalam TICK siklus (proksi daya dinamis α·C·V²·f).
Tetangga di luar grid = reservoir ambient (T=0) → tepi = "zona penampung".
Stabilitas eksplisit (von Neumann 2-D): 4/2^s ≤ 1 → s ≥ 2 (DIFF_SH=3, turbo=2 stabil).
Steady-state seragam: T* = 2^c · E·K_h/2^h (tanpa difusi).  Turbo-flow: Tmax > TURBO_T → s: 3→2.

## 4. Ice Wall (kontrol prediktif)
T_pred = Tmax + (Tmax − Tmax_prev)·2^PRED_SH.  Level naik jika T_pred ≥ ambang[level];
turun jika T_pred + HYST < ambang[level−1].  Duty (8 siklus): 100/75/50/25/12.5 %.
Throttle global sinkron ⇒ hasil matriks tetap benar (diverifikasi pada stress test hingga L4).

## 5. Catatan jujur
* Estimator termal adalah **model digital-twin** (bukan sensor fisik). Klaim "tanpa kipas" bergantung
  pada paket termal nyata; kode ini menyediakan *mekanisme kendali* + model, bukan jaminan fisik.
* `wt_thermal_fluid` besar bila ZS=2 (961 zona); untuk sintesis gunakan ZS=31 (2×2 zona) atau ZS=62.
* Mean `sm / NZZ` memakai pembagi konstan (simulasi); untuk sintesis ganti ke shift/reciprocal.
