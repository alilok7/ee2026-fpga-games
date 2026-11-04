`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// ball_render.v : the ball (in front of the pins) and the physics debug view
//-----------------------------------------------------------------------------
// Owner   : Student B
// Ball    : a circle drawn by a range check, dx^2 + dy^2 <= 18 (radius 4.3 px
//           at 1 px = 1 in), with no multiplier: |dx| <= 4 so the square is
//           a 5-entry table. Light from the top left: a highlight where
//           dx + dy <= -4, shade where dx + dy >= 4. Colour = ball weight.
//           Two finger holes orbit the centre at radius 2: their offset comes
//           from a 64-entry ROM indexed by ball_angle[15:10], which B's
//           physics advances with speed and spin, so a hook ball visibly spins.
// Debug   : (sw[2]) the velocity vector as a 1-px line from the centre
//           (length 1 px per 64 VEL units, ~18 px at 17 mph) and a red cross
//           on the last contact point for 0.5 s.
//           A pixel (dx, dy) is on the segment 0 -> (ex, ey) when
//             |dx*ey - dy*ex| <= max(|ex|, |ey|)        (distance <= ~1 px)
//             0 <= dx*ex + dy*ey <= ex^2 + ey^2          (between the ends)
//=============================================================================
module ball_render (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire signed [10:0] cam_y,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire signed [15:0] ball_vx,
    input  wire signed [15:0] ball_vy,
    input  wire        visible,
    input  wire [1:0]  ball_lb,
    input  wire [5:0]  angle,
    input  wire        debug,
    input  wire        fp,               // first-person view: ball from persp_proj
    input  wire        fb_vis,
    input  wire signed [7:0] fb_x,
    input  wire [5:0]  fb_row,           // floor contact row
    input  wire [2:0]  fb_rad,
    input  wire        contact_pulse,
    input  wire [15:0] contact_px,
    input  wire [15:0] contact_py,
    output reg  [15:0] color,
    output reg         en
);
    reg [5:0] marker_rom [0:63];
    initial $readmemh("ball_marker.mem", marker_rom);

    // screen position of the ball centre
    wire signed [11:0] bsx = $signed({2'b00, ball_x[15:6]});
    wire signed [11:0] bsy = 12'sd63 - ($signed({2'b00, ball_y[15:6]}) - cam_y);
    wire signed [11:0] dx  = $signed({5'd0, px_x}) - bsx;
    wire signed [11:0] dy  = $signed({6'd0, px_y}) - bsy;           // screen down
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

    // ---------------- debug: velocity arrow and contact cross ---------------
    // The velocity is drawn as an arrow in one of 8 directions (the same
    // octants as the pin fall directions) with a length of 1 px per 64 VEL
    // units (~18 px at 17 mph). Only comparisons, no multipliers: a pixel is
    // on the arrow if it lies on that axis / diagonal from the ball centre
    // and within the length.
    wire signed [11:0] ex = ball_vx >>> 6;                                  // px
    wire signed [11:0] ey = -(ball_vy >>> 6);                               // screen y (down)
    wire [11:0] aex = ex[11] ? -ex : ex;
    wire [11:0] aey = ey[11] ? -ey : ey;
    wire [11:0] vlen = (aex > aey) ? aex + (aey >> 1) : aey + (aex >> 1);  // ~ |v| in px
    wire horiz = aex > (aey << 1);                    // E / W
    wire vert  = aey > (aex << 1);                    // N / S
    // screen axes: +x right, +y DOWN. ex = vx and ey = -vy are the arrow's
    // screen components, so the arrow's pixels have the same signs as (ex, ey)
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
    // contact point = midpoint of ball and pin centres, latched with the cross
    reg [15:0] cx_l, cy_l;
    always @(posedge clk) if (contact_pulse) begin
        cx_l <= (ball_x >> 1) + (contact_px >> 1);
        cy_l <= (ball_y >> 1) + (contact_py >> 1);
    end
    wire signed [11:0] csx = $signed({2'b00, cx_l[15:6]});
    wire signed [11:0] csy = 12'sd63 - ($signed({2'b00, cy_l[15:6]}) - cam_y);
    wire signed [11:0] cdx = $signed({5'd0, px_x}) - csx;
    wire signed [11:0] cdy = $signed({6'd0, px_y}) - csy;
    wire on_cross = (ct_frames != 0) && ((cdx == 0 && (cdy >= -2 && cdy <= 2)) ||
                                         (cdy == 0 && (cdx >= -2 && cdx <= 2)));

    // first person: a circle of radius fb_rad standing on row fb_row
    wire signed [8:0] fdx = $signed({2'b00, px_x}) - $signed({fb_x[7], fb_x});
    wire signed [8:0] fdy = $signed({3'b000, px_y}) - ($signed({3'b000, fb_row}) - $signed({6'd0, fb_rad}));
    wire [8:0] afx = fdx[8] ? -fdx : fdx;
    wire [8:0] afy = fdy[8] ? -fdy : fdy;
    wire [7:0] fr2 = fb_rad * fb_rad;
    wire in_fb = fb_vis && afx <= 9'd8 && afy <= 9'd8 &&
                 ({4'd0, afx[3:0]} * afx[3:0] + {4'd0, afy[3:0]} * afy[3:0] <= {1'b0, fr2} + 9'd1);
    wire fb_lit = (fdx + fdy) < -$signed({6'd0, fb_rad});

    always @(*) begin
        en = 1'b0; color = base;
        if (fp) begin
            if (px_x < `SCR_LANE_W && in_fb) begin en = 1'b1; color = fb_lit ? lit : base; end
        end else if (px_x < `SCR_LANE_W) begin
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
