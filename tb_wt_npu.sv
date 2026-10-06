// =============================================================================
//  WT-NPU | tb_wt_npu.sv | Testbench self-contained (Icarus: iverilog -g2012)
//  Membaca vectors/a.hex & vectors/b.hex, menjalankan NPU, menulis
//  build/c_out.hex dan build/stats_rtl.txt untuk dibandingkan oleh model Python.
// =============================================================================
`timescale 1ns/1ps
module tb_wt_npu;
    parameter N       = 62;
    parameter K       = 128;
    parameter IDW     = $clog2(N);
    parameter ZS      = 2;
    parameter FAULT   = 0;          // 1 = tukar slot fisik lorong 3 & 5 (uji auto-steer)
    parameter TICK    = 16;
    parameter HEAT_K  = 3;
    parameter HEAT_SH = 2;
    parameter COOL_SH = 6;
    parameter WARN    = 10240;
    parameter HOT     = 14080;
    parameter CRIT    = 16640;
    parameter EMER    = 19200;
    parameter HYST    = 512;
    parameter TURBO_T = 12000;
    parameter MAXCYC  = 4000000;

    localparam PW = IDW + 8;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg                 rst_n = 1'b0;
    reg                 start = 1'b0;
    reg  [15:0]         k_len = K;
    reg  [15:0]         rd_row = 16'd0;
    reg  [N*PW-1:0]     a_pkt, b_pkt;
    wire [15:0]         k_idx;
    wire [N*32-1:0]     rd_data;
    wire                busy, done;
    wire [2:0]          level, stat_max_level, stat_level;
    wire [15:0]         tmax_live, hot_zone, stat_tmax, stat_tavg;
    wire [31:0]         stat_cycles, stat_stalled, stat_energy, stat_steer_fixed;
    wire                stat_steer_fault;

    wt_npu_top #(
        .N(N), .IDW(IDW), .ZS(ZS), .TICK(TICK), .HEAT_K(HEAT_K), .HEAT_SH(HEAT_SH),
        .COOL_SH(COOL_SH), .WARN(WARN), .HOT(HOT), .CRIT(CRIT), .EMER(EMER),
        .HYST(HYST), .TURBO_T(TURBO_T)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .k_len(k_len), .k_idx(k_idx),
        .a_pkt(a_pkt), .b_pkt(b_pkt), .rd_row(rd_row), .rd_data(rd_data),
        .busy(busy), .done(done), .level(level), .tmax_live(tmax_live), .hot_zone(hot_zone),
        .stat_cycles(stat_cycles), .stat_stalled(stat_stalled), .stat_energy(stat_energy),
        .stat_steer_fixed(stat_steer_fixed), .stat_max_level(stat_max_level),
        .stat_tmax(stat_tmax), .stat_tavg(stat_tavg), .stat_level(stat_level),
        .stat_steer_fault(stat_steer_fault)
    );

    reg [7:0] amem [0:N*K-1];
    reg [7:0] bmem [0:K*N-1];
    reg       loaded = 1'b0;

    function integer phys(input integer lane);
        begin
            phys = lane;
            if (FAULT != 0 && N > 5) begin
                if (lane == 3) phys = 5;
                if (lane == 5) phys = 3;
            end
        end
    endfunction

    integer li;
    reg [7:0] da, db;
    reg [IDW-1:0] lid;
    always @(k_idx or loaded) begin
        a_pkt = {N*PW{1'b0}};
        b_pkt = {N*PW{1'b0}};
        for (li = 0; li < N; li = li + 1) begin
            da = 8'd0; db = 8'd0;
            if (loaded && k_idx < K) begin
                da = amem[li*K + k_idx];
                db = bmem[k_idx*N + li];
            end
            lid = li;
            a_pkt[phys(li)*PW +: PW] = {lid, da};
            b_pkt[phys(li)*PW +: PW] = {lid, db};
        end
    end

    // Assertion sederhana: ketika busy, stall tidak boleh membuat k_idx mundur
    reg [15:0] prev_k = 16'd0;
    always @(posedge clk) begin
        if (busy && k_idx < prev_k) begin
            $display("ASSERT FAIL: k_idx mundur (%0d -> %0d)", prev_k, k_idx);
            $finish;
        end
        prev_k <= k_idx;
    end

    integer fo, r, c, cyc;
    initial begin
        $readmemh("vectors/a.hex", amem);
        $readmemh("vectors/b.hex", bmem);
        loaded = 1'b1;
        repeat (4) @(posedge clk);
        #1 rst_n = 1'b1;
        repeat (2) @(posedge clk);
        #1 start = 1'b1;
        @(posedge clk);
        #1 start = 1'b0;

        cyc = 0;
        while (!done && cyc < MAXCYC) begin
            @(posedge clk); cyc = cyc + 1;
        end
        if (!done) begin
            $display("TIMEOUT: done tidak pernah naik");
            $finish;
        end

        fo = $fopen("build/c_out.hex", "w");
        for (r = 0; r < N; r = r + 1) begin
            rd_row = r; #1;
            for (c = 0; c < N; c = c + 1)
                $fdisplay(fo, "%08x", rd_data[c*32 +: 32]);
        end
        $fclose(fo);

        fo = $fopen("build/stats_rtl.txt", "w");
        $fdisplay(fo, "cycles=%0d",       stat_cycles);
        $fdisplay(fo, "stalled=%0d",      stat_stalled);
        $fdisplay(fo, "energy=%0d",       stat_energy);
        $fdisplay(fo, "tmax=%0d",         stat_tmax);
        $fdisplay(fo, "tavg=%0d",         stat_tavg);
        $fdisplay(fo, "level=%0d",        stat_level);
        $fdisplay(fo, "max_level=%0d",    stat_max_level);
        $fdisplay(fo, "steer_fixed=%0d",  stat_steer_fixed);
        $fdisplay(fo, "steer_fault=%0d",  stat_steer_fault);
        $fclose(fo);

        $display("WT-NPU selesai: N=%0d K=%0d cycles=%0d stalled=%0d tmax=%0d (%0d.%02d C) max_level=%0d steer_fixed=%0d fault=%0d",
                 N, K, stat_cycles, stat_stalled, stat_tmax, stat_tmax/256, ((stat_tmax%256)*100)/256,
                 stat_max_level, stat_steer_fixed, stat_steer_fault);
        $finish;
    end
endmodule
