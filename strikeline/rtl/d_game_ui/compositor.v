`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// compositor.v : layers -> one pixel colour for the frame buffers
//-----------------------------------------------------------------------------
// Owner   : Student D
// Layers (front to back), v3: it depends on which picture this pixel is in
//   UI picture (the OLED, and the VGA's 96 x 64 window):
//     A cursor > D scorecard > D HUD/popups > D menus > A trail/meters/labels
//     > B ball > C pins > B lane > black                    (as in v2)
//   VGA 3-D game layout (v3d):
//     A cursor > D vga_hud (strip, panel, popups) > A trail
//     > B ball / C pins (the NEARER one: larger screen row) > B lane > black
//   VGA outside the window (menus etc.): A cursor > D vga_hud backdrop
//   VGA full-screen replay (v3.3, rp_full): D vga_hud (camera overlay, sides)
//     > B ball > C pins > B lane (top-down, stretched); no pointer, no HUD
//   Each layer says "I draw this pixel" (en) and its colour. Text layers also
//   send a text request; the FIRST valid request in that order goes to the
//   one shared text_engine, and the glyph pixel (fg), the cell background
//   (bg, when opaque) or the layer's own graphics are used for that layer.
// Post-processing, applied once to the final colour:
//   brightness 4 levels (x1, 3/4, 1/2, 1/4 with shifts)
//   fade-in: after every change of game_state the picture ramps from black
//   to full in 200 ms: channel * level / 8, level 0..8.
// Timing : render_scan holds each pixel position for 8 clocks and pulses
//   `cap` on the 7th; the XDC gives every path into pix 7 clocks.
//=============================================================================
module compositor (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire        cap,              // render_scan: capture this pixel now
    input  wire        scr,              // 0 = VGA, 1 = OLED
    input  wire        v3d,              // VGA 3-D game layout
    input  wire        u_in,             // inside the UI picture
    input  wire        rp_full,          // v3.3: full-screen replay on the VGA
    input  wire [`GS_W-1:0] game_state,
    input  wire [`SET_W-1:0] settings,
    input  wire        cur_en,   input wire [15:0] cur_c,
    input  wire        vh_en,    input wire [15:0] vh_c,   input wire [`TX_W-1:0] vh_t,
    input  wire        sc_en,    input wire [15:0] sc_c,   input wire [`TX_W-1:0] sc_t,
    input  wire        hud_en,   input wire [15:0] hud_c,  input wire [`TX_W-1:0] hud_t,
    input  wire        menu_en,  input wire [15:0] menu_c, input wire [`TX_W-1:0] menu_t,
    input  wire        a_en,     input wire [15:0] a_c,    input wire [`TX_W-1:0] a_t,
    input  wire        ball_en,  input wire [15:0] ball_c, input wire [7:0] ball_depth,
    input  wire        pin_en,   input wire [15:0] pin_c,  input wire [7:0] pin_depth,
    input  wire        lane_en,  input wire [15:0] lane_c,
    output reg  [15:0] pix
);
    wire vga_out_win = !scr && !v3d && !u_in && !rp_full; // VGA backdrop around the window
    wire ui          = !v3d && u_in && !rp_full;        // the UI picture
    // ---------------- shared text engine ----------------------------------
    // the request of each layer counts only in its own picture
    wire vh_v   = (v3d || vga_out_win || rp_full) && vh_t[`TX_VALID];
    wire sc_v   = ui && sc_t[`TX_VALID];
    wire hud_v  = ui && hud_t[`TX_VALID];
    wire menu_v = ui && menu_t[`TX_VALID];
    wire a_v    = (ui || v3d) && a_t[`TX_VALID];
    wire [2:0] tsel = vh_v ? 3'd4 : sc_v ? 3'd0 : hud_v ? 3'd1 : menu_v ? 3'd2 : 3'd3;
    wire [`TX_W-1:0] treq = (tsel == 3'd4) ? vh_t : (tsel == 3'd0) ? sc_t : (tsel == 3'd1) ? hud_t :
                            (tsel == 3'd2) ? menu_t : (a_v ? a_t : {`TX_W{1'b0}});
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
    wire [16:0] l_vh   = tl(tsel == 3'd4 && vh_v,   vh_en,   vh_c,   t_on, t_cell, t_bgen, t_fg, t_bg);
    wire [16:0] l_sc   = tl(tsel == 3'd0 && sc_v,   sc_en,   sc_c,   t_on, t_cell, t_bgen, t_fg, t_bg);
    wire [16:0] l_hud  = tl(tsel == 3'd1 && hud_v,  hud_en,  hud_c,  t_on, t_cell, t_bgen, t_fg, t_bg);
    wire [16:0] l_menu = tl(tsel == 3'd2 && menu_v, menu_en, menu_c, t_on, t_cell, t_bgen, t_fg, t_bg);
    wire [16:0] l_a    = tl(tsel == 3'd3 && a_v,    a_en,    a_c,    t_on, t_cell, t_bgen, t_fg, t_bg);

    // in 3-D a pin that is nearer than the ball (lower on the screen) covers it
    wire pin_front = pin_en && (!ball_en || pin_depth > ball_depth);

    reg [15:0] mixed;
    always @(*) begin
        mixed = `C_BLACK;
        if (rp_full) begin
            if (l_vh[16])                        mixed = l_vh[15:0];
            else if (u_in) begin
                if (ball_en)                     mixed = ball_c;
                else if (pin_en)                 mixed = pin_c;
                else if (lane_en)                mixed = lane_c;
            end
        end else if (cur_en)                     mixed = cur_c;
        else if (vga_out_win) begin
            if (l_vh[16])                        mixed = l_vh[15:0];
        end else if (v3d) begin
            if (l_vh[16])                        mixed = l_vh[15:0];
            else if (l_a[16])                    mixed = l_a[15:0];
            else if (pin_front)                  mixed = pin_c;
            else if (ball_en)                    mixed = ball_c;
            else if (pin_en)                     mixed = pin_c;
            else if (lane_en)                    mixed = lane_c;
        end else begin
            if (l_sc[16])                        mixed = l_sc[15:0];
            else if (l_hud[16])                  mixed = l_hud[15:0];
            else if (l_menu[16])                 mixed = l_menu[15:0];
            else if (l_a[16])                    mixed = l_a[15:0];
            else if (ball_en)                    mixed = ball_c;
            else if (pin_en)                     mixed = pin_c;
            else if (lane_en)                    mixed = lane_c;
        end
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

    // ---------------- capture (strobe from render_scan) ---------------------
    always @(posedge clk) if (cap) pix <= final_c;
endmodule
