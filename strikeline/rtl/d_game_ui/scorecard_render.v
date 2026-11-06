`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// scorecard_render.v : the bowling scorecard overlay (top of the screen)
//-----------------------------------------------------------------------------
// Owner   : Student C (v3.5 team split; before: Student D)
// Layout  : header row (3x5): P1/P2 and both totals; then two rows of five
//           frames, each frame a 19 px wide box:
//             top: frame number (left) and the mark boxes (right):
//                  2 boxes for frames 1-9, 3 for the 10th
//             bottom: running total, shown once that frame is known
//           Marks come ready-made from score_engine (X / - digits), totals
//           are turned into digits here (combinational double dabble).
// Shown   : automatically for 2 s after each frame, or toggled with
//           right-click / btnR.
// Tall    : (the OLED during a game) the card fills all 64 rows: header
//           0..9, frame rows 10..36 and 37..63 (marks on top, the running
//           total lower down). Normal: header 0..6, rows 7..20 and 22..35.
//=============================================================================
module scorecard_render (
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire        show,
    input  wire        tall,             // full-screen layout (OLED)
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

    // ---------- 1. Colours ----------
    localparam [15:0] GREY       = 16'h8410;
    localparam [15:0] BACKGROUND = 16'h0841;
    localparam [15:0] HEADER     = 16'h0109;

    // ---------- 2. Which frame box, and the pixel inside it ----------
    wire [2:0] KX = (px_x < 7'd19) ? 3'd0 :              // box column = x / 19
                    (px_x < 7'd38) ? 3'd1 :
                    (px_x < 7'd57) ? 3'd2 :
                    (px_x < 7'd76) ? 3'd3 :
                                     3'd4;
    wire [6:0] BX = px_x - 7'd19 * KX;

    wire [5:0] ROW1_Y  = tall ? 6'd10 : 6'd7;           // first box row
    wire [5:0] ROW2_Y  = tall ? 6'd37 : 6'd22;          // second box row
    wire [5:0] END_Y   = tall ? 6'd63 : 6'd35;          // last row of the card
    wire [5:0] BOX_H   = tall ? 6'd26 : 6'd13;          // last row inside a box
    wire [5:0] TOTAL_Y = tall ? 6'd15 : 6'd8;           // running total, 5 rows from here
    wire [2:0] HEAD_Y  = tall ? 3'd3 : 3'd1;            // header text row

    wire       ROW2  = (px_y >= ROW2_Y);
    wire [5:0] BY    = px_y - (ROW2 ? ROW2_Y : ROW1_Y); // 0..BOX_H
    wire [3:0] F     = (ROW2 ? 4'd5 : 4'd0) + {1'b0, KX};
    wire       TENTH = (F == 4'd9);
    wire       IN_CARD  = (px_y >= ROW1_Y) && (px_y <= END_Y) && !(!tall && px_y == 6'd21) && (px_x <= 7'd94);
    wire       BOX_LINE = (BX == 0) || (BX == 7'd18) || (BY == 0) || (BY == BOX_H);
    assign card_addr = {player, F};

    // ---------- 3. Mark boxes: frames 1-9 at BX 10..13, 14..17; the 10th at 6..9, 10..13, 14..17 ----------
    wire       MARK_ROW = (BY >= 6'd1) && (BY <= 6'd6);
    wire       IN_MARK  = MARK_ROW && (BX >= (TENTH ? 7'd6 : 7'd10)) && (BX <= 7'd17);
    wire [1:0] MARK_NO  = (BX >= 7'd14) ? (TENTH ? 2'd2 : 2'd1) :
                          (BX >= 7'd10) ? (TENTH ? 2'd1 : 2'd0) :
                                          2'd0;
    wire [6:0] MARK_X0  = (BX >= 7'd14) ? 7'd14 :       // left edge of this mark box
                          (BX >= 7'd10) ? 7'd10 :
                                          7'd6;
    wire [2:0] MARK_FX  = BX - MARK_X0 - 7'd1;
    wire [5:0] MARK_GLYPH = (MARK_NO == 2'd0) ? card_word[17:12] :
                            (MARK_NO == 2'd1) ? card_word[11:6]  :
                                                card_word[5:0];
    wire       FRAME_KNOWN = card_word[27];

    // ---------- 4. Digits ----------
    wire [11:0] TOTAL_BCD = bcd9(card_word[26:18]);
    wire [11:0] GAME0_BCD = bcd9(game0);
    wire [11:0] GAME1_BCD = bcd9(game1);
    wire [4:0]  HEAD_COL  = px_x[6:2];                  // header 3x5 column
    wire [2:0]  HEAD_FX   = {1'b0, px_x[1:0]};
    wire [2:0]  HEAD_FY   = px_y[2:0] - HEAD_Y;
    wire [15:0] P1_COLOUR = player ? GREY : `C_YELLOW;  // current player highlighted
    wire [15:0] P2_COLOUR = player ? `C_CYAN : GREY;
    wire [5:0]  TOTAL_FY  = BY - TOTAL_Y;               // running total: 3 digits of 4 px at BX 5..16
    wire [6:0]  TOTAL_DX  = BX - 7'd5;

    // digit K of 3, leading zeros blank
    function [5:0] DIGIT3;
        input [11:0] B;
        input [1:0]  K;
        case (K)
            2'd0:    DIGIT3 = (B[11:8] == 0) ? 6'd0 : 6'd16 + B[11:8];
            2'd1:    DIGIT3 = (B[11:4] == 0) ? 6'd0 : 6'd16 + B[7:4];
            default: DIGIT3 = 6'd16 + B[3:0];
        endcase
    endfunction

    // ---------- 5. Pixel colour and text ----------
    always @ (*) begin
        en = 1'b0;
        color = BACKGROUND;
        txt = {`TX_W{1'b0}};
        if (show && px_y <= END_Y) begin
            en = 1'b1;
            if (px_y < ROW1_Y) begin
                // header: P1 total   P2 total
                color = HEADER;
                if (px_y >= {3'd0, HEAD_Y} && px_y <= {3'd0, HEAD_Y} + 6'd4) begin
                    case (HEAD_COL)
                        5'd0:  txt = tx_l(6'd48, 1'b1, HEAD_FX, HEAD_FY, P1_COLOUR, 0, 1'b0);     // P
                        5'd1:  txt = tx_l(6'd17, 1'b1, HEAD_FX, HEAD_FY, P1_COLOUR, 0, 1'b0);     // 1
                        5'd3, 5'd4, 5'd5:
                               txt = tx_l(DIGIT3(GAME0_BCD, HEAD_COL - 5'd3), 1'b1, HEAD_FX, HEAD_FY, `C_WHITE, 0, 1'b0);
                        5'd12: if (two) txt = tx_l(6'd48, 1'b1, HEAD_FX, HEAD_FY, P2_COLOUR, 0, 1'b0);   // P
                        5'd13: if (two) txt = tx_l(6'd18, 1'b1, HEAD_FX, HEAD_FY, P2_COLOUR, 0, 1'b0);   // 2
                        5'd15, 5'd16, 5'd17:
                               if (two) txt = tx_l(DIGIT3(GAME1_BCD, HEAD_COL - 5'd15), 1'b1, HEAD_FX, HEAD_FY, `C_WHITE, 0, 1'b0);
                        default: ;
                    endcase
                end
            end
            else if (IN_CARD) begin
                if (BOX_LINE)
                    color = GREY;
                else begin
                    color = `C_WHITE;
                    // mark boxes have a thin grey line on their left / bottom
                    if (IN_MARK && (BX == MARK_X0 || BY == 6'd6))
                        color = 16'hC618;
                    // frame number (1..10) in the corner
                    else if (MARK_ROW && BX >= 7'd1 && BX <= 7'd4 && BY >= 6'd1 && BY <= 6'd5) begin
                        if (TENTH)
                            txt = tx_l(BX <= 7'd2 ? 6'd17 : 6'd16, 1'b1,
                                       (BX <= 7'd2) ? BX[2:0] - 3'd1 : BX[2:0] - 3'd3,
                                       BY[2:0] - 3'd1, GREY, 0, 1'b0);
                        else
                            txt = tx_l(6'd17 + F, 1'b1, BX[2:0] - 3'd1, BY[2:0] - 3'd1, GREY, 0, 1'b0);
                    end
                    // marks: X red, / blue, others black
                    else if (IN_MARK && BY >= 6'd1 && BY <= 6'd5)
                        txt = tx_l(MARK_GLYPH, 1'b1, MARK_FX, BY[2:0] - 3'd1,
                                   (MARK_GLYPH == 6'd56) ? `C_RED :
                                   (MARK_GLYPH == 6'd15) ? 16'h001F :
                                                           `C_BLACK, 0, 1'b0);
                    // running total, once the frame is known
                    else if (BY >= TOTAL_Y && BY <= TOTAL_Y + 6'd4 && BX >= 7'd5 && BX <= 7'd16 && FRAME_KNOWN)
                        txt = tx_l(DIGIT3(TOTAL_BCD, TOTAL_DX[3:2]), 1'b1, {1'b0, TOTAL_DX[1:0]},
                                   TOTAL_FY[2:0], `C_BLACK, 0, 1'b0);
                end
            end
        end
    end
endmodule
