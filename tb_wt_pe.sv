// WT-NPU | tb_wt_pe.sv | Uji unit PE: MAC bertanda, zero-gating, clr
`timescale 1ns/1ps
module tb_wt_pe;
    reg clk = 0, rst_n = 0, clr = 0, en = 0;
    reg signed [7:0] a, b;
    wire signed [7:0] ao, bo;
    wire signed [31:0] acc;
    wire [4:0] tgl;
    wt_pe dut(.clk(clk), .rst_n(rst_n), .clr(clr), .en(en), .a_in(a), .b_in(b),
              .a_out(ao), .b_out(bo), .acc(acc), .tgl(tgl));
    always #5 clk = ~clk;
    integer errs = 0, i;
    integer ref_acc = 0, ra, rb;
    initial begin
        a = 0; b = 0;
        repeat (2) @(posedge clk); #1 rst_n = 1;
        @(posedge clk); #1 clr = 1; @(posedge clk); #1 clr = 0; en = 1;
        for (i = 0; i < 500; i = i + 1) begin
            ra = ($random % 256); rb = ($random % 256);
            if (ra > 127) ra = ra - 256; if (ra < -128) ra = ra + 256;
            if (rb > 127) rb = rb - 256; if (rb < -128) rb = rb + 256;
            a = ra; b = rb;
            @(posedge clk); #1;
            ref_acc = ref_acc + ra*rb;
            if (acc !== ref_acc) begin errs = errs + 1; $display("MISMATCH i=%0d acc=%0d ref=%0d", i, acc, ref_acc); end
        end
        en = 0; a = 8'sd127; b = 8'sd127; @(posedge clk); #1;
        if (acc !== ref_acc) begin errs = errs + 1; $display("en=0 harus menahan acc"); end
        $display(errs == 0 ? "tb_wt_pe: PASS" : "tb_wt_pe: FAIL (%0d)", errs);
        $finish;
    end
endmodule
