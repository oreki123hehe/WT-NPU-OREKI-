// =============================================================================
//  WT-NPU  |  wt_thermal_fluid.sv  |  "Virtual Fluid" - estimator termal 2-D
//  Persamaan panas diskret per zona (NZ x NZ), integer fixed-point Q8.8 (C):
//
//    T'[z] = T[z] + (E[z]*HEAT_K >> HEAT_SH)            (sumber panas)
//                 + (sum_{n in N4(z)} (T[n]-T[z])) >>> s  (difusi / aliran fluida)
//                 - (T[z] >> COOL_SH)                     (pendinginan ke ambient)
//
//  E[z]  = akumulasi switching activity zona selama TICK siklus.
//  Tetangga di luar grid = reservoir ambient (T=0) -> tepi chip jadi "zona
//  penampung/pembuang". Turbo-flow: jika Tmax > TURBO_T, laju difusi naik
//  (s: DIFF_SH -> DIFF_SH_TURBO). Stabilitas eksplisit: 4/2^s <= 1  (s>=2).
// =============================================================================
`timescale 1ns/1ps
module wt_thermal_fluid #(
    parameter NZ            = 31,
    parameter ZW            = 7,
    parameter TW            = 16,
    parameter TICK          = 16,
    parameter HEAT_K        = 3,
    parameter HEAT_SH       = 2,
    parameter COOL_SH       = 6,
    parameter DIFF_SH       = 3,
    parameter DIFF_SH_TURBO = 2,
    parameter TURBO_T       = 12000
)(
    input  wire                   clk,
    input  wire                   rst_n,
    input  wire [NZ*NZ*ZW-1:0]    zact,
    output reg                    tick_pulse,
    output reg  [TW-1:0]          tmax,
    output reg  [TW-1:0]          tavg,
    output reg  [15:0]            hot_zone
);
    localparam NZZ = NZ*NZ;
    localparam [TW-1:0] TMAXV = {TW{1'b1}};

    reg [TW-1:0] T   [0:NZZ-1];
    reg [31:0]   acc [0:NZZ-1];
    reg [15:0]   tcnt;

    integer z, zr, zc, dsh;
    integer t, up, dn, lf, rt, lap, heat, dT, nt, mx, sm, mxz;
    reg [31:0] ze;

    always @(posedge clk) begin
        if (!rst_n) begin
            tcnt <= 16'd0; tick_pulse <= 1'b0;
            tmax <= {TW{1'b0}}; tavg <= {TW{1'b0}}; hot_zone <= 16'd0;
            for (z = 0; z < NZZ; z = z + 1) begin
                T[z] <= {TW{1'b0}}; acc[z] <= 32'd0;
            end
        end else begin
            tick_pulse <= 1'b0;
            if (tcnt == TICK-1) begin
                tcnt <= 16'd0;
                tick_pulse <= 1'b1;
                dsh = (tmax > TURBO_T) ? DIFF_SH_TURBO : DIFF_SH;
                mx = 0; sm = 0; mxz = 0;
                for (zr = 0; zr < NZ; zr = zr + 1) begin
                    for (zc = 0; zc < NZ; zc = zc + 1) begin
                        z  = zr*NZ + zc;
                        t  = T[z];
                        up = 0; dn = 0; lf = 0; rt = 0;
                        if (zr > 0)      up = T[z-NZ];
                        if (zr < NZ-1)   dn = T[z+NZ];
                        if (zc > 0)      lf = T[z-1];
                        if (zc < NZ-1)   rt = T[z+1];
                        lap  = up + dn + lf + rt - 4*t;
                        ze   = acc[z] + zact[z*ZW +: ZW];
                        heat = (ze * HEAT_K) >> HEAT_SH;
                        dT   = heat + (lap >>> dsh) - (t >>> COOL_SH);
                        nt   = t + dT;
                        if (nt < 0)     nt = 0;
                        if (nt > TMAXV) nt = TMAXV;
                        T[z]   <= nt;
                        acc[z] <= 32'd0;
                        sm = sm + nt;
                        if (nt > mx) begin mx = nt; mxz = z; end
                    end
                end
                tmax     <= mx;
                tavg     <= sm / NZZ;
                hot_zone <= mxz;
            end else begin
                tcnt <= tcnt + 16'd1;
                for (z = 0; z < NZZ; z = z + 1)
                    acc[z] <= acc[z] + zact[z*ZW +: ZW];
            end
        end
    end
endmodule
