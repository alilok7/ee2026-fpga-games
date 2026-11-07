`timescale 1ns / 1ps
// seg7_ctrl.v : what the 4-digit display says
// Owner: Student A
`include "strike_defs.vh"

module seg7_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_game,
    input  wire [`GS_W-1:0] game_state,
    input  wire [2:0]  hover,
    input  wire        paused,
    input  wire        throw_valid,
    input  wire [7:0]  mph10,
    input  wire [8:0]  score0,
    input  wire [8:0]  score1,
    input  wire        player,
    input  wire        two,
    input  wire        spare,
    input  wire [7:0]  made,
    input  wire [7:0]  tries,
    output reg  [23:0] glyphs,
    output reg  [3:0]  dps
);
    localparam [5:0] A = 10, B = 11, E = 14, F = 15, H = 17,
                     I = 18, L = 21, M = 22, N = 23, O = 24, P = 25,
                     R = 27, S = 28, T = 29, U = 30, WW = 32,
                     DASH = 37, BL = 39;
    reg [11:0] spd_ms;
    reg [7:0]  mph_l;
    always @(posedge clk) begin
        if (rst) begin
            spd_ms <= 0;
            mph_l <= 0;
        end
        else if (throw_valid) begin
            spd_ms <= 12'd3000;
            mph_l <= mph10;
        end
        else if (tick_game && spd_ms != 0) spd_ms <= spd_ms - 12'd1;
    end

    reg [10:0] alt_ms;
    reg        alt;
    always @(posedge clk) begin
        if (rst) begin
            alt_ms <= 0;
            alt <= 0;
        end
        else if (tick_game) begin
            if (alt_ms == 11'd1499) begin
                alt_ms <= 0;
                alt <= ~alt;
            end
            else alt_ms <= alt_ms + 11'd1;
        end
    end
    reg who;
    always @(*) begin
        if ((game_state == `GS_GAMEOVER)) begin
            who = (two & alt);
        end else begin
            who = player;
        end
    end
    reg [8:0]  score;
    always @(*) begin
        if (who) begin
            score = score1;
        end else begin
            score = score0;
        end
    end
    reg [5:0]  pdig;
    always @(*) begin
        if (two) begin
            if (who) begin
                pdig = 6'd2;
            end else begin
                pdig = 6'd1;
            end
        end else begin
            pdig = BL;
        end
    end
    wire [11:0] sb;
    seg_bcd9 score_digits (.value(score), .digits(sb));
    wire [11:0] smb, stb;
    seg_bcd9 made_digits (.value({1'b0, made}), .digits(smb));
    seg_bcd9 tries_digits (.value({1'b0, tries}), .digits(stb));
    wire [23:0] spare_g = {{2'b00, smb[7:4]}, {2'b00, smb[3:0]}, {2'b00, stb[7:4]}, {2'b00, stb[3:0]}};
    wire [11:0] mb;
    seg_bcd9 speed_digits (.value({1'b0, mph_l}), .digits(mb));
    wire [23:0] score_g = {pdig, (sb[11:8] == 0) ? BL : {2'b00, sb[11:8]},
                           (sb[11:4] == 0) ? BL : {2'b00, sb[7:4]}, {2'b00, sb[3:0]}};
    wire [23:0] speed_g = {BL, (mb[11:8] == 0) ? BL : {2'b00, mb[11:8]}, {2'b00, mb[7:4]}, {2'b00, mb[3:0]}};
    wire in_game = (game_state >= `GS_AIM && game_state <= `GS_SWEEP) || game_state == `GS_REPLAY;

    reg [23:0] next_glyphs;
    reg [3:0]  next_dps;
    always @(posedge clk) begin
        if (rst) begin
            glyphs <= {BL, BL, BL, BL};
            dps <= 0;
        end else begin
            glyphs <= next_glyphs;
            dps <= next_dps;
        end
    end
    always @(*) begin
        next_dps = 4'b0000;
        next_glyphs = {BL, BL, BL, BL};
        if (paused && in_game) next_glyphs = {P, A, U, S};
        else case (game_state)
            `GS_TITLE: next_glyphs = {B, O, WW, L};
            `GS_MENU: case (hover)
                3'd1: next_glyphs = {R, E, S, U};
                3'd2: next_glyphs = {6'd3, BL, F, R};
                3'd3: next_glyphs = {6'd1, 6'd0, F, R};

                3'd4: next_glyphs = {H, I, BL, BL};
                3'd5: next_glyphs = {S, E, T, BL};
                default: next_glyphs = {H, E, L, P};
            endcase
            `GS_SETTINGS: next_glyphs = {S, E, T, BL};
            `GS_SCORES:   next_glyphs = {H, I, BL, BL};
            `GS_HELP:     next_glyphs = {H, E, L, P};
            `GS_NAME:     next_glyphs = {N, A, M, E};
            `GS_GAMEOVER: next_glyphs = score_g;
            default: begin
                if (spd_ms != 0) begin next_glyphs = speed_g; next_dps = 4'b0010; end
                else if (game_state == `GS_THROW) next_glyphs = {DASH, DASH, DASH, DASH};
                else if (spare) begin next_glyphs = spare_g; next_dps = 4'b0100; end
                else next_glyphs = score_g;
            end
        endcase
    end
endmodule

module seg_bcd_step (
    input wire [11:0] digits_in,
    input wire bit_in,
    output wire [11:0] digits_out
);
    reg [11:0] adjusted;
    always @(*) begin
        adjusted = digits_in;
        if (digits_in[3:0] >= 5) adjusted[3:0] = digits_in[3:0] + 4'd3;
        if (digits_in[7:4] >= 5) adjusted[7:4] = digits_in[7:4] + 4'd3;
        if (digits_in[11:8] >= 5) adjusted[11:8] = digits_in[11:8] + 4'd3;
    end
    assign digits_out = {adjusted[10:0], bit_in};
endmodule

module seg_bcd9 (
    input wire [8:0] value,
    output wire [11:0] digits
);
    wire [11:0] stage1;
    wire [11:0] stage2;
    wire [11:0] stage3;
    wire [11:0] stage4;
    wire [11:0] stage5;
    wire [11:0] stage6;
    wire [11:0] stage7;
    wire [11:0] stage8;
    seg_bcd_step s0 (.digits_in(12'd0), .bit_in(value[8]), .digits_out(stage1));
    seg_bcd_step s1 (.digits_in(stage1), .bit_in(value[7]), .digits_out(stage2));
    seg_bcd_step s2 (.digits_in(stage2), .bit_in(value[6]), .digits_out(stage3));
    seg_bcd_step s3 (.digits_in(stage3), .bit_in(value[5]), .digits_out(stage4));
    seg_bcd_step s4 (.digits_in(stage4), .bit_in(value[4]), .digits_out(stage5));
    seg_bcd_step s5 (.digits_in(stage5), .bit_in(value[3]), .digits_out(stage6));
    seg_bcd_step s6 (.digits_in(stage6), .bit_in(value[2]), .digits_out(stage7));
    seg_bcd_step s7 (.digits_in(stage7), .bit_in(value[1]), .digits_out(stage8));
    seg_bcd_step s8 (.digits_in(stage8), .bit_in(value[0]), .digits_out(digits));
endmodule
