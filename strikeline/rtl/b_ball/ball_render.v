`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// ball_render.v : the ball (in front of the pins) and the physics debug view
//-----------------------------------------------------------------------------
// Owner   : Student B
// Top-down (UI space): a circle drawn by a range check, dx^2 + dy^2 <= 18
//           (radius 4.3 px at 1 px = 1 in), with no multiplier: |dx| <= 4 so
//           the square is a 5-entry table. Light from the top left: a
//           highlight where dx + dy <= -4, shade where dx + dy >= 4. Colour =
//           ball weight. Two finger holes orbit the centre at radius 2: their
//           offset comes from a 64-entry ROM indexed by ball_angle[15:10],
//           which B's physics advances with speed and spin.
// 3-D (v3, VGA; v3.2 at 320 x 240): a shaded sphere of radius b_rad
//           (1..15 px) standing on its floor row: four light bands from the
//           top left, a darker rim, a specular spot, a soft shadow on the lane
//           under it, and the same two finger holes scaled to the projected
//           radius (2 x 2 px on a big ball), so the ball visibly rolls and
//           spins. `depth` = its floor row, used by the compositor to decide
//           whether a pin is in front of the ball.
// Debug   : (sw[2], top-down) the velocity vector as a 1-px line from the
//           centre (1 px per 64 VEL units, ~18 px at 17 mph) and a red cross
//           on the last contact point for 0.5 s.
//=============================================================================
module ball_render (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [8:0]  vx,               // VGA pixel, 320 x 240 (3-D view)
    input  wire [7:0]  vy,
    input  wire [6:0]  ux,               // UI-space pixel (top-down)
    input  wire [5:0]  uy,
    input  wire signed [10:0] cam_y,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire signed [15:0] ball_vx,
    input  wire signed [15:0] ball_vy,
    input  wire        visible,
    input  wire [1:0]  ball_lb,
    input  wire [5:0]  angle,
    input  wire        debug,
    input  wire        fp,               // 3-D view: ball from persp_proj
    input  wire        fb_vis,
    input  wire signed [9:0] fb_x,
    input  wire [7:0]  fb_row,           // floor contact row
    input  wire [3:0]  fb_rad,
    input  wire        contact_pulse,
    input  wire [15:0] contact_px,
    input  wire [15:0] contact_py,
    output reg  [15:0] color,
    output reg         en,
    output wire [7:0]  depth
);
    reg [5:0] marker_rom [0:63];
    initial $readmemh("ball_marker.mem", marker_rom);
    assign depth = fb_row;

    // screen position of the ball centre (top-down)
    wire signed [11:0] bsx = $signed({2'b00, ball_x[15:6]});
    wire signed [11:0] bsy = 12'sd63 - ($signed({2'b00, ball_y[15:6]}) - cam_y);
    wire signed [11:0] dx  = $signed({5'd0, ux}) - bsx;
    wire signed [11:0] dy  = $signed({6'd0, uy}) - bsy;           // screen down
    wire [11:0] adx = dx[11] ? -dx : dx;
    wire [11:0] ady = dy[11] ? -dy : dy;
    function [4:0] sq4;                                            // 0..16
        input [2:0] a;
        case (a) 3'd0: sq4 = 0; 3'd1: sq4 = 1; 3'd2: sq4 = 4; 3'd3: sq4 = 9; default: sq4 = 16; endcase
    endfunction
    wire near = (adx <= 12'd4) && (ady <= 12'd4);
    wire [5:0] r2 = sq4(adx[2:0]) + sq4(ady[2:0]);
    wire in_ball = visible && near && (r2 <= 6'd18);

    // finger holes at angle and angle + 45 degrees
    wire [5:0] h1 = marker_rom[angle];
    wire [5:0] h2 = marker_rom[angle + 6'd8];
    wire signed [2:0] h1x = h1[5:3], h1y = h1[2:0], h2x = h2[5:3], h2y = h2[2:0];
    wire hole = (dx == h1x && dy == h1y) || (dx == h2x && dy == h2y);

    reg [15:0] base;
    always @(*) begin
        case (ball_lb)
            2'd0:    base = 16'h2ADB;            // 12 lb blue
            2'd1:    base = 16'h1D4B;            // 14 lb green
            default: base = 16'hA8E7;            // 16 lb ruby
        endcase
    end
    wire signed [12:0] diag = dx + dy;
    wire [15:0] lit   = base | 16'h4208;                                    // brighter
    wire [15:0] shade = {1'b0, base[15:12], 1'b0, base[10:6], 1'b0, base[4:1]};   // half
    wire [15:0] dark  = {2'b00, base[15:13], 2'b00, base[10:7], 2'b00, base[4:2]}; // quarter

    // ---------------- debug: velocity arrow and contact cross ---------------
    wire signed [11:0] ex = ball_vx >>> 6;                                  // px
    wire signed [11:0] ey = -(ball_vy >>> 6);                               // screen y (down)
    wire [11:0] aex = ex[11] ? -ex : ex;
    wire [11:0] aey = ey[11] ? -ey : ey;
    wire [11:0] vlen = (aex > aey) ? aex + (aey >> 1) : aey + (aex >> 1);  // ~ |v| in px
    wire horiz = aex > (aey << 1);                    // E / W
    wire vert  = aey > (aex << 1);                    // N / S
    wire x_ok = ex[11] ? (dx <= 0) : (dx >= 0);
    wire y_ok = ey[11] ? (dy <= 0) : (dy >= 0);
    wire on_dir = vert  ? (dx == 0 && y_ok) :
                  horiz ? (dy == 0 && x_ok) :
                          (x_ok && y_ok && (adx == ady));
    wire on_vel = (vlen != 0) && on_dir && (adx <= vlen) && (ady <= vlen) && (adx < 12'd40) && (ady < 12'd40);

    reg [4:0] ct_frames;                      // 0.5 s of contact marker
    always @(posedge clk) begin
        if (rst) ct_frames <= 5'd0;
        else if (contact_pulse) ct_frames <= 5'd30;
        else if (tick_frame && ct_frames != 0) ct_frames <= ct_frames - 5'd1;
    end
    reg [15:0] cx_l, cy_l;
    always @(posedge clk) if (contact_pulse) begin
        cx_l <= (ball_x >> 1) + (contact_px >> 1);
        cy_l <= (ball_y >> 1) + (contact_py >> 1);
    end
    wire signed [11:0] csx = $signed({2'b00, cx_l[15:6]});
    wire signed [11:0] csy = 12'sd63 - ($signed({2'b00, cy_l[15:6]}) - cam_y);
    wire signed [11:0] cdx = $signed({5'd0, ux}) - csx;
    wire signed [11:0] cdy = $signed({6'd0, uy}) - csy;
    wire on_cross = (ct_frames != 0) && ((cdx == 0 && (cdy >= -2 && cdy <= 2)) ||
                                         (cdy == 0 && (cdx >= -2 && cdx <= 2)));

    // ---------------- 3-D: sphere of radius fb_rad standing on row fb_row ----
    wire signed [10:0] fdx = $signed({2'b00, vx}) - $signed({fb_x[9], fb_x});
    wire signed [10:0] fdy = $signed({3'b000, vy}) - ($signed({3'b000, fb_row}) - $signed({7'd0, fb_rad}));
    wire [10:0] afx = fdx[10] ? -fdx : fdx;
    wire [10:0] afy = fdy[10] ? -fdy : fdy;
    wire [7:0]  fr2 = fb_rad * fb_rad;
    wire [9:0]  fd2 = afx[4:0] * afx[4:0] + afy[4:0] * afy[4:0];
    wire in_fb = fb_vis && afx <= 11'd16 && afy <= 11'd16 && (fd2 <= {2'b00, fr2} + {7'd0, fb_rad[3:1]});
    // rim: the outer ring of a big ball (d^2 > r^2 - r) is drawn darker
    wire f_rim  = (fb_rad >= 4'd6) && (fd2 + {6'd0, fb_rad} > {2'b00, fr2});
    // light bands from the top left: s = fdx + fdy relative to the radius
    wire signed [11:0] fsum = fdx + fdy;
    wire signed [11:0] rh   = $signed({8'd0, fb_rad[3:1]});           // r / 2
    wire signed [11:0] rr   = $signed({8'd0, fb_rad});
    wire signed [10:0] sx_c = fdx + $signed({8'd0, fb_rad[3:1]}), sy_c = fdy + $signed({8'd0, fb_rad[3:1]});
    wire f_spec = (fb_rad >= 4'd8) ? (sx_c >= -11'sd1 && sx_c <= 11'sd0 && sy_c >= -11'sd1 && sy_c <= 11'sd0)
                                   : (sx_c == 11'sd0 && sy_c == 11'sd0);
    wire f_lit  = fsum < -rh;
    wire f_dark = fsum > rr;
    wire f_shd  = fsum > rh;
    // finger holes on the 3-D ball: the ROM offset (radius 2) scaled by rad / 4
    wire signed [7:0] fh1x = (h1x * $signed({1'b0, fb_rad})) >>> 2, fh1y = (h1y * $signed({1'b0, fb_rad})) >>> 2;
    wire signed [7:0] fh2x = (h2x * $signed({1'b0, fb_rad})) >>> 2, fh2y = (h2y * $signed({1'b0, fb_rad})) >>> 2;
    wire signed [10:0] e1x = fdx - fh1x, e1y = fdy - fh1y, e2x = fdx - fh2x, e2y = fdy - fh2y;
    wire big_h = (fb_rad >= 4'd10);
    wire f_hole = (e1x == 0 && e1y == 0) || (e2x == 0 && e2y == 0) ||
                  (fb_rad >= 4'd6 && ((e1x == 1 && e1y == 0) || (e2x == 1 && e2y == 0))) ||
                  (big_h && (((e1x == 0 || e1x == 1) && e1y == 1) || ((e2x == 0 || e2x == 1) && e2y == 1)));
    // shadow: a flat ellipse on the floor (2 rows), slightly to the right
    wire signed [10:0] sdy = $signed({3'b000, vy}) - $signed({3'b000, fb_row});
    wire signed [10:0] sdx = fdx - $signed({8'd0, fb_rad[3:2]});
    wire [10:0] asx = sdx[10] ? -sdx : sdx;
    wire in_shadow = fb_vis && (sdy >= -11'sd2) && (sdy <= 11'sd0) &&
                     (asx <= {7'd0, fb_rad} - ((sdy == -11'sd2) ? 11'd2 : 11'd0));
    // v3.4: the oiled lane is glossy: a faint mirror image of the ball's
    // lower half just below its contact row, narrowing with distance
    wire [10:0] afd = fdx[10] ? -fdx : fdx;
    wire in_refl = fb_vis && (fb_rad >= 4'd3) && (sdy >= 11'sd1) && (sdy <= $signed({8'd0, fb_rad[3:1]})) &&
                   (afd + sdy[10:0] <= {7'd0, fb_rad});
    // half ball colour, half lane wood (a blend with a constant, no read-back)
    wire [15:0] refl = {1'b0, base[15:12], 1'b0, base[10:6], 1'b0, base[4:1]} + 16'h6B28;

    always @(*) begin
        en = 1'b0; color = base;
        if (fp) begin
            if (vx < `H_VIEW_W && vy >= `H_TOP_H) begin
                if (in_fb) begin
                    en = 1'b1;
                    color = f_hole ? 16'h1082 : f_spec ? `C_WHITE : f_lit ? lit :
                            (f_dark || f_rim) ? dark : f_shd ? shade : base;
                end else if (in_shadow) begin
                    en = 1'b1; color = 16'h2104;
                end else if (in_refl) begin
                    en = 1'b1; color = refl;
                end
            end
        end else if (ux < `SCR_LANE_W) begin
            if (debug && on_cross)       begin en = 1'b1; color = `C_RED;   end
            else if (in_ball) begin
                en = 1'b1;
                if (hole)                color = 16'h2104;
                else if (diag <= -4)     color = lit;
                else if (diag >= 4)      color = shade;
                else                     color = base;
            end
            else if (debug && visible && on_vel) begin en = 1'b1; color = `C_CYAN; end
        end
    end
endmodule
