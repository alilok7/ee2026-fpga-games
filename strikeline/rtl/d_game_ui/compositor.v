`timescale 1ns / 1ps
`include "strike_defs.vh"
// compositor.v : all layers -> one pixel (text engine, layer order, brightness, fade)
// Student D. pix is captured on cap; the XDC gives paths into u_comp/pix_reg
// 7 clocks, so the register must stay named pix.

// one text layer: glyph pixel, opaque cell, or own graphics
module text_layer (
    input  wire        own,
    input  wire        en_in,            // the layer's own graphics
    input  wire [15:0] c_in,
    input  wire        on,               // text engine: glyph bit set
    input  wire        in_cell,
    input  wire        bg_en,
    input  wire [15:0] fg, bg,
    output wire        en_out,
    output wire [15:0] c_out
);
    wire glyph = own && on;                        // a letter pixel
    wire opaque = own && in_cell && bg_en;
    assign en_out = glyph || opaque || en_in;
    assign c_out  = glyph ? fg : opaque ? bg : c_in;
endmodule

module compositor (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire        cap,
    input  wire        scr,
    input  wire        v3d,
    input  wire        u_in,
    input  wire        rp_full,          // full-screen replay on the VGA
    input  wire [`GS_W-1:0] game_state,
    input  wire [`SET_W-1:0] settings,
    input  wire        cur_en,   input wire [15:0] cur_c,                            // A cursor
    input  wire        vh_en,    input wire [15:0] vh_c,   input wire [`TX_W-1:0] vh_t,   // D vga_hud
    input  wire        sc_en,    input wire [15:0] sc_c,   input wire [`TX_W-1:0] sc_t,   // C scorecard
    input  wire        hud_en,   input wire [15:0] hud_c,  input wire [`TX_W-1:0] hud_t,  // C HUD
    input  wire        menu_en,  input wire [15:0] menu_c, input wire [`TX_W-1:0] menu_t, // D menus
    input  wire        a_en,     input wire [15:0] a_c,    input wire [`TX_W-1:0] a_t,    // A trail / meters
    input  wire        ball_en,  input wire [15:0] ball_c, input wire [7:0] ball_depth,   // B ball
    input  wire        pin_en,   input wire [15:0] pin_c,  input wire [7:0] pin_depth,    // C pins
    input  wire        lane_en,  input wire [15:0] lane_c,                                // B lane
    input  wire        bd_en,    input wire [15:0] bd_c,                                  // B backdrop
    output reg  [15:0] pix
);
    // which kind of picture is this pixel in
    wire vga_out_win = !scr && !v3d && !u_in && !rp_full;     // VGA backdrop around the window
    wire ui          = !v3d && u_in && !rp_full;              // the UI picture

    // 1. the first valid text request (in its own picture) goes to the one text engine
    wire vh_v   = (v3d || vga_out_win || rp_full) && vh_t[`TX_VALID];
    wire sc_v   = ui && sc_t[`TX_VALID];
    wire hud_v  = ui && hud_t[`TX_VALID];
    wire menu_v = ui && menu_t[`TX_VALID];
    wire a_v    = (ui || v3d) && a_t[`TX_VALID];
    // priority encoder: vga_hud > scorecard > HUD > menus > A
    wire [2:0] tsel = vh_v ? 3'd4 : sc_v ? 3'd0 : hud_v ? 3'd1 : menu_v ? 3'd2 : 3'd3;
    wire [`TX_W-1:0] treq = (tsel == 3'd4) ? vh_t : (tsel == 3'd0) ? sc_t : (tsel == 3'd1) ? hud_t :
                            (tsel == 3'd2) ? menu_t : (a_v ? a_t : {`TX_W{1'b0}});
    // the shared text engine (A's)
    wire t_on, t_cell, t_bgen;
    wire [15:0] t_fg, t_bg;
    text_engine u_text (.req(treq), .on(t_on), .in_cell(t_cell), .fg(t_fg), .bg(t_bg), .bg_en(t_bgen));

    // each text layer: glyph pixel / opaque cell / its own graphics (structural, 5 instances)
    wire        l_vh_en, l_sc_en, l_hud_en, l_menu_en, l_a_en;
    wire [15:0] l_vh_c,  l_sc_c,  l_hud_c,  l_menu_c,  l_a_c;
    // 5 text layers: letter pixel, opaque cell, or the layer's own colour
    text_layer tl_vh   (.own(tsel == 3'd4 && vh_v),   .en_in(vh_en),   .c_in(vh_c),   .on(t_on), .in_cell(t_cell),
                        .bg_en(t_bgen), .fg(t_fg), .bg(t_bg), .en_out(l_vh_en),   .c_out(l_vh_c));
    text_layer tl_sc   (.own(tsel == 3'd0 && sc_v),   .en_in(sc_en),   .c_in(sc_c),   .on(t_on), .in_cell(t_cell),
                        .bg_en(t_bgen), .fg(t_fg), .bg(t_bg), .en_out(l_sc_en),   .c_out(l_sc_c));
    text_layer tl_hud  (.own(tsel == 3'd1 && hud_v),  .en_in(hud_en),  .c_in(hud_c),  .on(t_on), .in_cell(t_cell),
                        .bg_en(t_bgen), .fg(t_fg), .bg(t_bg), .en_out(l_hud_en),  .c_out(l_hud_c));
    text_layer tl_menu (.own(tsel == 3'd2 && menu_v), .en_in(menu_en), .c_in(menu_c), .on(t_on), .in_cell(t_cell),
                        .bg_en(t_bgen), .fg(t_fg), .bg(t_bg), .en_out(l_menu_en), .c_out(l_menu_c));
    text_layer tl_a    (.own(tsel == 3'd3 && a_v),    .en_in(a_en),    .c_in(a_c),    .on(t_on), .in_cell(t_cell),
                        .bg_en(t_bgen), .fg(t_fg), .bg(t_bg), .en_out(l_a_en),    .c_out(l_a_c));

    // 2. priority mux: front-most layer that draws (a nearer pin covers the ball)
    wire pin_front = pin_en && (!ball_en || pin_depth > ball_depth);

    // the front-most layer that draws wins
    reg [15:0] mixed;
    always @(*) begin
        mixed = `C_BLACK;
        if (rp_full) begin                                   // full-screen replay
            if (l_vh_en)       mixed = l_vh_c;
            else if (u_in) begin
                if (ball_en)       mixed = ball_c;
                else if (pin_en)   mixed = pin_c;
                else if (lane_en)  mixed = lane_c;
            end
        end else if (cur_en)       mixed = cur_c;            // the pointer is always in front
        else if (vga_out_win) begin                          // around the UI window
            if (l_vh_en)       mixed = l_vh_c;
        end else if (v3d) begin                              // 3-D game
            if (l_vh_en)           mixed = l_vh_c;
            else if (l_a_en)       mixed = l_a_c;
            else if (pin_front)    mixed = pin_c;
            else if (ball_en)      mixed = ball_c;
            else if (pin_en)       mixed = pin_c;
            else if (bd_en)        mixed = bd_c;
            else if (lane_en)      mixed = lane_c;
        end else begin                                       // UI picture
            if (l_sc_en)           mixed = l_sc_c;
            else if (l_hud_en)     mixed = l_hud_c;
            else if (l_menu_en)    mixed = l_menu_c;
            else if (l_a_en)       mixed = l_a_c;
            else if (ball_en)      mixed = ball_c;
            else if (pin_en)       mixed = pin_c;
            else if (lane_en)      mixed = lane_c;
        end
    end

    // 4. fade-in: back to 0 on a screen change, +1 every 2 frames (ball states don't fade)
    reg [`GS_W-1:0] gs_d;                                    // game_state one clock ago
    reg [3:0] fade;                                          // 0 = black .. 8 = full
    reg [1:0] fsub;                                          // counts frames inside a step
    wire in_ball_now  = (game_state >= `GS_AIM) && (game_state <= `GS_SWEEP);
    wire in_ball_was  = (gs_d >= `GS_AIM) && (gs_d <= `GS_SWEEP);
    wire screen_change = (gs_d != game_state) && !(in_ball_now && in_ball_was) &&
                         !(game_state == `GS_REPLAY || gs_d == `GS_REPLAY);
    // fade counter
    always @(posedge clk) begin
        if (rst) begin
            gs_d <= 0; fade <= 4'd8; fsub <= 0;
        end else begin
            gs_d <= game_state;
            if (screen_change) begin
                fade <= 4'd0; fsub <= 0;
            end else if (tick_frame && fade != 4'd8) begin
                fsub <= fsub + 2'd1;
                if (fsub[0]) fade <= fade + 4'd1;
            end
        end
    end

    // 3. brightness (shifts), then the fade (x fade / 8)
    wire [4:0] r = mixed[15:11];                             // RGB565
    wire [5:0] g = mixed[10:5];
    wire [4:0] b = mixed[4:0];
    reg  [4:0] r2, b2;
    reg  [5:0] g2;
    // brightness: x1, x3/4, x1/2, x1/4
    always @(*) begin
        case (settings[`SET_BRI_HI:`SET_BRI_LO])
            2'd3:    begin r2 = r;            g2 = g;            b2 = b;            end   // x 1
            2'd2:    begin r2 = r - (r >> 2); g2 = g - (g >> 2); b2 = b - (b >> 2); end   // x 3/4
            2'd1:    begin r2 = r >> 1;       g2 = g >> 1;       b2 = b >> 1;       end   // x 1/2
            default: begin r2 = r >> 2;       g2 = g >> 2;       b2 = b >> 2;       end   // x 1/4
        endcase
    end
    wire [8:0]  rf = r2 * fade;                              // x fade ...
    wire [9:0]  gf = g2 * fade;
    wire [8:0]  bf = b2 * fade;
    wire [15:0] final_c = {rf[7:3], gf[8:3], bf[7:3]};       // ... / 8

    // 5. the capture register (the XDC multicycle path ends here)
    always @(posedge clk) begin
        if (cap) pix <= final_c;
    end
endmodule
