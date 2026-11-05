`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// compositor.v : layers -> one pixel colour for OLED 1 (the lane screen)
//-----------------------------------------------------------------------------
// Owner   : Student D
// Layers (front to back):
//   A cursor > D HUD/popups > D menus > A trail/meters/labels
//   > B ball > C pins > B lane > black
//   (v3: the scorecard moved to OLED 2, Student C's screen2.v)
//   Each layer says "I draw this pixel" (en) and its colour. Text layers also
//   send a text request; the FIRST valid request in that order goes to the
//   one shared text_engine, and the glyph pixel (fg), the cell background
//   (bg, when opaque) or the layer's own graphics are used for that layer.
// Post-processing, applied once to the final colour:
//   brightness 4 levels (x1, 3/4, 1/2, 1/4 with shifts)
//   fade-in: after every change of game_state the picture ramps from black
//   to full in 200 ms (12 frames): channel * level / 8, level 0..8.
// Timing : the output register captures only once the pixel position has
//   been stable for 6 clocks (capture enable), and the XDC gives all paths
//   into it 6 clocks (multicycle), as proved in KeyLight's tb_top: each
//   pixel position is held for 256 clocks, the OLED latches 16 clocks after
//   it changes, so the colour is ready ~7 clocks before it is needed.
//=============================================================================
module compositor (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire [`GS_W-1:0] game_state,
    input  wire [`SET_W-1:0] settings,
    input  wire        cur_en,   input wire [15:0] cur_c,
    input  wire        hud_en,   input wire [15:0] hud_c,  input wire [`TX_W-1:0] hud_t,
    input  wire        menu_en,  input wire [15:0] menu_c, input wire [`TX_W-1:0] menu_t,
    input  wire        a_en,     input wire [15:0] a_c,    input wire [`TX_W-1:0] a_t,
    input  wire        ball_en,  input wire [15:0] ball_c,
    input  wire        pin_en,   input wire [15:0] pin_c,
    input  wire        lane_en,  input wire [15:0] lane_c,
    output reg  [15:0] oled_data
);
    // ---------------- shared text engine ----------------------------------
    wire [1:0] tsel = hud_t[`TX_VALID] ? 2'd1 : menu_t[`TX_VALID] ? 2'd2 : 2'd3;
    wire [`TX_W-1:0] treq = (tsel == 2'd1) ? hud_t : (tsel == 2'd2) ? menu_t : a_t;
    wire t_on, t_cell, t_bgen;
    wire [15:0] t_fg, t_bg;
    text_engine u_text (.req(treq), .on(t_on), .in_cell(t_cell), .fg(t_fg), .bg(t_bg), .bg_en(t_bgen));

    // a text layer's colour: glyph pixel, opaque cell, or its graphics.
    // (Everything is passed as an argument: a function that reads module
    // signals directly is not re-evaluated in simulation when they change.)
    function [16:0] tl;                       // {en, colour}
        input own;                            // this layer owns the text engine now
        input en; input [15:0] c;
        input on, incell, bgen; input [15:0] fg, bg;
        begin
            if (own && on)                tl = {1'b1, fg};
            else if (own && incell && bgen) tl = {1'b1, bg};
            else                          tl = {en, c};
        end
    endfunction
    wire [16:0] l_hud  = tl(tsel == 2'd1 && hud_t[`TX_VALID],  hud_en,  hud_c,  t_on, t_cell, t_bgen, t_fg, t_bg);
    wire [16:0] l_menu = tl(tsel == 2'd2 && menu_t[`TX_VALID], menu_en, menu_c, t_on, t_cell, t_bgen, t_fg, t_bg);
    wire [16:0] l_a    = tl(tsel == 2'd3 && a_t[`TX_VALID],    a_en,    a_c,    t_on, t_cell, t_bgen, t_fg, t_bg);

    reg [15:0] mixed;
    always @(*) begin
        if (cur_en)            mixed = cur_c;
        else if (l_hud[16])    mixed = l_hud[15:0];
        else if (l_menu[16])   mixed = l_menu[15:0];
        else if (l_a[16])      mixed = l_a[15:0];
        else if (ball_en)      mixed = ball_c;
        else if (pin_en)       mixed = pin_c;
        else if (lane_en)      mixed = lane_c;
        else                   mixed = `C_BLACK;
    end

    // ---------------- fade-in after a state change -------------------------
    reg [`GS_W-1:0] gs_d;
    reg [3:0] fade;                           // 0..8
    reg [1:0] fsub;
    always @(posedge clk) begin
        if (rst) begin gs_d <= 0; fade <= 4'd8; fsub <= 0; end
        else begin
            gs_d <= game_state;
            // only screen changes fade (not every ball state)
            if (gs_d != game_state && !(game_state >= `GS_AIM && game_state <= `GS_SWEEP &&
                                        gs_d >= `GS_AIM && gs_d <= `GS_SWEEP) &&
                !(game_state == `GS_REPLAY || gs_d == `GS_REPLAY)) begin
                fade <= 4'd0; fsub <= 0;
            end else if (tick_frame && fade != 4'd8) begin
                fsub <= fsub + 2'd1;
                if (fsub[0]) fade <= fade + 4'd1;   // 2 frames per step: 16 frames ~ 0.25 s
            end
        end
    end

    // ---------------- brightness, then fade ---------------------------------
    wire [4:0] r = mixed[15:11];
    wire [5:0] g = mixed[10:5];
    wire [4:0] b = mixed[4:0];
    reg  [4:0] r2, b2;
    reg  [5:0] g2;
    always @(*) begin
        case (settings[`SET_BRI_HI:`SET_BRI_LO])
            2'd3:    begin r2 = r;            g2 = g;            b2 = b;            end
            2'd2:    begin r2 = r - (r >> 2); g2 = g - (g >> 2); b2 = b - (b >> 2); end
            2'd1:    begin r2 = r >> 1;       g2 = g >> 1;       b2 = b >> 1;       end
            default: begin r2 = r >> 2;       g2 = g >> 2;       b2 = b >> 2;       end
        endcase
    end
    wire [8:0] rf = r2 * fade;
    wire [9:0] gf = g2 * fade;
    wire [8:0] bf = b2 * fade;
    wire [15:0] final_c = {rf[7:3], gf[8:3], bf[7:3]};

    // ---------------- capture enable --------------------------------------
    reg [6:0] x_d = 7'd0;
    reg [5:0] y_d = 6'd0;
    reg [2:0] settle = 3'd0;
    always @(posedge clk) begin
        x_d <= px_x;
        y_d <= px_y;
        if (px_x != x_d || px_y != y_d) settle <= 3'd6;
        else if (settle != 3'd0)        settle <= settle - 3'd1;
        if (settle == 3'd1) oled_data <= final_c;
    end
endmodule
