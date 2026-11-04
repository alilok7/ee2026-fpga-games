`timescale 1ns / 1ps
`include "keylight_defs.vh"
`include "strings_map.vh"
//=============================================================================
// play_renderer.v : the Play screen, a pure function of pixel + game state
//-----------------------------------------------------------------------------
// Owner   : Student C
// Layout  : y 0..7   score (left), multiplier and combo (right)
//           y 8      song progress bar
//           y 10..53 8 lanes x 12 px; falling notes are rounded bars
//           y 54     hit line;   y 56..63 lane letters = which switch
// Method  : lane = x / 12 = (x * 43) >> 9 (no divider), lx = x - 12*lane.
//           A pixel is "note" if ANY of the 24 snapshot slots has the same
//           lane and top <= y <= bottom: 24 range checks per pixel, no
//           bitmaps. Text uses D's font/string ROMs (one lookup per pixel).
// Budget  : 24 slots x (3-bit lane compare + two 8-bit compares).
//=============================================================================
module play_renderer #(
    parameter N = 24
) (
    input  wire [6:0]     px_x,
    input  wire [5:0]     px_y,
    input  wire [N-1:0]   r_vis,
    input  wire [N-1:0]   r_missed,
    input  wire [3*N-1:0] r_lane,
    input  wire [8*N-1:0] r_top,
    input  wire [8*N-1:0] r_bot,
    input  wire [7:0]     flash,          // per-lane hit flash
    input  wire [1:0]     popup,          // 0 none, 1 PERFECT, 2 GOOD, 3 MISS
    input  wire           burst_on,
    input  wire [2:0]     burst_lane,
    input  wire [23:0]    score_bcd,
    input  wire [11:0]    combo_bcd,
    input  wire [2:0]     mult,
    input  wire [6:0]     progress,       // 0..96 px
    input  wire [2:0]     countin,        // 0 none, 1 "3", 2 "2", 3 "1", 4 "GO!", 5 tip
    output reg  [15:0]    color
);
    localparam signed [7:0] HIT_Y = 8'sd54;
    localparam [15:0] C_GOLD = 16'hFE60;

    // ---- lane geometry -----------------------------------------------------
    wire [12:0] p43  = px_x * 6'd43;
    wire [2:0]  lane = p43[11:9];
    wire [6:0]  lx   = px_x - ({1'b0, lane, 3'b000} + {2'b00, lane, 2'b00});
    wire signed [7:0] ys = {2'b00, px_y};

    // ---- 24 range checks ---------------------------------------------------
    reg note_on, note_miss;
    integer i;
    always @(*) begin
        note_on = 1'b0; note_miss = 1'b0;
        for (i = 0; i < N; i = i + 1) begin
            if (r_vis[i] && r_lane[3*i +: 3] == lane &&
                ys >= $signed(r_top[8*i +: 8]) && ys <= $signed(r_bot[8*i +: 8]) &&
                lx >= 7'd1 && lx <= 7'd10 &&
                !((lx == 7'd1 || lx == 7'd10) &&                       // round corners
                  (ys == $signed(r_top[8*i +: 8]) || ys == $signed(r_bot[8*i +: 8])))) begin
                note_on = 1'b1;
                if (r_missed[i]) note_miss = 1'b1;
            end
        end
    end

    // ---- burst sprite on Perfect: a small star centred on the hit line -----
    wire [6:0] cx  = {1'b0, burst_lane, 3'b000} + {2'b00, burst_lane, 2'b00} + 7'd5;
    wire [6:0] adx = (px_x >= cx) ? px_x - cx : cx - px_x;
    wire [5:0] ady = (px_y >= 6'd54) ? px_y - 6'd54 : 6'd54 - px_y;
    wire burst_px = burst_on && ((adx == 7'd0 && ady <= 6'd4) || (ady == 6'd0 && adx <= 7'd4) ||
                                 ({1'b0, ady} == adx && adx <= 7'd2));

    // ---- palette -----------------------------------------------------------
    wire [15:0] lane_c, lane_dk;
    note_palette u_pal  (.lane(lane), .dark(1'b0), .color(lane_c));
    note_palette u_pald (.lane(lane), .dark(1'b1), .color(lane_dk));
    wire [15:0] lane_bg = (lane_dk >> 1) & 16'h7BEF;          // quarter brightness

    // ---- text: choose glyph / font row / font column for this pixel --------
    wire [3:0] col; wire [2:0] fx, row, fy, col2, fx2;
    text_grid u_grid (.px_x(px_x), .px_y(px_y), .col(col), .fx(fx), .row(row),
                      .fy(fy), .col2(col2), .fx2(fx2));
    reg  [9:0]  t_addr;
    reg  [5:0]  t_glyph;
    reg         t_direct, t_en;
    reg  [2:0]  t_row, t_col;
    reg  [15:0] t_fg;
    wire [5:0]  s_ch;
    wire [4:0]  fbits;
    string_rom u_str  (.addr(t_addr), .ch(s_ch));
    font_rom   u_font (.ch(t_direct ? t_glyph : s_ch), .row(t_row), .bits(fbits));
    wire text_on = t_en && t_col < 3'd5 && t_row < 3'd7 && fbits[3'd4 - t_col];

    wire [6:0] lx4 = lx - 7'd4;                                // letter centred in lane
    always @(*) begin
        t_en = 1'b0; t_direct = 1'b1; t_addr = 10'd0; t_glyph = 6'd0;
        t_row = fy; t_col = fx; t_fg = `KL_WHITE;
        if (row == 3'd0) begin                                 // HUD
            if (col <= 4'd5) begin                             // 6-digit score
                t_en = 1'b1; t_glyph = 6'd16 + score_bcd[4*(3'd5 - col[2:0]) +: 4];
            end else if (col == 4'd10 && mult != 3'd1) begin   // "x2" multiplier
                t_en = 1'b1; t_glyph = 6'h38; t_fg = C_GOLD;   // 'X'
            end else if (col == 4'd11 && mult != 3'd1) begin
                t_en = 1'b1; t_glyph = 6'd16 + {3'd0, mult}; t_fg = C_GOLD;
            end else if (col >= 4'd13 && combo_bcd != 12'd0) begin
                t_en = 1'b1; t_fg = C_GOLD;
                t_glyph = 6'd16 + combo_bcd[4*(4'd15 - col) +: 4];
            end
        end else if (countin >= 3'd1 && countin <= 3'd4 && (row == 3'd2 || row == 3'd3)) begin
            if (col2 >= 3'd2 && col2 <= 3'd5) begin            // big "3" "2" "1" "GO!"
                t_en = 1'b1; t_direct = 1'b0;
                t_addr = `S_COUNT + {countin - 3'd1, 2'b00} + (col2 - 3'd2);
                t_row = {row[0], fy[2:1]}; t_col = fx2; t_fg = C_GOLD;
            end
        end else if (countin == 3'd5 && row == 3'd4) begin
            if (col <= 4'd14) begin                            // "FLIP LIT SWITCH"
                t_en = 1'b1; t_direct = 1'b0; t_addr = `S_TIP + col; t_fg = C_GOLD;
            end
        end else if (popup != 2'd0 && row == 3'd3) begin
            if (col >= 4'd4 && col <= 4'd11) begin
                t_en = 1'b1; t_direct = 1'b0;
                t_addr = `S_POP + {popup - 2'd1, 3'b000} + (col - 4'd4);
                t_fg = (popup == 2'd1) ? C_GOLD : (popup == 2'd2) ? 16'h07E0 : 16'hF800;
            end
        end else if (row == 3'd7) begin                        // lane letters
            if (lx >= 7'd4 && lx <= 7'd8) begin
                t_en = 1'b1; t_direct = 1'b0; t_addr = `S_LANES + lane;
                t_col = lx4[2:0]; t_fg = lane_c;
            end
        end
    end

    // ---- compose, top layer first --------------------------------------------
    always @(*) begin
        if (text_on)
            color = t_fg;
        else if (px_y < 6'd8)
            color = `KL_BLACK;
        else if (px_y == 6'd8)
            color = (px_x < progress) ? `KL_WHITE : `KL_DKGREY;
        else if (px_y == 6'd9)
            color = `KL_BLACK;
        else if (burst_px)
            color = `KL_WHITE;
        else if (note_on)
            color = note_miss ? `KL_GREY : lane_c;
        else if (px_y == 6'd54)
            color = flash[lane] ? lane_c : `KL_WHITE;
        else if (px_y >= 6'd56)
            color = flash[lane] ? lane_dk : lane_bg;
        else if (lx == 7'd0)
            color = `KL_BLACK;                                 // lane separator
        else
            color = flash[lane] ? lane_dk : lane_bg;
    end
endmodule
