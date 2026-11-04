`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// hud_render.v : in-game overlays (above the lane, pins, ball and A's layer)
//-----------------------------------------------------------------------------
// Owner   : Student D
// Panel (x 70..95, y 0..35): player + frame, running score (5x7), ball number,
//   and a live pin diagram (red = standing). Spare Challenge shows the leave
//   and "made / tries" instead.
// Lane overlays:
//   popup   STRIKE! SPARE! GUTTER SPLIT! TURKEY! DOUBLE! / "n PINS" (Spare
//           Challenge: CLEARED! / MISSED) in a flashing box, ~1.5 s
//   banner  "FRAME n" (and P1/P2) when a frame starts
//   paused  banner + "SW0 TO RESUME"
//   hint    bottom row: what to do now (GRAB + FLICK UP, LET GO = THROW,
//           M-CLK: REPLAY), or SAVING while the flash is written
//   ghost   first throw of a game: a dot shows the swipe, curving like a hook
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

    reg [7:0] fr;
    always @(posedge clk) if (rst) fr <= 0; else if (tick_frame && !paused) fr <= fr + 8'd1;

    wire [3:0] col = c6(px_x);
    wire [2:0] fx  = f6(px_x);
    wire [2:0] row = px_y[5:3];
    wire [2:0] fy  = px_y[2:0];
    wire [4:0] mcol = px_x[6:2];
    wire [2:0] mfx  = {1'b0, px_x[1:0]};
    wire [12:0] my43 = px_y * 6'd43;
    wire [3:0] mrow = my43[11:8];
    wire [5:0] mfy6 = px_y - {mrow, 2'b00} - {1'b0, mrow, 1'b0};
    wire [2:0] mfy  = mfy6[2:0];

    wire in_game = (game_state >= `GS_AIM && game_state <= `GS_SWEEP) || game_state == `GS_REPLAY;
    wire spare   = kind[`PK_SPARE];
    wire [11:0] sb  = bcd9(score);
    wire [11:0] smb = bcd9({1'b0, spare_made});
    wire [11:0] stb = bcd9({1'b0, spare_tries});
    wire [4:0]  fno = {1'b0, frame} + 5'd1;               // 1..10
    localparam [15:0] PANEL = 16'h0841, W = `C_WHITE, Y = `C_YELLOW;

    // pin diagram dots (2 x 2 px): 7 8 9 10 / 4 5 6 / 2 3 / 1
    reg pin_dot; reg [3:0] pin_k;
    always @(*) begin
        pin_dot = 1'b0; pin_k = 4'd0;
        if (px_y[5:1] == 5'd12) begin                         // y 24..25
            if (px_x[6:1] == 6'd37) begin pin_dot = 1; pin_k = 6; end
            if (px_x[6:1] == 6'd40) begin pin_dot = 1; pin_k = 7; end
            if (px_x[6:1] == 6'd43) begin pin_dot = 1; pin_k = 8; end
            if (px_x[6:1] == 6'd46) begin pin_dot = 1; pin_k = 9; end
        end else if (px_y == 6'd27 || px_y == 6'd28) begin
            if (px_x == 7'd77 || px_x == 7'd78) begin pin_dot = 1; pin_k = 3; end
            if (px_x == 7'd83 || px_x == 7'd84) begin pin_dot = 1; pin_k = 4; end
            if (px_x == 7'd89 || px_x == 7'd90) begin pin_dot = 1; pin_k = 5; end
        end else if (px_y[5:1] == 5'd15) begin                // y 30..31
            if (px_x[6:1] == 6'd40) begin pin_dot = 1; pin_k = 1; end
            if (px_x[6:1] == 6'd43) begin pin_dot = 1; pin_k = 2; end
        end else if (px_y == 6'd33 || px_y == 6'd34) begin
            if (px_x == 7'd83 || px_x == 7'd84) begin pin_dot = 1; pin_k = 0; end
        end
    end

    // popup box (lane, y 22..33)
    wire in_box = (px_x >= 7'd4) && (px_x <= 7'd55) && (px_y >= 6'd22) && (px_y <= 6'd33);
    wire box_edge = in_box && (px_x == 7'd4 || px_x == 7'd55 || px_y == 6'd22 || px_y == 6'd33);
    reg [15:0] pop_col;
    always @(*) begin
        case (popup_id)
            4'd0, 4'd4, 4'd5: pop_col = fr[2] ? 16'hFD20 : `C_MAGENTA;   // strike family flashes
            4'd1, 4'd6:       pop_col = 16'h03EF;                        // spare / cleared
            4'd3:             pop_col = `C_ORANGE;                       // split
            4'd2, 4'd7:       pop_col = 16'h630C;                        // gutter / missed
            default:          pop_col = 16'h0019;                        // n pins
        endcase
    end
    wire show_pop    = (popup_id != 4'd15) && (game_state == `GS_RESULT);
    wire show_banner = banner && !show_pop && (game_state == `GS_AIM || game_state == `GS_SWEEP) && !spare;

    // ghost swipe: a dot that travels 40 rows up from the ball, drifting left
    wire [5:0] gt = fr[6:1];                                       // 0..63, 2 frames per step
    wire [6:0] gx = stance_x[12:6] - {3'd0, gt[5:2]} * {3'd0, gt[5:4]} / 7'd2;
    wire [5:0] gy = 6'd44 - {1'b0, gt[5:1]} - {2'b00, gt[5:2]};    // 44 .. ~0
    wire ghost_dot = ghost && game_state == `GS_AIM && !grabbing && gt < 6'd48 &&
                     (px_x == gx || px_x == gx + 7'd1) && (px_y == gy || px_y == gy + 6'd1);

    always @(*) begin
        en = 1'b0; color = PANEL; txt = {`TX_W{1'b0}};
        if (in_game) begin
            // ================= panel =================
            if (px_x >= 7'd70 && px_y < `SCR_MTR_Y0) begin
                en = 1'b1;
                color = (px_x == 7'd70) ? 16'h4208 : PANEL;
                if (pin_dot) color = pins_standing[pin_k] ? `C_RED : 16'h31A6;
                if (!spare) begin
                    if (mrow == 4'd0) case (mcol)
                        5'd18: if (kind[`PK_TWO]) txt = tx_l(6'd48, 1'b1, mfx, mfy, player ? `C_CYAN : Y, 0, 1'b0);
                        5'd19: if (kind[`PK_TWO]) txt = tx_l(player ? 6'd18 : 6'd17, 1'b1, mfx, mfy, player ? `C_CYAN : Y, 0, 1'b0);
                        5'd21: txt = tx_l(6'd38, 1'b1, mfx, mfy, W, 0, 1'b0);              // F
                        5'd22: if (fno >= 5'd10) txt = tx_l(6'd17, 1'b1, mfx, mfy, W, 0, 1'b0);
                        5'd23: txt = tx_l(6'd16 + ((fno >= 5'd10) ? 6'd0 : {2'b00, fno[3:0]}), 1'b1, mfx, mfy, W, 0, 1'b0);
                        default: ;
                    endcase
                    else if (row == 3'd1 && col >= 4'd13)
                        txt = tx_l(col == 4'd13 ? (sb[11:8] == 0 ? 6'd0 : dig(sb[11:8])) :
                                   col == 4'd14 ? (sb[11:4] == 0 ? 6'd0 : dig(sb[7:4])) : dig(sb[3:0]),
                                   1'b0, fx, fy, Y, 0, 1'b0);
                    else if (mrow == 4'd3) begin
                        if (mcol >= 5'd18 && mcol < 5'd22) txt = tx_s(`S_BALLW + mcol - 5'd18, 1'b1, mfx, mfy, 16'hAD55, 0, 1'b0);
                        else if (mcol == 5'd23) txt = tx_l(dig({2'b00, ball_no} + 4'd1), 1'b1, mfx, mfy, W, 0, 1'b0);
                    end
                end else begin
                    // Spare Challenge: leave name, then made / tries
                    if (mrow == 4'd0 && mcol >= 5'd18)
                        txt = tx_s(`S_LEAVE + {leave_idx, 3'd0} - leave_idx + mcol - 5'd18, 1'b1, mfx, mfy, Y, 0, 1'b0);
                    else if (mrow == 4'd2) case (mcol)
                        5'd18: txt = tx_l(smb[7:4] == 0 ? 6'd0 : dig(smb[7:4]), 1'b1, mfx, mfy, `C_GREEN, 0, 1'b0);
                        5'd19: txt = tx_l(dig(smb[3:0]), 1'b1, mfx, mfy, `C_GREEN, 0, 1'b0);
                        5'd20: txt = tx_l(6'd15, 1'b1, mfx, mfy, W, 0, 1'b0);              // '/'
                        5'd21: txt = tx_l(stb[7:4] == 0 ? 6'd0 : dig(stb[7:4]), 1'b1, mfx, mfy, W, 0, 1'b0);
                        5'd22: txt = tx_l(dig(stb[3:0]), 1'b1, mfx, mfy, W, 0, 1'b0);
                        default: ;
                    endcase
                end
            end
            // ================= lane overlays =================
            else if (px_x < `SCR_LANE_W) begin
                if (paused && in_box) begin
                    en = 1'b1; color = box_edge ? W : 16'h0010;
                    if (row == 3'd3 && col >= 4'd2 && col < 4'd8) txt = tx_s(`S_HINT + 11'd60 + col - 4'd2, 1'b0, fx, fy, W, 0, 1'b0);
                end else if (show_pop && in_box) begin
                    en = 1'b1; color = box_edge ? W : pop_col;
                    if (row == 3'd3) begin
                        if (popup_id == 4'd8) begin
                            if (col == 4'd2) txt = tx_l(dig(popup_n), 1'b0, fx, fy, W, 0, 1'b0);
                            else if (col >= 4'd4 && col < 4'd8) txt = tx_s(`S_POP + 11'd64 + col - 4'd4, 1'b0, fx, fy, W, 0, 1'b0);
                        end else if (col >= 4'd1 && col < 4'd9)
                            txt = tx_s(`S_POP + {popup_id, 3'd0} + col - 4'd1, 1'b0, fx, fy, W, 0, 1'b0);
                    end
                end else if (show_banner && in_box) begin
                    en = 1'b1; color = box_edge ? 16'h8410 : 16'h0109;
                    if (row == 3'd3) begin
                        if (col >= 4'd1 && col < 4'd6) txt = tx_s(`S_POP + 11'd72 + col - 4'd1, 1'b0, fx, fy, W, 0, 1'b0);
                        else if (col == 4'd7 && fno >= 5'd10) txt = tx_l(6'd17, 1'b0, fx, fy, Y, 0, 1'b0);
                        else if (col == 4'd8) txt = tx_l(6'd16 + ((fno >= 5'd10) ? 6'd0 : {2'b00, fno[3:0]}), 1'b0, fx, fy, Y, 0, 1'b0);
                    end
                end else if (ghost_dot) begin
                    en = 1'b1; color = (gt[2]) ? W : 16'hBDF7;
                end
                // hint row (3x5, y 54..59): saving > replay > what to do now
                if (mrow == 4'd9 && mcol < 5'd15) begin
                    if (saving && fr[4])
                        txt = tx_s(`S_HINT + 11'd90 + mcol, 1'b1, mfx, mfy, `C_ORANGE, `C_BLACK, mcol < 5'd6);
                    else if (paused)
                        txt = tx_s(`S_HINT + 11'd105 + mcol, 1'b1, mfx, mfy, W, `C_BLACK, mcol < 5'd13);
                    else case (game_state)
                        `GS_AIM:    txt = tx_s(`S_HINT + mcol,          1'b1, mfx, mfy, W, `C_BLACK, 1'b1);
                        `GS_THROW:  txt = tx_s(`S_HINT + 11'd15 + mcol, 1'b1, mfx, mfy, Y, `C_BLACK, mcol < 5'd14);
                        `GS_RESULT: txt = tx_s(`S_HINT + 11'd30 + mcol, 1'b1, mfx, mfy, 16'hAD55, `C_BLACK, mcol < 5'd13);
                        `GS_REPLAY: if (fr[4]) txt = tx_s(`S_HINT + 11'd75 + mcol, 1'b1, mfx, mfy, `C_RED, `C_BLACK, mcol < 5'd6);
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule
