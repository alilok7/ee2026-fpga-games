`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// scorecard_render.v : the bowling scorecard overlay (top of the screen)
//-----------------------------------------------------------------------------
// Owner   : Student D
// Layout  : header row (3x5): P1/P2 and both totals; then two rows of five
//           frames, each frame a 19 x 14 px box:
//             top: frame number (left) and the mark boxes (right):
//                  2 boxes for frames 1-9, 3 for the 10th
//             bottom: running total, shown once that frame is known
//           Marks come ready-made from score_engine (X / - digits), totals
//           are turned into digits here (combinational double dabble).
// Shown   : automatically for 2 s after each frame, or toggled with
//           right-click / btnR.
//=============================================================================
module scorecard_render (
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire        show,
    input  wire        player,
    input  wire        two,
    output wire [4:0]  card_addr,        // {player, frame} -> score_engine
    input  wire [27:0] card_word,        // {known, total, mark0, mark1, mark2}
    input  wire [8:0]  game0, game1,
    output reg  [15:0] color,
    output reg         en,
    output reg  [`TX_W-1:0] txt
);
`include "txt_helpers.vh"
`include "bcd_fns.vh"


    // which frame box: x / 19 (5 boxes), y rows 7..20 and 22..35
    wire [2:0] kx = (px_x < 7'd19) ? 3'd0 : (px_x < 7'd38) ? 3'd1 : (px_x < 7'd57) ? 3'd2 :
                    (px_x < 7'd76) ? 3'd3 : 3'd4;
    wire [6:0] bx = px_x - {kx, 4'b0000} - {2'b00, kx, 1'b0} - {4'b0000, kx};   // x - 19 kx
    wire       r2 = (px_y >= 6'd22);
    wire [5:0] by = px_y - (r2 ? 6'd22 : 6'd7);                                 // 0..13
    wire [3:0] f  = (r2 ? 4'd5 : 4'd0) + {1'b0, kx};
    wire       in_card = (px_y >= 6'd7) && (px_y <= 6'd35) && !(px_y == 6'd21) && (px_x <= 7'd94);
    wire       box_line = (bx == 0) || (bx == 7'd18) || (by == 0) || (by == 6'd13);
    wire       tenth = (f == 4'd9);
    // mark boxes: frames 1-9 at bx 10..13, 14..17; 10th at 6..9, 10..13, 14..17
    wire       mark_row = (by >= 6'd1) && (by <= 6'd6);
    wire [1:0] mb = (bx >= 7'd14) ? (tenth ? 2'd2 : 2'd1) : (bx >= 7'd10) ? (tenth ? 2'd1 : 2'd0) : 2'd0;
    wire       in_mark = mark_row && (bx >= (tenth ? 7'd6 : 7'd10)) && (bx <= 7'd17);
    assign card_addr = {player, f};
    wire [5:0] mglyph = (mb == 2'd0) ? card_word[17:12] : (mb == 2'd1) ? card_word[11:6] : card_word[5:0];
    wire       f_ok   = card_word[27];
    wire [6:0] mx0 = (bx >= 7'd14) ? 7'd14 : (bx >= 7'd10) ? 7'd10 : 7'd6;
    wire [2:0] mfx = bx - mx0 - 7'd1;
    wire [11:0] tb = bcd9(card_word[26:18]);
    wire [11:0] g0b = bcd9(game0), g1b = bcd9(game1);
    wire [4:0]  hc  = px_x[6:2];                                   // header 3x5 column
    wire [2:0]  hfx = {1'b0, px_x[1:0]};
    wire [2:0]  hfy = px_y[2:0] - 3'd1;
    wire [6:0]  tdx = bx - 7'd5;                                   // total digits
    wire [1:0]  tdi = tdx[3:2];
    wire [2:0]  tfx = {1'b0, tdx[1:0]};
    function [5:0] dg3;                    // digit k of 3, leading zeros blank
        input [11:0] b; input [1:0] k;
        case (k)
            2'd0: dg3 = (b[11:8] == 0) ? 6'd0 : 6'd16 + b[11:8];
            2'd1: dg3 = (b[11:4] == 0) ? 6'd0 : 6'd16 + b[7:4];
            default: dg3 = 6'd16 + b[3:0];
        endcase
    endfunction

    always @(*) begin
        en = 1'b0; color = 16'h0841; txt = {`TX_W{1'b0}};
        if (show && px_y <= 6'd35) begin
            en = 1'b1;
            if (px_y < 6'd7) begin
                // header: P1 total   P2 total (current player highlighted)
                color = 16'h0109;
                if (px_y >= 6'd1 && px_y <= 6'd5) begin
                    case (hc)
                        5'd0:  txt = tx_l(6'd48, 1'b1, hfx, hfy, player ? 16'h8410 : `C_YELLOW, 0, 1'b0);
                        5'd1:  txt = tx_l(6'd17, 1'b1, hfx, hfy, player ? 16'h8410 : `C_YELLOW, 0, 1'b0);
                        5'd3, 5'd4, 5'd5: txt = tx_l(dg3(g0b, hc - 5'd3), 1'b1, hfx, hfy, `C_WHITE, 0, 1'b0);
                        5'd12: if (two) txt = tx_l(6'd48, 1'b1, hfx, hfy, player ? `C_CYAN : 16'h8410, 0, 1'b0);
                        5'd13: if (two) txt = tx_l(6'd18, 1'b1, hfx, hfy, player ? `C_CYAN : 16'h8410, 0, 1'b0);
                        5'd15, 5'd16, 5'd17: if (two) txt = tx_l(dg3(g1b, hc - 5'd15), 1'b1, hfx, hfy, `C_WHITE, 0, 1'b0);
                        default: ;
                    endcase
                end
            end else if (!in_card) begin
                color = 16'h0841;
            end else if (box_line) begin
                color = 16'h8410;
            end else begin
                color = `C_WHITE;
                // mark boxes have a thin grey frame line on their left / bottom
                if (in_mark && (bx == mx0 || by == 6'd6)) color = 16'hC618;
                else if (mark_row && bx >= 7'd1 && bx <= 7'd4 && by >= 6'd1 && by <= 6'd5) begin
                    // frame number (1..10) in the corner, 3x5 font
                    if (f == 4'd9) txt = tx_l(bx <= 7'd2 ? 6'd17 : 6'd16, 1'b1, (bx <= 7'd2) ? bx[2:0] - 3'd1 : bx[2:0] - 3'd3,
                                              by[2:0] - 3'd1, 16'h8410, 0, 1'b0);
                    else txt = tx_l(6'd17 + f, 1'b1, bx[2:0] - 3'd1, by[2:0] - 3'd1, 16'h8410, 0, 1'b0);
                end else if (in_mark && bx != mx0 && by >= 6'd1 && by <= 6'd5)
                    txt = tx_l(mglyph, 1'b1, mfx, by[2:0] - 3'd1,
                               (mglyph == 6'd56) ? `C_RED : (mglyph == 6'd15) ? 16'h001F : `C_BLACK, 0, 1'b0);
                else if (by >= 6'd8 && by <= 6'd12 && bx >= 7'd5 && bx <= 7'd16 && f_ok)
                    // running total: 3 digits of 4 px at bx 5..16
                    txt = tx_l(dg3(tb, tdi), 1'b1, tfx, by[2:0] - 3'd0, `C_BLACK, 0, 1'b0);
            end
        end
    end
endmodule
