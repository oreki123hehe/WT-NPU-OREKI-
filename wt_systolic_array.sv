// =============================================================================
//  WT-NPU  |  wt_systolic_array.sv  |  Array N x N PE (default 62 x 62)
//  Output-stationary: A mengalir kiri->kanan, B atas->bawah, C diam di PE.
//  Tiap baris/kolom = 1 lorong INT8 terisolasi (tanpa bus bersama => zero-
//  contention). Wavefront: PE(i,j) menerima A[i][k], B[k][j] pada siklus k+i+j.
// =============================================================================
`timescale 1ns/1ps
module wt_systolic_array #(
    parameter N    = 62,
    parameter ACCW = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  clr,
    input  wire                  en,
    input  wire [N*8-1:0]        a_in,      // dari skew (kolom 0)
    input  wire [N*8-1:0]        b_in,      // dari skew (baris 0)
    output wire [N*N*ACCW-1:0]   acc_flat,
    output wire [N*N*5-1:0]      tgl_flat
);
    wire [8*N*(N+1)-1:0] a_bus;   // idx (i*(N+1)+j)*8
    wire [8*(N+1)*N-1:0] b_bus;   // idx (i*N+j)*8
    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin : g_in
            assign a_bus[(i*(N+1))*8 +: 8] = a_in[i*8 +: 8];
            assign b_bus[i*8 +: 8]         = b_in[i*8 +: 8];
        end
        for (i = 0; i < N; i = i + 1) begin : g_row
            for (j = 0; j < N; j = j + 1) begin : g_col
                wt_pe #(.ACCW(ACCW)) u_pe (
                    .clk(clk), .rst_n(rst_n), .clr(clr), .en(en),
                    .a_in (a_bus[(i*(N+1)+j)*8 +: 8]),
                    .b_in (b_bus[(i*N+j)*8 +: 8]),
                    .a_out(a_bus[(i*(N+1)+j+1)*8 +: 8]),
                    .b_out(b_bus[((i+1)*N+j)*8 +: 8]),
                    .acc  (acc_flat[(i*N+j)*ACCW +: ACCW]),
                    .tgl  (tgl_flat[(i*N+j)*5 +: 5])
                );
            end
        end
    endgenerate
endmodule
