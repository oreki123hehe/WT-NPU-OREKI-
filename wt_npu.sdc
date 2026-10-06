# WT-NPU | batasan waktu contoh (ASIC/FPGA) - target 1 GHz kelas flagship
create_clock -name clk -period 1.0 [get_ports clk]
set_clock_uncertainty 0.05 [get_clocks clk]
set_input_delay  0.2 -clock clk [all_inputs]
set_output_delay 0.2 -clock clk [all_outputs]
# rd_data adalah mux baca statis -> multicycle
set_multicycle_path 2 -setup -to [get_ports rd_data*]
