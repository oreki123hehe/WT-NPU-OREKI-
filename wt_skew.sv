// =============================================================================
//  WT-NPU  |  wt_skew.sv  |  Skew buffer: lorong i ditunda i siklus
//  Menyelaraskan wavefront systolic. Ikut berhenti saat 'en'=0 (ice-wall stall).
// =============================================================================
`timescale 1ns/1ps
module wt_skew #(
    parameter N = 62,
    parameter W = 8
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             clr,
    input  wire             en,
    input  wire [N*W-1:0]   din,
    output wire [N*W-1:0]   dout
);
    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_lane
            if (i == 0) begin : g_d0
                assign dout[i*W +: W] = din[i*W +: W];
            end else begin : g_dn
                reg [W-1:0] sr [0:i-1];
                integer d;
                always @(posedge clk) begin
                    if (!rst_n || clr) begin
                        for (d = 0; d < i; d = d + 1) sr[d] <= {W{1'b0}};
                    end else if (en) begin
                        sr[0] <= din[i*W +: W];
                        for (d = 1; d < i; d = d + 1) sr[d] <= sr[d-1];
                    end
                end
                assign dout[i*W +: W] = sr[i-1];
            end
        end
    endgenerate
endmodule
