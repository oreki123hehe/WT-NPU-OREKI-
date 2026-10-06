// =============================================================================
//  WT-NPU  |  wt_ice_wall_ctrl.sv  |  "Dinding Es" - clamp switching activity
//  Kontrol prediktif (PD): T_pred = Tmax + (Tmax - Tmax_prev) * 2^PRED_SH
//  Level 0..4 dengan histeresis; tiap level = pola duty-cycle 8 siklus:
//      L0 100% | L1 75% | L2 50% | L3 25% | L4 12.5%
//  Throttle bersifat global & sinkron (seluruh array + skew berhenti bersama),
//  sehingga hasil matriks TETAP benar - hanya latensi yang bertambah.
// =============================================================================
`timescale 1ns/1ps
module wt_ice_wall_ctrl #(
    parameter TW      = 16,
    parameter WARN    = 10240,
    parameter HOT     = 14080,
    parameter CRIT    = 16640,
    parameter EMER    = 19200,
    parameter HYST    = 512,
    parameter PRED_SH = 2
)(
    input  wire           clk,
    input  wire           rst_n,
    input  wire           tick,
    input  wire [TW-1:0]  tmax,
    output reg  [2:0]     level,
    output wire           adv_allow
);
    reg [TW-1:0] tprev;
    reg [2:0]    phase;
    reg [7:0]    mask;
    integer pred, itm, itp;

    function integer thr(input [2:0] lv);
        begin
            case (lv)
                3'd0:    thr = WARN;
                3'd1:    thr = HOT;
                3'd2:    thr = CRIT;
                default: thr = EMER;
            endcase
        end
    endfunction

    always @* begin
        case (level)
            3'd0:    mask = 8'hFF;
            3'd1:    mask = 8'hEE;
            3'd2:    mask = 8'hAA;
            3'd3:    mask = 8'h88;
            default: mask = 8'h80;
        endcase
    end
    assign adv_allow = mask[phase];

    always @(posedge clk) begin
        if (!rst_n) begin
            level <= 3'd0; tprev <= {TW{1'b0}}; phase <= 3'd0;
        end else begin
            phase <= phase + 3'd1;
            if (tick) begin
                itm  = tmax;
                itp  = tprev;
                pred = itm + ((itm - itp) <<< PRED_SH);
                if (pred < 0) pred = 0;
                tprev <= tmax;
                if (level < 3'd4 && pred >= thr(level))
                    level <= level + 3'd1;
                else if (level > 3'd0 && (pred + HYST) < thr(level - 3'd1))
                    level <= level - 3'd1;
            end
        end
    end
endmodule
