# =============================================================================
#  WT-NPU Makefile   (butuh: python3+numpy, iverilog>=11 / vvp)
#    make test     -> unit PE + full-chip 62x62 + cek vs golden
#    make small    -> N=8 cepat (+ uji auto-steer FAULT=1)
#    make stress   -> N=16 ambang termal rendah => ice-wall aktif sampai L4
#    make model    -> hanya model Python (tanpa Verilog)
# =============================================================================
IVERILOG ?= iverilog
VVP      ?= vvp
PY       ?= python3
N        ?= 62
K        ?= 128
FAULT    ?= 0
MODE     ?= random
RTL      := $(wildcard rtl/*.sv)
TOP      := tb_wt_npu

.PHONY: test small stress model pe clean vectors
test: pe full
vectors:
	@mkdir -p build vectors
	$(PY) model/wt_gen_vectors.py --n $(N) --k $(K) --mode $(MODE) --out vectors
model: vectors
	$(PY) model/wt_cosim.py --n $(N) --k $(K) --fault $(FAULT) $(EXTRA_PY)
pe:
	@mkdir -p build
	$(IVERILOG) -g2012 -o build/pe.vvp tb/tb_wt_pe.sv rtl/wt_pe.sv && $(VVP) build/pe.vvp
full: vectors
	$(PY) model/wt_cosim.py --n $(N) --k $(K) --fault $(FAULT) $(EXTRA_PY)
	$(IVERILOG) -g2012 -P$(TOP).N=$(N) -P$(TOP).K=$(K) -P$(TOP).FAULT=$(FAULT) $(EXTRA_V) \
	    -o build/wt.vvp tb/tb_wt_npu.sv $(RTL)
	$(VVP) build/wt.vvp
	$(PY) model/wt_check.py $(STRICT)
small:
	$(MAKE) full N=8 K=40 FAULT=1
stress:
	$(MAKE) full N=16 K=400 MODE=max STRICT=--strict \
	  EXTRA_PY="--heat_k 12 --warn 1500 --hot 3000 --crit 4500 --emer 6000 --hyst 200" \
	  EXTRA_V="-P$(TOP).HEAT_K=12 -P$(TOP).WARN=1500 -P$(TOP).HOT=3000 -P$(TOP).CRIT=4500 -P$(TOP).EMER=6000 -P$(TOP).HYST=200"
clean:
	rm -rf build/* vectors/*
