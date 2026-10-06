// =============================================================================
//  WT-NPU  |  wt_pe.sv  |  Processing Element INT8 (output-stationary MAC)
//  acc <= acc + a*b  (INT8 x INT8 -> INT16 -> INT32 accumulate)
//  - Zero-gating  : MAC dilewati bila salah satu operand = 0 (hemat switching)
//  - tgl          : estimasi switching activity (Hamming distance a & b)
//  - clr          : sinkron, prioritas tertinggi, membersihkan semua register
// =============================================================================
`timescale 1ns/1ps
module wt_pe #(
    parameter ACCW = 32
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clr,
    input  wire                     en,
    input  wire signed [7:0]        a_in,
    input  wire signed [7:0]        b_in,
    output reg  signed [7:0]        a_out,
    output reg  signed [7:0]        b_out,
    output reg  signed [ACCW-1:0]   acc,
    output wire [4:0]               tgl
);
    function [3:0] pc8(input [7:0] v);
        integer k;
        begin
            pc8 = 4'd0;
            for (k = 0; k < 8; k = k + 1) pc8 = pc8 + v[k];
        end
    endfunction

    wire [7:0] xa = a_in ^ a_out;
    wire [7:0] xb = b_in ^ b_out;
    wire [4:0] raw_tgl = {1'b0, pc8(xa)} + {1'b0, pc8(xb)};
    assign tgl = en ? raw_tgl : 5'd0;

    wire zero_gate = (a_in == 8'sd0) || (b_in == 8'sd0);
    wire signed [15:0] prod = a_in * b_in;

    always @(posedge clk) begin
        if (!rst_n || clr) begin
            a_out <= 8'sd0;
            b_out <= 8'sd0;
            acc   <= {ACCW{1'b0}};
        end else if (en) begin
            a_out <= a_in;
            b_out <= b_in;
            if (!zero_gate) acc <= acc + prod;
        end
    end
endmodule
