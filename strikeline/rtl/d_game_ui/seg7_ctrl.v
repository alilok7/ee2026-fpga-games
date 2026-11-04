`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// seg7_ctrl.v : what the 4-digit display says
//-----------------------------------------------------------------------------
// Owner   : Student D
// Glyph codes are seg7_driver's: 0-9 digits, 10.. letters, 37 '-', 39 blank.
//   menus      the word for the highlighted item (PLAY, PrAC, HI, SEt ...)
//   after a throw  the ball speed "17.2" (decimal point on) for 3 s
//   otherwise in a game  the current player's PROVISIONAL score (moves after
//              every ball); 2 players: the left digit is the player number
//   Spare Challenge  made . tries  (e.g. 03.05)
//   game over  the score; 2 players: P1 and P2 alternate every 1.5 s
//   Swipe Lab  the speed of the last swipe; game over: the final score
//   paused     "PAUS"
//=============================================================================
module seg7_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_game,
    input  wire [`GS_W-1:0] game_state,
    input  wire [2:0]  hover,
    input  wire        paused,
    input  wire        throw_valid,
    input  wire [7:0]  mph10,
    input  wire [8:0]  score0,           // provisional totals of both players
    input  wire [8:0]  score1,
    input  wire        player,           // whose turn it is
    input  wire        two,              // 2-player game
    input  wire        spare,            // Spare Challenge
    input  wire [7:0]  made,
    input  wire [7:0]  tries,
    output reg  [23:0] glyphs,           // registered (timing)
    output reg  [3:0]  dps
);
`include "bcd_fns.vh"
    localparam [5:0] A = 6'd10, B = 6'd11, Cc = 6'd12, D = 6'd13, E = 6'd14, F = 6'd15, H = 6'd17,
                     I = 6'd18, L = 6'd21, M = 6'd22, N = 6'd23, O = 6'd24, P = 6'd25, R = 6'd27,
                     S = 6'd28, T = 6'd29, U = 6'd30, WW = 6'd32, Yy = 6'd34, DASH = 6'd37, BL = 6'd39;
    reg [11:0] spd_ms;
    reg [7:0]  mph_l;
    always @(posedge clk) begin
        if (rst) begin spd_ms <= 0; mph_l <= 0; end
        else if (throw_valid) begin spd_ms <= 12'd3000; mph_l <= mph10; end
        else if (tick_game && spd_ms != 0) spd_ms <= spd_ms - 12'd1;
    end
    // game over in 2-player: show P1, then P2, every 1.5 s
    reg [10:0] alt_ms;
    reg        alt;
    always @(posedge clk) begin
        if (rst) begin alt_ms <= 0; alt <= 0; end
        else if (tick_game) begin
            if (alt_ms == 11'd1499) begin alt_ms <= 0; alt <= ~alt; end
            else alt_ms <= alt_ms + 11'd1;
        end
    end
    wire        who = (game_state == `GS_GAMEOVER) ? (two & alt) : player;
    wire [8:0]  score = who ? score1 : score0;
    wire [5:0]  pdig  = two ? (who ? 6'd2 : 6'd1) : BL;      // player digit (left)
    wire [11:0] sb = bcd9(score);
    wire [11:0] smb = bcd9({1'b0, made}), stb = bcd9({1'b0, tries});
    wire [23:0] spare_g = {{2'b00, smb[7:4]}, {2'b00, smb[3:0]}, {2'b00, stb[7:4]}, {2'b00, stb[3:0]}};
    wire [11:0] mb = bcd9({1'b0, mph_l});
    wire [23:0] score_g = {pdig, (sb[11:8] == 0) ? BL : {2'b00, sb[11:8]},
                           (sb[11:4] == 0) ? BL : {2'b00, sb[7:4]}, {2'b00, sb[3:0]}};
    wire [23:0] speed_g = {BL, (mb[11:8] == 0) ? BL : {2'b00, mb[11:8]}, {2'b00, mb[7:4]}, {2'b00, mb[3:0]}};
    wire in_game = (game_state >= `GS_AIM && game_state <= `GS_SWEEP) || game_state == `GS_REPLAY;

    reg [23:0] g_c;
    reg [3:0]  d_c;
    always @(posedge clk) begin glyphs <= g_c; dps <= d_c; end
    always @(*) begin
        d_c = 4'b0000;
        g_c = {BL, BL, BL, BL};
        if (paused && in_game) g_c = {P, A, U, S};
        else case (game_state)
            `GS_TITLE: g_c = {B, O, WW, L};
            `GS_MENU: case (hover)
                3'd1: g_c = {R, E, S, U};
                3'd2: g_c = {6'd3, BL, F, R};
                3'd3: g_c = {6'd1, 6'd0, F, R};
                3'd4: g_c = {P, R, A, Cc};
                3'd5: g_c = {H, I, BL, BL};
                3'd6: g_c = {S, E, T, BL};
                default: g_c = {H, E, L, P};
            endcase
            `GS_PRACTICE_SPARE: g_c = {P, R, A, Cc};
            `GS_PRACTICE_SWIPE: begin g_c = speed_g; d_c = 4'b0010; end
            `GS_SETTINGS: g_c = {S, E, T, BL};
            `GS_SCORES:   g_c = {H, I, BL, BL};
            `GS_HELP:     g_c = {H, E, L, P};
            `GS_NAME:     g_c = {N, A, M, E};
            `GS_GAMEOVER: g_c = score_g;
            default: begin
                if (spd_ms != 0) begin g_c = speed_g; d_c = 4'b0010; end
                else if (game_state == `GS_THROW) g_c = {DASH, DASH, DASH, DASH};
                else if (spare) begin g_c = spare_g; d_c = 4'b0100; end   // "03.05"
                else g_c = score_g;
            end
        endcase
    end
endmodule
