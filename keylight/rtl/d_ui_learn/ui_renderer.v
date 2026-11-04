`timescale 1ns / 1ps
`include "keylight_defs.vh"
`include "strings_map.vh"
//=============================================================================
// ui_renderer.v : D's screens (title, menu, song select, results, stubs)
//                 and the overlay layer (hint bar, pause banner)
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : A combinational function of (px_x, px_y, UI state) -> RGB565.
//           Text: for the pixel's character cell, a per-screen layout picks
//           "string S, starting at column c0" (or a digit). One string_rom
//           and one font_rom lookup per pixel then give the pixel's bit.
//           Shapes (highlight bar, title notes) are range checks, never
//           bitmaps. The only state here is animation (frame counter,
//           sliding highlight), updated on tick_frame between frames.
// Layers  : ui_color = the screen for D's modes.
//           ov_color/ov_en = drawn ON TOP of every mode's screen by the
//           video mux: the bottom hint bar (all modes except Play) and the
//           pause banner (Play).
//=============================================================================
module ui_renderer (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  tick_frame,
    input  wire [6:0]            px_x,
    input  wire [5:0]            px_y,
    input  wire [`KL_MODE_W-1:0] mode,
    input  wire [2:0]            menu_idx,
    input  wire [2:0]            song_id,
    input  wire [1:0]            difficulty,
    input  wire                  rec_exists,
    input  wire                  paused,
    input  wire [23:0]           best_bcd,
    input  wire [14:0]           best_initials,  // 3 x 5 bits, 1..26 = A..Z, 0 = none
    input  wire [23:0]           res_score_bcd,
    input  wire [11:0]           res_perf_bcd,
    input  wire [11:0]           res_good_bcd,
    input  wire [11:0]           res_miss_bcd,
    input  wire [11:0]           res_max_bcd,
    input  wire [11:0]           res_acc_bcd,
    input  wire [2:0]            res_grade,
    output reg  [15:0]           ui_color,
    output reg  [15:0]           ov_color,
    output reg                   ov_en
);
    localparam [5:0] G_NOTE = 6'h3C, G_DASH = 6'h0D, G_PCT = 6'h05;   // glyph codes
    localparam [15:0] C_GOLD = 16'hFE60, C_HINTBG = 16'h2124, C_BANNER = 16'h1092;

    // ---------------- animation state (changes only between frames) --------
    reg [7:0] anim;                 // frame counter, 60 per second
    reg [5:0] bar_y;                // sliding highlight bar, top y
    wire [5:0] bar_target = {((mode == `KL_MODE_MENU) ? menu_idx : song_id) + 3'd1, 3'b000};
    always @(posedge clk) begin
        if (rst) begin
            anim  <= 8'd0;
            bar_y <= 6'd8;
        end else if (tick_frame) begin
            anim <= anim + 8'd1;
            // Move 2 px per frame toward the target -> 4 frames per item.
            if (bar_y + 6'd2 <= bar_target)      bar_y <= bar_y + 6'd2;
            else if (bar_y >= bar_target + 6'd2) bar_y <= bar_y - 6'd2;
            else                                 bar_y <= bar_target;
        end
    end

    // ---------------- grid, ROMs, palette -----------------------------------
    wire [3:0] col;  wire [2:0] fx, row, fy, col2, fx2;
    text_grid u_grid (.px_x(px_x), .px_y(px_y), .col(col), .fx(fx), .row(row),
                      .fy(fy), .col2(col2), .fx2(fx2));

    reg  [9:0]  t_addr;              // string ROM address for this cell
    reg  [5:0]  t_glyph;             // used when t_direct = 1
    reg         t_direct, t_en, t_big, t_bigodd;
    reg  [15:0] t_fg;
    wire [5:0]  s_ch;
    string_rom u_str (.addr(t_addr), .ch(s_ch));
    wire [5:0]  glyph = t_direct ? t_glyph : s_ch;
    wire [2:0]  frow  = t_big ? {row[0] ^ t_bigodd, fy[2:1]} : fy;
    wire [2:0]  fcol  = t_big ? fx2 : fx;
    wire [4:0]  fbits;
    font_rom u_font (.ch(glyph), .row(frow), .bits(fbits));
    wire text_on = t_en && (fcol < 3'd5) && (frow < 3'd7) && fbits[3'd4 - fcol];

    reg  [2:0]  fg_lane, bg_lane;
    wire [15:0] fg_pal, bg_pal;
    note_palette u_pal_fg (.lane(fg_lane), .dark(1'b0), .color(fg_pal));
    note_palette u_pal_bg (.lane(bg_lane), .dark(1'b1), .color(bg_pal));

    // ---------------- layout helpers (tasks set the t_* "text request") ------
    task put_str;                          // 1x string at column c0
        input [9:0] base; input [3:0] c0; input [4:0] len; input [15:0] fg;
        begin
            if ({1'b0, col} >= {1'b0, c0} && {1'b0, col} < {1'b0, c0} + len) begin
                t_en = 1'b1; t_direct = 1'b0; t_big = 1'b0;
                t_addr = base + (col - c0); t_fg = fg;
            end
        end
    endtask
    task put_big;                          // 2x string at big-column c0
        input [9:0] base; input [2:0] c0; input [3:0] len; input [15:0] fg; input odd;
        begin
            if ({1'b0, col2} >= {1'b0, c0} && {1'b0, col2} < {1'b0, c0} + len) begin
                t_en = 1'b1; t_direct = 1'b0; t_big = 1'b1; t_bigodd = odd;
                t_addr = base + (col2 - c0); t_fg = fg;
            end
        end
    endtask
    task put_glyph;                        // one glyph at column c0
        input [5:0] g; input [3:0] c0; input [15:0] fg;
        begin
            if (col == c0) begin
                t_en = 1'b1; t_direct = 1'b1; t_big = 1'b0; t_glyph = g; t_fg = fg;
            end
        end
    endtask
    task put_num;                          // n BCD digits, most significant first
        input [23:0] bcd; input [3:0] c0; input [2:0] n; input [15:0] fg; input big;
        reg [3:0] k, c;
        begin
            c = big ? {1'b0, col2} : col;
            if ({1'b0, c} >= {1'b0, c0} && {1'b0, c} < {1'b0, c0} + n) begin   // 5 bits: 13+3 must not wrap
                k = n - 4'd1 - (c - c0);
                t_en = 1'b1; t_direct = 1'b1; t_big = big; t_bigodd = 1'b1;
                t_glyph = 6'd16 + bcd[4*k +: 4]; t_fg = fg;
            end
        end
    endtask

    // ---------------- per-screen layout --------------------------------------
    wire [2:0] item      = row - 3'd1;                 // list row -> item index
    wire [9:0] item12    = {4'd0, item, 3'b000} + {5'd0, item, 2'b00};
    wire [2:0] last_song = rec_exists ? 3'd4 : 3'd3;
    wire [11:0] bpm_bcd;
    song_info_rom u_info (.song_id(song_id), .bpm_bcd(bpm_bcd));
    wire in_bar = (px_y >= bar_y) && (px_y < bar_y + 6'd8);
    reg [15:0] bg;
    reg [4:0]  ini;

    always @(*) begin
        t_en = 1'b0; t_direct = 1'b0; t_big = 1'b0; t_bigodd = 1'b0;
        t_addr = 10'd0; t_glyph = 6'd0; t_fg = `KL_WHITE;
        fg_lane = 3'd0; bg_lane = 3'd0; bg = `KL_BLACK; ini = 5'd0;
        ov_en = 1'b0; ov_color = `KL_BLACK;

        // ---- overlay regions first: they own their text cells ----
        if (row == 3'd7 && mode != `KL_MODE_PLAY && mode != `KL_MODE_TEST) begin
            ov_en = 1'b1;
            case (mode)
                `KL_MODE_TITLE:   put_str(`S_H_TITLE, (16 - `L_H_TITLE) / 2, `L_H_TITLE, `KL_WHITE);
                `KL_MODE_MENU:    put_str(`S_H_MENU,  (16 - `L_H_MENU) / 2,  `L_H_MENU,  `KL_WHITE);
                `KL_MODE_SONGSEL: put_str(`S_H_SONG,  (16 - `L_H_SONG) / 2,  `L_H_SONG,  `KL_WHITE);
                `KL_MODE_RESULTS: put_str(`S_H_RES,   (16 - `L_H_RES) / 2,   `L_H_RES,   `KL_WHITE);
                `KL_MODE_FREE:    put_str(`S_FREEH,   (16 - `L_FREEH) / 2,   `L_FREEH,   `KL_WHITE);
                default:          put_str(`S_H_BACK,  (16 - `L_H_BACK) / 2,  `L_H_BACK,  `KL_WHITE);
            endcase
        end else if (mode == `KL_MODE_PLAY && paused && (row == 3'd3 || row == 3'd4)) begin
            ov_en = 1'b1;
            if (row == 3'd3) put_str(`S_PAUSED, (16 - `L_PAUSED) / 2, `L_PAUSED, `KL_WHITE);
            else             put_str(`S_PAUSEH, 0, `L_PAUSEH, C_GOLD);
        end else begin
            // ---- base screens ----
            case (mode)
            `KL_MODE_TITLE: begin
                // falling note streaks behind the logo, one per lane
                bg_lane = col[3:1];
                if (fx >= 3'd2 && fx <= 3'd3 && col[0] &&
                    (((px_y - (col[1] ? anim[5:0] : anim[6:1]) - {col[3:1], 3'b0}) & 6'd63) < 6'd6))
                    bg = bg_pal;
                fg_lane = col2;
                if (row == 3'd2 || row == 3'd3)
                    put_big(`S_TITLE, 3'd0, 4'd8,
                            ((px_x - {anim[6:0], 1'b0}) < 7'd6 || ({anim[6:0], 1'b0} - px_x) < 7'd6)
                              ? `KL_WHITE : fg_pal, 1'b0);
                if (row == 3'd4) put_str(`S_TAGLINE, (16 - `L_TAGLINE) / 2, `L_TAGLINE, `KL_GREY);
                if (row == 3'd6 && anim[5]) put_str(`S_PRESS, 4'd4, `L_PRESS, C_GOLD);
            end
            `KL_MODE_MENU: begin
                bg_lane = menu_idx;
                if (row == 3'd0) begin
                    bg = `KL_DKGREY;
                    put_str(`S_TITLE, 4'd4, `L_TITLE, `KL_WHITE);
                end else if (row <= 3'd5) begin
                    if (in_bar) bg = bg_pal;
                    fg_lane = item;
                    put_glyph(G_NOTE, 4'd0, fg_pal);
                    put_str(`S_MENU + item12, 4'd2, `L_MENU,
                            (item == menu_idx) ? `KL_WHITE : `KL_GREY);
                end else if (row == 3'd6) begin
                    fg_lane = menu_idx;
                    put_str(`S_MDESC + {menu_idx, 4'b0000}, 4'd0, `L_MDESC, fg_pal);
                end
            end
            `KL_MODE_SONGSEL: begin
                bg_lane = song_id;
                if (row == 3'd0) begin
                    put_str(`S_DIFF + {difficulty, 2'b00} + {difficulty, 1'b0}, 4'd0, `L_DIFF,
                            (difficulty == `KL_DIFF_EASY) ? 16'h07E0 :
                            (difficulty == `KL_DIFF_HARD) ? 16'hF800 : 16'hFFE0);
                    put_str(`S_BPM, 4'd9, `L_BPM, `KL_GREY);
                    put_num({12'd0, bpm_bcd}, 4'd13, 3'd3, `KL_WHITE, 1'b0);
                end else if (row <= 3'd5 && item <= last_song) begin
                    if (in_bar) bg = bg_pal;
                    fg_lane = item;
                    put_glyph(G_NOTE, 4'd0, fg_pal);
                    put_str(`S_SONGS + item12, 4'd2, `L_SONGS,
                            (item == song_id) ? `KL_WHITE : `KL_GREY);
                end else if (row == 3'd6) begin
                    put_str(`S_BEST, 4'd0, `L_BEST, `KL_GREY);
                    put_num(best_bcd, 4'd5, 3'd6, C_GOLD, 1'b0);
                    if (col >= 4'd12 && col <= 4'd14) begin
                        ini = (col == 4'd12) ? best_initials[14:10] :
                              (col == 4'd13) ? best_initials[9:5] : best_initials[4:0];
                        put_glyph((ini == 5'd0) ? G_DASH : 6'd32 + {1'b0, ini}, col, `KL_WHITE);
                    end
                end
            end
            `KL_MODE_RESULTS: begin
                if (row == 3'd0)
                    put_str(`S_SONGS + {4'd0, song_id, 3'b000} + {5'd0, song_id, 2'b00},
                            4'd0, `L_SONGS, `KL_WHITE);
                else if (row == 3'd1 || row == 3'd2) begin
                    put_num(res_score_bcd, 4'd0, 3'd6, `KL_WHITE, 1'b1);
                    put_big(`S_GRADES + res_grade, 3'd7, 4'd1,
                            (res_grade == `KL_GRADE_S) ? C_GOLD :
                            (res_grade <= `KL_GRADE_B) ? 16'h07E0 : 16'hFB56, 1'b1);
                end else if (row <= 3'd5) begin
                    put_str(`S_RES + {item - 3'd2, 3'b000}, 4'd0, 5'd7,
                            (row == 3'd3) ? C_GOLD : (row == 3'd4) ? 16'h07E0 : 16'hF800);
                    put_num({12'd0, (row == 3'd3) ? res_perf_bcd :
                                    (row == 3'd4) ? res_good_bcd : res_miss_bcd},
                            4'd8, 3'd3, `KL_WHITE, 1'b0);
                end else if (row == 3'd6) begin
                    put_str(`S_RES + 10'd24, 4'd0, 5'd3, `KL_GREY);     // "ACC"
                    put_num({12'd0, res_acc_bcd}, 4'd4, 3'd3, `KL_WHITE, 1'b0);
                    put_glyph(G_PCT, 4'd7, `KL_WHITE);
                    put_str(`S_RES + 10'd32, 4'd9, 5'd3, `KL_GREY);     // "MAX"
                    put_num({12'd0, res_max_bcd}, 4'd13, 3'd3, `KL_WHITE, 1'b0);
                end
            end
            default: begin   // Learn / Scores / Settings / Name: not built yet
                if (row == 3'd2)
                    put_str(`S_MENU + ((mode == `KL_MODE_LEARN) ? 10'd12 :
                                       (mode == `KL_MODE_SCORES) ? 10'd36 : 10'd48),
                            4'd2, `L_MENU, `KL_WHITE);
                if (row == 3'd4) put_str(`S_SOON, 4'd2, `L_SOON, `KL_GREY);
            end
            endcase
        end

        // ---- compose ----
        if (ov_en) ov_color = text_on ? t_fg : ((row == 3'd7) ? C_HINTBG : C_BANNER);
        ui_color = text_on ? t_fg : bg;
    end
endmodule

//-----------------------------------------------------------------------------
// song_info_rom : BPM of each song as 3 BCD digits (data from song_to_mem.py)
//-----------------------------------------------------------------------------
module song_info_rom #(
    parameter MEM_FILE = "song_info.mem"
) (
    input  wire [2:0]  song_id,
    output wire [11:0] bpm_bcd
);
    reg [11:0] rom [0:7];
    initial $readmemh(MEM_FILE, rom);
    assign bpm_bcd = rom[song_id];
endmodule
