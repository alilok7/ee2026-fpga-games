`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// screen2.v - the second OLED (scoreboard screen): picks the page, mixes the layers
//-----------------------------------------------------------------------------
// Owner   : Student C
// Why a second screen: on screen 1 the scorecard used to cover the lane.
// Now screen 1 is only the lane, and screen 2 is like the monitor above a
// real bowling lane:
//
//   page SCORE (in a game, and on the game-over / initials screens)
//       y  0..35  D's scorecard (scorecard_render), or in Spare Challenge
//                 the leave and MADE / OF (deck_panel)
//       y 36..63  the live pin deck and pin counts (deck_panel)
//   page SWITCHES (in the menus; in a game while btnD / right-click is on)
//       what every switch does, green when up (switch_panel)
//
// Both OLEDs run from the same 6.25 MHz clock and the same reset, so their
// Oled_Display state machines are identical and ask for the SAME pixel at
// the same time: screen 2 reuses screen 1's px_x / px_y.
//
// Screen 2 has its own text engine (with its own small string ROM,
// screen2_strings.mem) so it never competes with screen 1 for one.
//
// Output timing: like D's compositor, the colour register loads once the
// pixel position has been stable for 6 clocks; the XDC gives every path
// into u_scr2/oled_data_reg a 6-clock multicycle.
//=============================================================================
module screen2 (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire [`GS_W-1:0]  game_state,
    input  wire [`PK_W-1:0]  kind,
    input  wire [`SET_W-1:0] settings,
    input  wire [15:0] sw_level,
    input  wire        help_page,        // btnD / right-click in a game (from D)
    // pins (C)
    input  wire [9:0]  standing,
    input  wire [9:0]  standing_before,
    input  wire        split_flag,
    // Spare Challenge (D)
    input  wire [2:0]  leave_idx,
    input  wire [7:0]  spare_made,
    input  wire [7:0]  spare_tries,
    // D's scorecard layer
    input  wire        sc_en,
    input  wire [15:0] sc_c,
    input  wire [`TX_W-1:0] sc_t,
    output reg  [15:0] oled_data
);
    // ---------------- which page? ----------------------------------------
    wire in_game  = (game_state >= `GS_AIM && game_state <= `GS_SWEEP) ||
                    (game_state == `GS_REPLAY);
    wire at_end   = (game_state == `GS_GAMEOVER) || (game_state == `GS_NAME);
    wire page_score = (in_game && !help_page) || at_end;
    wire spare    = kind[`PK_SPARE];

    reg [3:0] fr;                                   // frame counter for blinking
    always @(posedge clk)
        if (rst)             fr <= 4'd0;
        else if (tick_frame) fr <= fr + 4'd1;

    // ---------------- the two panels ---------------------------------------
    wire [15:0] dk_c, sp_c;
    wire        dk_en, sp_en;
    wire [`TX_W-1:0] dk_t, sp_t;

    // Before the ball is thrown (aiming, swiping, new rack) nothing has been
    // knocked down yet: compare the pins with themselves, so DOWN shows 0.
    wire no_throw_yet = (game_state == `GS_AIM) || (game_state == `GS_THROW) ||
                        (game_state == `GS_SWEEP);
    wire [9:0] before = no_throw_yet ? standing : standing_before;

    deck_panel u_deck (
        .px_x(px_x), .px_y(px_y), .standing(standing), .standing_before(before),
        .split_flag(split_flag),
        .show_split(game_state == `GS_RESULT || game_state == `GS_SWEEP),
        .blink(fr[3]), .spare(spare), .leave_idx(leave_idx),
        .spare_made(spare_made), .spare_tries(spare_tries),
        .color(dk_c), .en(dk_en), .txt(dk_t));

    switch_panel u_switch (
        .px_x(px_x), .px_y(px_y), .sw_level(sw_level), .in_game(in_game),
        .color(sp_c), .en(sp_en), .txt(sp_t));

    // ---------------- choose the layer for this pixel -------------------------
    // On the SCORE page the scorecard owns y 0..35 (unless Spare Challenge),
    // the deck panel the rest.
    wire use_card = page_score && !spare && (px_y < 6'd36);
    reg  [15:0] base_c;
    reg  [`TX_W-1:0] req;
    always @(*) begin
        if (!page_score) begin
            base_c = sp_c;                       req = sp_t;
        end else if (use_card) begin
            base_c = sc_en ? sc_c : `C_BLACK;    req = sc_t;
        end else begin
            base_c = dk_en ? dk_c : `C_BLACK;    req = dk_t;
        end
    end

    // ---------------- text: glyph pixel, opaque cell, or the graphics ------------
    wire t_on, t_cell, t_bgen;
    wire [15:0] t_fg, t_bg;
    text_engine #(.STR_FILE("screen2_strings.mem"), .STR_AW(9)) u_text2 (
        .req(req), .on(t_on), .in_cell(t_cell), .fg(t_fg), .bg(t_bg), .bg_en(t_bgen));

    wire [15:0] mixed = t_on              ? t_fg :
                        (t_cell && t_bgen) ? t_bg : base_c;

    // ---------------- brightness (same 4 levels as screen 1) -------------------
    wire [4:0] r = mixed[15:11];
    wire [5:0] g = mixed[10:5];
    wire [4:0] b = mixed[4:0];
    reg  [15:0] dimmed;
    always @(*) begin
        case (settings[`SET_BRI_HI:`SET_BRI_LO])
            2'd3:    dimmed = mixed;
            2'd2:    dimmed = {r - (r >> 2), g - (g >> 2), b - (b >> 2)};
            2'd1:    dimmed = {r >> 1, g >> 1, b >> 1};
            default: dimmed = {r >> 2, g >> 2, b >> 2};
        endcase
    end

    // ---------------- output register (loads when the pixel is stable) -------
    reg [6:0] last_x = 7'd0;
    reg [5:0] last_y = 6'd0;
    reg [2:0] wait_cnt = 3'd0;
    always @(posedge clk) begin
        last_x <= px_x;
        last_y <= px_y;
        if (px_x != last_x || px_y != last_y) wait_cnt <= 3'd6;
        else if (wait_cnt != 3'd0)           wait_cnt <= wait_cnt - 3'd1;
        if (wait_cnt == 3'd1) oled_data <= dimmed;
    end
endmodule
