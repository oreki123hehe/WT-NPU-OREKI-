// =============================================================================
//  WT-NPU  |  wt_lane_steer.sv  |  Gerbang Lorong Anti-Nyasar (Auto-Steering)
//  Tiap paket = {Channel ID (IDW bit), data INT8}. Paket di slot fisik i yang
//  ber-ID j otomatis dituntun ke lorong j (crossbar berbasis ID).
//   - n_misrouted : jumlah paket yang slot fisiknya != ID (dikoreksi)
//   - collision   : >1 paket menuju lorong yang sama (data lorong dibuang=0)
//   - id_err      : ID di luar rentang [0,N-1]
// =============================================================================
`timescale 1ns/1ps
module wt_lane_steer #(
    parameter N   = 62,
    parameter IDW = 6,
    parameter W   = 8
)(
    input  wire [N-1:0]            valid,
    input  wire [N*(IDW+W)-1:0]    pkt,
    output reg  [N*W-1:0]          lane_data,
    output reg  [N-1:0]            lane_valid,
    output reg  [15:0]             n_misrouted,
    output reg                     collision,
    output reg                     id_err
);
    localparam PW = IDW + W;
    integer i, j, cnt;
    reg [IDW-1:0] id;

    always @* begin
        lane_data   = {N*W{1'b0}};
        lane_valid  = {N{1'b0}};
        n_misrouted = 16'd0;
        collision   = 1'b0;
        id_err      = 1'b0;
        for (j = 0; j < N; j = j + 1) begin
            cnt = 0;
            for (i = 0; i < N; i = i + 1) begin
                id = pkt[i*PW + W +: IDW];
                if (valid[i] && (id == j)) begin
                    lane_data[j*W +: W] = pkt[i*PW +: W];
                    cnt = cnt + 1;
                end
            end
            if (cnt > 1) begin
                collision = 1'b1;
                lane_data[j*W +: W] = {W{1'b0}};
            end
            lane_valid[j] = (cnt == 1);
        end
        for (i = 0; i < N; i = i + 1) begin
            id = pkt[i*PW + W +: IDW];
            if (valid[i]) begin
                if (id != i) n_misrouted = n_misrouted + 16'd1;
                if (id >= N) id_err = 1'b1;
            end
        end
    end
endmodule
