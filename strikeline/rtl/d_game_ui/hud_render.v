`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// hud_render.v : in-game overlays (above the lane, pins, ball and A's layer)
//-----------------------------------------------------------------------------
// Owner   : Student C (v3.5 team split; before: Student D)
// Panel (x 70..95, y 0..35): player + frame, running score (5x7), ball number,
//   and a live pin diagram (red = standing).
// Lane overlays:
//   popup   STRIKE! SPARE! GUTTER SPLIT! TURKEY! DOUBLE! / "n PINS" in a
//           flashing box, ~1.5 s
//   banner  "FRAME n" when a frame starts
//   paused  banner + "SW0 TO RESUME"
//   hint    bottom row: what to do now (GRAB + FLICK UP, LET GO = THROW,
//           M-CLK: REPLAY), or SAVING while the flash is written
//   ghost   first throw of a game: a dot shows the swipe, curving like a hook
// (The Spare Challenge is not in v3.5: leave_idx, spare_made and spare_tries
//  are not used.)
//=============================================================================
module hud_render (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire [`GS_W-1:0] game_state,
    input  wire [`SET_W-1:0] settings,
    input  wire [`PK_W-1:0] kind,
    input  wire        player,
    input  wire [3:0]  frame,
    input  wire [1:0]  ball_no,
    input  wire [8:0]  score,            // current player's known total
    input  wire [9:0]  pins_standing,
    input  wire [3:0]  popup_id,
    input  wire [3:0]  popup_n,
    input  wire        banner,
    input  wire        ghost,
    input  wire        grabbing,
    input  wire        paused,
    input  wire        saving,
    input  wire [2:0]  leave_idx,
    input  wire [7:0]  spare_made,
    input  wire [7:0]  spare_tries,
    input  wire [15:0] stance_x,
    output reg  [15:0] color,
    output reg         en,
    output reg  [`TX_W-1:0] txt
);
`include "txt_helpers.vh"
`include "strings_map.vh"
`include "bcd_fns.vh"

    // ---------- 1. Colours ----------
    localparam [15:0] PANEL = 16'h0841;
    localparam [15:0] W     = `C_WHITE;
    localparam [15:0] Y     = `C_YELLOW;

    // ---------- 2. Frame counter (animations) ----------
    reg [7:0] FRAME_COUNT;
    always @ (posedge clk) begin
        if (rst)
            FRAME_COUNT <= 0;
        else if (tick_frame && !paused)
            FRAME_COUNT <= FRAME_COUNT + 8'd1;
    end

    // ---------- 3. Text cells: 5x7 (6 x 8 px) and 3x5 (4 x 6 px) ----------
    wire [3:0]  COL   = c6(px_x);
    wire [2:0]  FX    = f6(px_x);
    wire [2:0]  ROW   = px_y[5:3];
    wire [2:0]  FY    = px_y[2:0];
    wire [4:0]  MCOL  = px_x[6:2];
    wire [2:0]  MFX   = {1'b0, px_x[1:0]};
    wire [12:0] MY43  = px_y * 6'd43;
    wire [3:0]  MROW  = MY43[11:8];                       // px_y / 6
    wire [5:0]  MFY6  = px_y - {MROW, 2'b00} - {1'b0, MROW, 1'b0};
    wire [2:0]  MFY   = MFY6[2:0];

    // ---------- 4. Values shown ----------
    wire        IN_GAME   = (game_state >= `GS_AIM && game_state <= `GS_SWEEP) || game_state == `GS_REPLAY;
    wire [11:0] SCORE_BCD = bcd9(score);
    wire [4:0]  FRAME_NO  = {1'b0, frame} + 5'd1;         // 1..10
    wire        FRAME_10  = (FRAME_NO >= 5'd10);
    wire [5:0]  FRAME_LAST_DIGIT = 6'd16 + (FRAME_10 ? 6'd0 : {2'b00, FRAME_NO[3:0]});
    wire [15:0] PLAYER_COLOUR = player ? `C_CYAN : Y;

    // ---------- 5. Pin diagram dots (2 x 2 px): 7 8 9 10 / 4 5 6 / 2 3 / 1 ----------
    reg       PIN_DOT;
    reg [3:0] PIN_K;
    always @ (*) begin
        PIN_DOT = 1'b0;
        PIN_K = 4'd0;
        if (px_y[5:1] == 5'd12) begin                         // y 24..25
            if (px_x[6:1] == 6'd37) begin PIN_DOT = 1; PIN_K = 6; end
            if (px_x[6:1] == 6'd40) begin PIN_DOT = 1; PIN_K = 7; end
            if (px_x[6:1] == 6'd43) begin PIN_DOT = 1; PIN_K = 8; end
            if (px_x[6:1] == 6'd46) begin PIN_DOT = 1; PIN_K = 9; end
        end
        else if (px_y == 6'd27 || px_y == 6'd28) begin
            if (px_x == 7'd77 || px_x == 7'd78) begin PIN_DOT = 1; PIN_K = 3; end
            if (px_x == 7'd83 || px_x == 7'd84) begin PIN_DOT = 1; PIN_K = 4; end
            if (px_x == 7'd89 || px_x == 7'd90) begin PIN_DOT = 1; PIN_K = 5; end
        end
        else if (px_y[5:1] == 5'd15) begin                    // y 30..31
            if (px_x[6:1] == 6'd40) begin PIN_DOT = 1; PIN_K = 1; end
            if (px_x[6:1] == 6'd43) begin PIN_DOT = 1; PIN_K = 2; end
        end
        else if (px_y == 6'd33 || px_y == 6'd34) begin
            if (px_x == 7'd83 || px_x == 7'd84) begin PIN_DOT = 1; PIN_K = 0; end
        end
    end

    // ---------- 6. Popup box (lane, y 22..33) ----------
    wire IN_BOX   = (px_x >= 7'd4) && (px_x <= 7'd55) && (px_y >= 6'd22) && (px_y <= 6'd33);
    wire BOX_EDGE = IN_BOX && (px_x == 7'd4 || px_x == 7'd55 || px_y == 6'd22 || px_y == 6'd33);
    reg [15:0] POPUP_COLOUR;
    always @ (*) begin
        case (popup_id)
            4'd0, 4'd4, 4'd5: POPUP_COLOUR = FRAME_COUNT[2] ? 16'hFD20 : `C_MAGENTA;   // strike / turkey / double flash
            4'd1:             POPUP_COLOUR = 16'h03EF;                                 // spare
            4'd3:             POPUP_COLOUR = `C_ORANGE;                                // split
            4'd2:             POPUP_COLOUR = 16'h630C;                                 // gutter
            default:          POPUP_COLOUR = 16'h0019;                                 // n pins
        endcase
    end
    wire SHOW_POPUP  = (popup_id != 4'd15) && (game_state == `GS_RESULT);
    wire SHOW_BANNER = banner && !SHOW_POPUP && (game_state == `GS_AIM || game_state == `GS_SWEEP);

    // ---------- 7. Ghost swipe: a dot that travels 40 rows up from the ball, drifting left ----------
    wire [5:0] GHOST_T = FRAME_COUNT[6:1];                         // 0..63, 2 frames per step
    wire [6:0] GHOST_X = stance_x[12:6] - {3'd0, GHOST_T[5:2]} * {3'd0, GHOST_T[5:4]} / 7'd2;
    wire [5:0] GHOST_Y = 6'd44 - {1'b0, GHOST_T[5:1]} - {2'b00, GHOST_T[5:2]};   // 44 .. ~0
    wire GHOST_DOT = ghost && game_state == `GS_AIM && !grabbing && GHOST_T < 6'd48 &&
                     (px_x == GHOST_X || px_x == GHOST_X + 7'd1) &&
                     (px_y == GHOST_Y || px_y == GHOST_Y + 6'd1);

    // ---------- 8. Pixel colour and text ----------
    always @ (*) begin
        en = 1'b0;
        color = PANEL;
        txt = {`TX_W{1'b0}};
        if (IN_GAME) begin
            // panel
            if (px_x >= 7'd70 && px_y < `SCR_MTR_Y0) begin
                en = 1'b1;
                color = (px_x == 7'd70) ? 16'h4208 : PANEL;
                if (PIN_DOT)
                    color = pins_standing[PIN_K] ? `C_RED : 16'h31A6;

                if (MROW == 4'd0)                                      // P1 / P2, F n
                    case (MCOL)
                        5'd18: if (kind[`PK_TWO]) txt = tx_l(6'd48, 1'b1, MFX, MFY, PLAYER_COLOUR, 0, 1'b0);
                        5'd19: if (kind[`PK_TWO]) txt = tx_l(player ? 6'd18 : 6'd17, 1'b1, MFX, MFY, PLAYER_COLOUR, 0, 1'b0);
                        5'd21: txt = tx_l(6'd38, 1'b1, MFX, MFY, W, 0, 1'b0);
                        5'd22: if (FRAME_10) txt = tx_l(6'd17, 1'b1, MFX, MFY, W, 0, 1'b0);
                        5'd23: txt = tx_l(FRAME_LAST_DIGIT, 1'b1, MFX, MFY, W, 0, 1'b0);
                        default: ;
                    endcase
                else if (ROW == 3'd1 && COL >= 4'd13)                  // score, leading zeros blank
                    txt = tx_l((COL == 4'd13) ? (SCORE_BCD[11:8] == 0 ? 6'd0 : dig(SCORE_BCD[11:8])) :
                               (COL == 4'd14) ? (SCORE_BCD[11:4] == 0 ? 6'd0 : dig(SCORE_BCD[7:4])) :
                                                dig(SCORE_BCD[3:0]),
                               1'b0, FX, FY, Y, 0, 1'b0);
                else if (MROW == 4'd3) begin                           // BALL n
                    if (MCOL >= 5'd18 && MCOL < 5'd22)
                        txt = tx_s(`S_BALLW + MCOL - 5'd18, 1'b1, MFX, MFY, 16'hAD55, 0, 1'b0);
                    else if (MCOL == 5'd23)
                        txt = tx_l(dig({2'b00, ball_no} + 4'd1), 1'b1, MFX, MFY, W, 0, 1'b0);
                end
            end

            // lane overlays
            else if (px_x < `SCR_LANE_W) begin
                if (paused && IN_BOX) begin
                    en = 1'b1;
                    color = BOX_EDGE ? W : 16'h0010;
                    if (ROW == 3'd3 && COL >= 4'd2 && COL < 4'd8)
                        txt = tx_s(`S_HINT + 11'd60 + COL - 4'd2, 1'b0, FX, FY, W, 0, 1'b0);
                end
                else if (SHOW_POPUP && IN_BOX) begin
                    en = 1'b1;
                    color = BOX_EDGE ? W : POPUP_COLOUR;
                    if (ROW == 3'd3) begin
                        if (popup_id == 4'd8) begin                    // n PINS
                            if (COL == 4'd2)
                                txt = tx_l(dig(popup_n), 1'b0, FX, FY, W, 0, 1'b0);
                            else if (COL >= 4'd4 && COL < 4'd8)
                                txt = tx_s(`S_POP + 11'd64 + COL - 4'd4, 1'b0, FX, FY, W, 0, 1'b0);
                        end
                        else if (COL >= 4'd1 && COL < 4'd9)
                            txt = tx_s(`S_POP + {popup_id, 3'd0} + COL - 4'd1, 1'b0, FX, FY, W, 0, 1'b0);
                    end
                end
                else if (SHOW_BANNER && IN_BOX) begin
                    en = 1'b1;
                    color = BOX_EDGE ? 16'h8410 : 16'h0109;
                    if (ROW == 3'd3) begin                             // FRAME n
                        if (COL >= 4'd1 && COL < 4'd6)
                            txt = tx_s(`S_POP + 11'd72 + COL - 4'd1, 1'b0, FX, FY, W, 0, 1'b0);
                        else if (COL == 4'd7 && FRAME_10)
                            txt = tx_l(6'd17, 1'b0, FX, FY, Y, 0, 1'b0);
                        else if (COL == 4'd8)
                            txt = tx_l(FRAME_LAST_DIGIT, 1'b0, FX, FY, Y, 0, 1'b0);
                    end
                end
                else if (GHOST_DOT) begin
                    en = 1'b1;
                    color = GHOST_T[2] ? W : 16'hBDF7;
                end

                // hint row (3x5, y 54..59): saving > paused > what to do now
                if (MROW == 4'd9 && MCOL < 5'd15) begin
                    if (saving && FRAME_COUNT[4])
                        txt = tx_s(`S_HINT + 11'd90 + MCOL, 1'b1, MFX, MFY, `C_ORANGE, `C_BLACK, MCOL < 5'd6);
                    else if (paused)
                        txt = tx_s(`S_HINT + 11'd105 + MCOL, 1'b1, MFX, MFY, W, `C_BLACK, MCOL < 5'd13);
                    else
                        case (game_state)
                            `GS_AIM:    txt = tx_s(`S_HINT + MCOL,          1'b1, MFX, MFY, W, `C_BLACK, 1'b1);
                            `GS_THROW:  txt = tx_s(`S_HINT + 11'd15 + MCOL, 1'b1, MFX, MFY, Y, `C_BLACK, MCOL < 5'd14);
                            `GS_RESULT: txt = tx_s(`S_HINT + 11'd30 + MCOL, 1'b1, MFX, MFY, 16'hAD55, `C_BLACK, MCOL < 5'd13);
                            `GS_REPLAY: if (FRAME_COUNT[4])
                                            txt = tx_s(`S_HINT + 11'd75 + MCOL, 1'b1, MFX, MFY, `C_RED, `C_BLACK, MCOL < 5'd6);
                            default: ;
                        endcase
                end
            end
        end
    end
endmodule
