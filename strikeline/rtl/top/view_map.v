`timescale 1ns / 1ps
`include "strike_defs.vh"
// view_map.v : which picture a scanned pixel belongs to, and its UI position
// Owner: Student B

module view_map (
    input  wire        scr,
    input  wire [7:0]  sx,
    input  wire [6:0]  sy,
    input  wire [8:0]  hx,
    input  wire [7:0]  hy,
    input  wire [`GS_W-1:0] game_state,
    input  wire        classic,
    input  wire        replay,
    output wire [6:0]  ux,
    output wire [5:0]  uy,
    output wire        u_in,
    output wire        v3d,
    output wire        rp_full
);

    // ---------- 1. Which picture this pixel is in ----------
    // Is this pixel inside the 96 x 64 window on the VGA screen?
    wire [7:0] dx = sx - `UI_X0;
    wire [6:0] dy = sy - `UI_Y0;
    wire in_win = (sx >= `UI_X0) && (sx < `UI_X0 + 8'd96) && (sy >= `UI_Y0) && (sy < `UI_Y0 + 7'd64);
    wire play   = (game_state >= `GS_AIM) && (game_state <= `GS_SWEEP);

    assign v3d = !scr && play && !classic && !replay;
    assign rp_full = !scr && replay;

    // ---------- 2. Full-screen replay stretches the lane over the whole picture ----------
    // Multiply by 17/64 to fit the lane across the screen
    wire [8:0]  rx  = hx - 9'd48;
    wire [13:0] rxm = rx * 5'd17;
    wire [12:0] rym = hy * 5'd17;
    wire [7:0]  rux = rxm[13:6];
    wire        r_on = (hx >= 9'd48) && (rux < 8'd60);

    // ---------- 3. Top-down position for each case ----------
    assign u_in = scr ? 1'b1 : rp_full ? r_on : (in_win && !v3d);
    assign ux = scr ? sx[6:0] : rp_full ? rux[6:0] : dx[6:0];
    assign uy = scr ? sy[5:0] : rp_full ? rym[11:6] : dy[5:0];
endmodule
