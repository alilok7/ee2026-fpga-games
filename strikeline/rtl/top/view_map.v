`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// view_map.v - which picture a scanned pixel belongs to, and its UI-space position (v3)
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student D (integration)
// Purpose : every renderer is a function of the pixel. This module turns the
//           scanned pixel (scr, sx, sy) into the coordinates each one needs:
//   OLED pass        : UI space = the pixel itself (96 x 64), always inside
//   VGA, 3-D play    : v3d = 1, the renderers use the VGA pixel directly
//   VGA, replay      : (v3.3) rp_full = 1: the top-down replay fills the screen
//                      with no frame. The 60 in of lane are stretched 3.75x
//                      over the 320 x 240 picture (hx, hy):
//                        ux = (hx - 48) * 17 / 64,  uy = hy * 17 / 64
//                      u_in = on the lane (ux < 60); vga_hud draws the rest
//   VGA, otherwise   : the UI picture in a window at (UI_X0, UI_Y0):
//                      ux = sx - 32, uy = sy - 28, u_in = inside the window
//   3-D play = the VGA during a game (AIM .. SWEEP), unless sw[4] asks for the
//   classic top-down view.
//=============================================================================
module view_map (
    input  wire        scr,
    input  wire [7:0]  sx,               // 160 x 120 position
    input  wire [6:0]  sy,
    input  wire [8:0]  hx,               // 320 x 240 position (VGA pass)
    input  wire [7:0]  hy,
    input  wire [`GS_W-1:0] game_state,
    input  wire        classic,          // sw[4]: top-down view on the VGA too
    input  wire        replay,           // instant replay is showing
    output wire [6:0]  ux,
    output wire [5:0]  uy,
    output wire        u_in,
    output wire        v3d,
    output wire        rp_full           // v3.3: full-screen replay on the VGA
);
    wire [7:0] dx = sx - `UI_X0;
    wire [6:0] dy = sy - `UI_Y0;
    wire in_win = (sx >= `UI_X0) && (sx < `UI_X0 + 8'd96) && (sy >= `UI_Y0) && (sy < `UI_Y0 + 7'd64);
    wire play   = (game_state >= `GS_AIM) && (game_state <= `GS_SWEEP);
    assign v3d  = !scr && play && !classic && !replay;
    assign rp_full = !scr && replay;
    // full-screen replay: x 17/64 (= 1 / 3.76), y the same
    wire [8:0]  rx  = hx - 9'd48;
    wire [13:0] rxm = rx * 5'd17;
    wire [12:0] rym = hy * 5'd17;
    wire [7:0]  rux = rxm[13:6];
    wire        r_on = (hx >= 9'd48) && (rux < 8'd60);
    assign u_in = scr ? 1'b1 : rp_full ? r_on : (in_win && !v3d);
    assign ux   = scr ? sx[6:0] : rp_full ? rux[6:0] : dx[6:0];
    assign uy   = scr ? sy[5:0] : rp_full ? rym[11:6] : dy[5:0];
endmodule
