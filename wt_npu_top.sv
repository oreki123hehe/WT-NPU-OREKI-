// =============================================================================
//  WT-NPU  |  wt_npu_top.sv  |  Water-Turbo & Ice-Wall INT8 NPU (62 x 62)
//
//  Alur:  pkt{ID,data} -> lane_steer -> skew -> systolic NxN -> acc INT32
//         tgl -> zone activity -> thermal_fluid -> ice_wall_ctrl -> adv (stall)
//
//  Protokol host:
//    1. pulsa 'start' dengan k_len (>=1) saat busy=0
//    2. selama busy, host menyajikan kolom A[:,k_idx] dan baris B[k_idx,:]
//       sebagai paket {ID,data} per lorong (kombinasional terhadap k_idx)
//    3. tunggu 'done'; baca C baris demi baris lewat rd_row / rd_data
// =============================================================================
`timescale 1ns/1ps
module wt_npu_top #(
    parameter N             = 62,
    parameter IDW           = $clog2(N),
    parameter ZS            = 2,          // ukuran zona termal (N % ZS == 0)
    parameter TICK          = 16,
    parameter HEAT_K        = 3,
    parameter HEAT_SH       = 2,
    parameter COOL_SH       = 6,
    parameter DIFF_SH       = 3,
    parameter DIFF_SH_TURBO = 2,
    parameter TURBO_T       = 12000,
    parameter WARN          = 10240,      // 40 C  (Q8.8)
    parameter HOT           = 14080,      // 55 C
    parameter CRIT          = 16640,      // 65 C
    parameter EMER          = 19200,      // 75 C
    parameter HYST          = 512,
    parameter PRED_SH       = 2
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     start,
    input  wire [15:0]              k_len,
    output wire [15:0]              k_idx,
    input  wire [N*(IDW+8)-1:0]     a_pkt,
    input  wire [N*(IDW+8)-1:0]     b_pkt,
    input  wire [15:0]              rd_row,
    output wire [N*32-1:0]          rd_data,
    output wire                     busy,
    output wire                     done,
    // telemetri langsung
    output wire [2:0]               level,
    output wire [15:0]              tmax_live,
    output wire [15:0]              hot_zone,
    // statistik (snapshot saat selesai)
    output reg  [31:0]              stat_cycles,
    output reg  [31:0]              stat_stalled,
    output reg  [31:0]              stat_energy,
    output reg  [31:0]              stat_steer_fixed,
    output reg  [2:0]               stat_max_level,
    output reg  [15:0]              stat_tmax,
    output reg  [15:0]              stat_tavg,
    output reg  [2:0]               stat_level,
    output reg                      stat_steer_fault
);
    localparam NZ = N / ZS;
    localparam ZW = $clog2(ZS*ZS*16 + 1);
    localparam S_IDLE = 2'd0, S_CLR = 2'd1, S_RUN = 2'd2, S_DONE = 2'd3;

    reg  [1:0]  st;
    reg  [15:0] cnt;
    reg  [31:0] total;

    wire        ice_adv;
    wire        run        = (st == S_RUN);
    wire        clr        = (st == S_CLR);
    wire        adv        = run & ice_adv;
    wire        feed_valid = run & (cnt < k_len);

    assign k_idx = cnt;
    assign busy  = (st == S_CLR) | (st == S_RUN);
    assign done  = (st == S_DONE);

    // ---------------- auto-steering ----------------
    wire [N*8-1:0] a_lane, b_lane;
    wire [N-1:0]   a_lv, b_lv;
    wire [15:0]    a_mis, b_mis;
    wire           a_col, b_col, a_ide, b_ide;

    wt_lane_steer #(.N(N), .IDW(IDW), .W(8)) u_steer_a (
        .valid({N{feed_valid}}), .pkt(a_pkt), .lane_data(a_lane),
        .lane_valid(a_lv), .n_misrouted(a_mis), .collision(a_col), .id_err(a_ide));
    wt_lane_steer #(.N(N), .IDW(IDW), .W(8)) u_steer_b (
        .valid({N{feed_valid}}), .pkt(b_pkt), .lane_data(b_lane),
        .lane_valid(b_lv), .n_misrouted(b_mis), .collision(b_col), .id_err(b_ide));

    wire steer_bad = feed_valid & (a_col | b_col | a_ide | b_ide |
                                   (a_lv != {N{1'b1}}) | (b_lv != {N{1'b1}}));

    // ---------------- skew + array ----------------
    wire [N*8-1:0] a_sk, b_sk;
    wt_skew #(.N(N), .W(8)) u_skew_a (.clk(clk), .rst_n(rst_n), .clr(clr), .en(adv), .din(a_lane), .dout(a_sk));
    wt_skew #(.N(N), .W(8)) u_skew_b (.clk(clk), .rst_n(rst_n), .clr(clr), .en(adv), .din(b_lane), .dout(b_sk));

    wire [N*N*32-1:0] acc_flat;
    wire [N*N*5-1:0]  tgl_flat;
    wt_systolic_array #(.N(N), .ACCW(32)) u_array (
        .clk(clk), .rst_n(rst_n), .clr(clr), .en(adv),
        .a_in(a_sk), .b_in(b_sk), .acc_flat(acc_flat), .tgl_flat(tgl_flat));

    assign rd_data = acc_flat[rd_row*N*32 +: N*32];

    // ---------------- zona aktivitas ----------------
    reg [NZ*NZ*ZW-1:0] zact;
    reg [31:0]         zsum;
    integer zr, zc, dr, dc, s;
    always @* begin
        zsum = 32'd0;
        zact = {NZ*NZ*ZW{1'b0}};
        for (zr = 0; zr < NZ; zr = zr + 1)
            for (zc = 0; zc < NZ; zc = zc + 1) begin
                s = 0;
                for (dr = 0; dr < ZS; dr = dr + 1)
                    for (dc = 0; dc < ZS; dc = dc + 1)
                        s = s + tgl_flat[((zr*ZS+dr)*N + (zc*ZS+dc))*5 +: 5];
                zact[(zr*NZ+zc)*ZW +: ZW] = s;
                zsum = zsum + s;
            end
    end

    // ---------------- termal + ice wall ----------------
    wire        tick;
    wire [15:0] tmax, tavg;
    wt_thermal_fluid #(
        .NZ(NZ), .ZW(ZW), .TW(16), .TICK(TICK), .HEAT_K(HEAT_K), .HEAT_SH(HEAT_SH),
        .COOL_SH(COOL_SH), .DIFF_SH(DIFF_SH), .DIFF_SH_TURBO(DIFF_SH_TURBO), .TURBO_T(TURBO_T)
    ) u_fluid (.clk(clk), .rst_n(rst_n), .zact(zact), .tick_pulse(tick),
               .tmax(tmax), .tavg(tavg), .hot_zone(hot_zone));

    wt_ice_wall_ctrl #(
        .TW(16), .WARN(WARN), .HOT(HOT), .CRIT(CRIT), .EMER(EMER), .HYST(HYST), .PRED_SH(PRED_SH)
    ) u_ice (.clk(clk), .rst_n(rst_n), .tick(tick), .tmax(tmax), .level(level), .adv_allow(ice_adv));

    assign tmax_live = tmax;

    // ---------------- FSM & statistik ----------------
    always @(posedge clk) begin
        if (!rst_n) begin
            st <= S_IDLE; cnt <= 16'd0; total <= 32'd0;
            stat_cycles <= 0; stat_stalled <= 0; stat_energy <= 0; stat_steer_fixed <= 0;
            stat_max_level <= 0; stat_tmax <= 0; stat_tavg <= 0; stat_level <= 0;
            stat_steer_fault <= 1'b0;
        end else begin
            case (st)
                S_IDLE, S_DONE: begin
                    if (start) begin
                        st    <= S_CLR;
                        cnt   <= 16'd0;
                        total <= k_len + 2*N - 2;
                        stat_cycles <= 0; stat_stalled <= 0; stat_energy <= 0;
                        stat_steer_fixed <= 0; stat_max_level <= 0; stat_steer_fault <= 1'b0;
                    end
                end
                S_CLR: st <= S_RUN;
                S_RUN: begin
                    stat_cycles <= stat_cycles + 1;
                    if (!ice_adv) stat_stalled <= stat_stalled + 1;
                    if (level > stat_max_level) stat_max_level <= level;
                    if (feed_valid) stat_steer_fixed <= stat_steer_fixed + a_mis + b_mis;
                    if (steer_bad)  stat_steer_fault <= 1'b1;
                    if (adv) begin
                        stat_energy <= stat_energy + zsum;
                        if (cnt == total - 1) begin
                            st <= S_DONE;
                            stat_tmax <= tmax; stat_tavg <= tavg; stat_level <= level;
                        end else cnt <= cnt + 16'd1;
                    end
                end
            endcase
        end
    end
endmodule
