`timescale 1ns / 1ps
`include "strike_defs.vh"
// ball_render.v : the ball (in front of the pins) and the physics debug view
// Owner: Student B

module ball_render (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [8:0]  vx,
    input  wire [7:0]  vy,
    input  wire [6:0]  ux,
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
    input  wire        fp,
    input  wire        fb_vis,
    input  wire signed [9:0] fb_x,
    input  wire [7:0]  fb_row,
    input  wire [3:0]  fb_rad,
    input  wire        contact_pulse,
    input  wire [15:0] contact_px,
    input  wire [15:0] contact_py,
    output reg  [15:0] color,
    output reg         en,
    output wire [7:0]  depth
);

    assign depth = fb_row;

    // ---------- 1. Ball colours for this weight ----------
    reg [15:0] base;
    always @ (*) begin
        case (ball_lb)
            2'd0:    base = 16'h2ADB;
            2'd1:    base = 16'h1D4B;
            default: base = 16'hA8E7;
        endcase
    end
    wire [15:0] lit   = base | 16'h4208;
    wire [15:0] shade = {1'b0, base[15:12], 1'b0, base[10:6], 1'b0, base[4:1]};
    wire [15:0] dark  = {2'b00, base[15:13], 2'b00, base[10:7], 2'b00, base[4:2]};

    // ---------- 2. Where the white dot and the finger holes are ----------
    wire signed [3:0] dot_x, dot_y, mx, my;
    wire holes_on;

    ball_marks u_marks (
        .angle(angle),
        .dot_x(dot_x),
        .dot_y(dot_y),
        .holes_on(holes_on),
        .mx(mx),
        .my(my)
    );

    // ---------- 3. Top-down ball ----------
    wire signed [11:0] dx, dy;
    wire [11:0] adx, ady;
    wire in_ball, hole, mark;
    wire signed [12:0] diag;

    ball_top u_top (
        .ux(ux),
        .uy(uy),
        .cam_y(cam_y),
        .ball_x(ball_x),
        .ball_y(ball_y),
        .visible(visible),
        .dot_x(dot_x),
        .dot_y(dot_y),
        .holes_on(holes_on),
        .mx(mx),
        .my(my),
        .dx(dx),
        .dy(dy),
        .adx(adx),
        .ady(ady),
        .in_ball(in_ball),
        .hole(hole),
        .mark(mark),
        .diag(diag)
    );

    // ---------- 4. Debug view: speed arrow and contact cross ----------
    wire on_vel, on_cross;

    ball_debug u_debug (
        .clk(clk),
        .rst(rst),
        .tick_frame(tick_frame),
        .ux(ux),
        .uy(uy),
        .cam_y(cam_y),
        .ball_x(ball_x),
        .ball_y(ball_y),
        .ball_vx(ball_vx),
        .ball_vy(ball_vy),
        .dx(dx),
        .dy(dy),
        .adx(adx),
        .ady(ady),
        .contact_pulse(contact_pulse),
        .contact_px(contact_px),
        .contact_py(contact_py),
        .on_vel(on_vel),
        .on_cross(on_cross)
    );

    // ---------- 5. 3-D ball, then its shadow and reflection ----------
    wire signed [10:0] fdx;
    wire [10:0] afx;
    wire [7:0]  fr2;
    wire in_fb;
    wire [15:0] fb_color;

    ball_sphere u_sphere (
        .vx(vx),
        .vy(vy),
        .fb_vis(fb_vis),
        .fb_x(fb_x),
        .fb_row(fb_row),
        .fb_rad(fb_rad),
        .dot_x(dot_x),
        .dot_y(dot_y),
        .holes_on(holes_on),
        .mx(mx),
        .my(my),
        .base(base),
        .lit(lit),
        .shade(shade),
        .dark(dark),
        .fdx(fdx),
        .afx(afx),
        .fr2(fr2),
        .in_fb(in_fb),
        .fb_color(fb_color)
    );

    wire in_shadow, in_refl, near_r;

    ball_shadow u_shadow (
        .vx(vx),
        .vy(vy),
        .fb_vis(fb_vis),
        .fb_row(fb_row),
        .fb_rad(fb_rad),
        .fdx(fdx),
        .afx(afx),
        .fr2(fr2),
        .in_shadow(in_shadow),
        .in_refl(in_refl),
        .near_r(near_r)
    );

    // ---------- 6. Pick what to draw ----------
    always @ (*) begin
        en = 1'b0;
        color = base;
        if (fp) begin
            if (vx < `H_VIEW_W && vy >= `H_TOP_H) begin
                if (in_fb) begin
                    en = 1'b1;
                    color = fb_color;
                end
                else if (in_shadow) begin
                    en = 1'b1;
                    color = 16'h2104;
                end
                else if (in_refl) begin
                    en = 1'b1;
                    color = near_r ? shade : dark;
                end
            end
        end
        else if (ux < `SCR_LANE_W) begin
            if (debug && on_cross) begin
                en = 1'b1;
                color = `C_RED;
            end
            else if (in_ball) begin
                en = 1'b1;
                if (hole)
                    color = 16'h2104;
                else if (mark)
                    color = 16'hFFFF;
                else if (diag <= -4)
                    color = lit;
                else if (diag >= 4)
                    color = shade;
                else
                    color = base;
            end
            else if (debug && visible && on_vel) begin
                en = 1'b1;
                color = `C_CYAN;
            end
        end
    end
endmodule


// White dot circles the centre; three holes roll up the ball and slant with the spin
module ball_marks (
    input  wire [5:0] angle,
    output reg  signed [3:0] dot_x,
    output reg  signed [3:0] dot_y,
    output wire       holes_on,
    output wire signed [3:0] mx,
    output reg  signed [3:0] my
);
    // Fields of angle: roll position, side of the spin, how much spin is left
    wire [2:0] roll = angle[5:3];
    wire       right = angle[2];
    wire [1:0] amount = angle[1:0];
    wire [2:0] dot_pos = right ? -roll : roll;

    // White dot: 8 positions on a circle. Right spin runs them the other way
    always @ (*) begin
        case (dot_pos)
            3'd0: begin
                dot_x = 4'sd2;
                dot_y = 4'sd0;
            end
            3'd1: begin
                dot_x = 4'sd1;
                dot_y = -4'sd1;
            end
            3'd2: begin
                dot_x = 4'sd0;
                dot_y = -4'sd2;
            end
            3'd3: begin
                dot_x = -4'sd1;
                dot_y = -4'sd1;
            end
            3'd4: begin
                dot_x = -4'sd2;
                dot_y = 4'sd0;
            end
            3'd5: begin
                dot_x = -4'sd1;
                dot_y = 4'sd1;
            end
            3'd6: begin
                dot_x = 4'sd0;
                dot_y = 4'sd2;
            end
            default: begin
                dot_x = 4'sd1;
                dot_y = 4'sd1;
            end
        endcase
    end

    // The holes show for half of the roll and move up the ball
    assign holes_on = !roll[2];

    always @ (*) begin
        case (roll[1:0])
            2'd0:    my = 4'sd3;
            2'd1:    my = 4'sd1;
            2'd2:    my = -4'sd1;
            default: my = -4'sd3;
        endcase
    end

    // The holes drift sideways as they roll. More spin left means a wider drift
    reg signed [3:0] slant;
    always @ (*) begin
        case ({amount, roll[1:0]})
            4'b01_00: slant = 4'sd1;
            4'b01_11: slant = -4'sd1;
            4'b10_00: slant = 4'sd2;
            4'b10_01: slant = 4'sd1;
            4'b10_10: slant = -4'sd1;
            4'b10_11: slant = -4'sd2;
            4'b11_00: slant = 4'sd3;
            4'b11_01: slant = 4'sd1;
            4'b11_10: slant = -4'sd1;
            4'b11_11: slant = -4'sd3;
            default:  slant = 4'sd0;
        endcase
    end

    assign mx = right ? -slant : slant;
endmodule


// The top-down ball: a circle check, its marks and which way the light falls
module ball_top (
    input  wire [6:0]  ux,
    input  wire [5:0]  uy,
    input  wire signed [10:0] cam_y,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire        visible,
    input  wire signed [3:0] dot_x,
    input  wire signed [3:0] dot_y,
    input  wire        holes_on,
    input  wire signed [3:0] mx,
    input  wire signed [3:0] my,
    output wire signed [11:0] dx,
    output wire signed [11:0] dy,
    output wire [11:0] adx,
    output wire [11:0] ady,
    output wire        in_ball,
    output wire        hole,
    output wire        mark,
    output wire signed [12:0] diag
);
    // Offset of this pixel from the ball centre
    wire signed [11:0] bsx = $signed({2'b00, ball_x[15:6]});
    wire signed [11:0] bsy = 12'sd63 - ($signed({2'b00, ball_y[15:6]}) - cam_y);

    assign dx = $signed({5'd0, ux}) - bsx;
    assign dy = $signed({6'd0, uy}) - bsy;
    assign adx = dx[11] ? -dx : dx;
    assign ady = dy[11] ? -dy : dy;

    // Small table instead of a multiplier, because |d| is at most 4 here
    function [4:0] square;
        input [2:0] a;
        case (a)
            3'd0:    square = 0;
            3'd1:    square = 1;
            3'd2:    square = 4;
            3'd3:    square = 9;
            default: square = 16;
        endcase
    endfunction

    wire near = (adx <= 12'd4) && (ady <= 12'd4);
    wire [5:0] r2 = square(adx[2:0]) + square(ady[2:0]);

    assign in_ball = visible && near && (r2 <= 6'd18);
    // White dot, the three finger holes, and which way the light falls
    assign mark = (dx == dot_x) && (dy == dot_y);
    assign hole = holes_on && (((dx == mx) && (dy == my - 4'sd1)) ||
                               ((dx == mx - 4'sd1) && (dy == my + 4'sd1)) ||
                               ((dx == mx + 4'sd1) && (dy == my + 4'sd1)));
    assign diag = dx + dy;
endmodule


// Debug view: speed arrow, and a cross on the last contact for 0.5 s
module ball_debug (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [6:0]  ux,
    input  wire [5:0]  uy,
    input  wire signed [10:0] cam_y,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire signed [15:0] ball_vx,
    input  wire signed [15:0] ball_vy,
    input  wire signed [11:0] dx,
    input  wire signed [11:0] dy,
    input  wire [11:0] adx,
    input  wire [11:0] ady,
    input  wire        contact_pulse,
    input  wire [15:0] contact_px,
    input  wire [15:0] contact_py,
    output wire        on_vel,
    output wire        on_cross
);
    // Speed arrow: a line from the ball along its velocity
    wire signed [11:0] ex = ball_vx >>> 6;
    wire signed [11:0] ey = -(ball_vy >>> 6);
    wire [11:0] aex = ex[11] ? -ex : ex;
    wire [11:0] aey = ey[11] ? -ey : ey;
    wire [11:0] vlen = (aex > aey) ? aex + (aey >> 1) : aey + (aex >> 1);
    wire horiz = aex > (aey << 1);
    wire vert  = aey > (aex << 1);
    wire x_ok = ex[11] ? (dx <= 0) : (dx >= 0);
    wire y_ok = ey[11] ? (dy <= 0) : (dy >= 0);
    wire on_dir = vert  ? (dx == 0 && y_ok) :
                  horiz ? (dy == 0 && x_ok) :
                          (x_ok && y_ok && (adx == ady));

    assign on_vel = (vlen != 0) && on_dir && (adx <= vlen) && (ady <= vlen) && (adx < 12'd40) && (ady < 12'd40);

    // The contact cross stays on for 30 frames
    reg [4:0] cnt;
    always @ (posedge clk) begin
        if (rst)
            cnt <= 5'd0;
        else if (contact_pulse)
            cnt <= 5'd30;
        else if (tick_frame && cnt != 0)
            cnt <= cnt - 5'd1;
    end

    // Contact point: halfway between the ball and the pin
    reg [15:0] cx_l, cy_l;
    always @ (posedge clk) begin
        if (contact_pulse) begin
            cx_l <= (ball_x >> 1) + (contact_px >> 1);
            cy_l <= (ball_y >> 1) + (contact_py >> 1);
        end
    end

    wire signed [11:0] csx = $signed({2'b00, cx_l[15:6]});
    wire signed [11:0] csy = 12'sd63 - ($signed({2'b00, cy_l[15:6]}) - cam_y);
    wire signed [11:0] cdx = $signed({5'd0, ux}) - csx;
    wire signed [11:0] cdy = $signed({6'd0, uy}) - csy;

    assign on_cross = (cnt != 0) && ((cdx == 0 && (cdy >= -2 && cdy <= 2)) ||
                                       (cdy == 0 && (cdx >= -2 && cdx <= 2)));
endmodule


// The 3-D ball: a shaded sphere of radius fb_rad standing on row fb_row
module ball_sphere (
    input  wire [8:0]  vx,
    input  wire [7:0]  vy,
    input  wire        fb_vis,
    input  wire signed [9:0] fb_x,
    input  wire [7:0]  fb_row,
    input  wire [3:0]  fb_rad,
    input  wire signed [3:0] dot_x,
    input  wire signed [3:0] dot_y,
    input  wire        holes_on,
    input  wire signed [3:0] mx,
    input  wire signed [3:0] my,
    input  wire [15:0] base,
    input  wire [15:0] lit,
    input  wire [15:0] shade,
    input  wire [15:0] dark,
    output wire signed [10:0] fdx,
    output wire [10:0] afx,
    output wire [7:0]  fr2,
    output wire        in_fb,
    output wire [15:0] fb_color
);
    // Offset from the ball centre, then the circle check
    assign fdx = $signed({2'b00, vx}) - $signed({fb_x[9], fb_x});
    wire signed [10:0] fdy = $signed({3'b000, vy}) - ($signed({3'b000, fb_row}) - $signed({7'd0, fb_rad}));
    assign afx = fdx[10] ? -fdx : fdx;
    wire [10:0] afy = fdy[10] ? -fdy : fdy;
    assign fr2 = fb_rad * fb_rad;
    wire [9:0] fd2 = afx[4:0] * afx[4:0] + afy[4:0] * afy[4:0];

    assign in_fb = fb_vis && afx <= 11'd16 && afy <= 11'd16 && (fd2 <= {2'b00, fr2} + {7'd0, fb_rad[3:1]});

    // light bands from the top left, a darker rim and a bright spot
    wire f_rim = (fb_rad >= 4'd6) && (fd2 + {6'd0, fb_rad} > {2'b00, fr2});
    wire signed [11:0] fsum = fdx + fdy;
    wire signed [11:0] rh = $signed({8'd0, fb_rad[3:1]});
    wire signed [11:0] rr = $signed({8'd0, fb_rad});
    wire signed [10:0] sx_c = fdx + $signed({8'd0, fb_rad[3:1]});
    wire signed [10:0] sy_c = fdy + $signed({8'd0, fb_rad[3:1]});
    wire f_spec = (fb_rad >= 4'd8) ? (sx_c >= -11'sd1 && sx_c <= 11'sd0 && sy_c >= -11'sd1 && sy_c <= 11'sd0)
                                   : (sx_c == 11'sd0 && sy_c == 11'sd0);
    wire f_lit  = fsum < -rh;
    wire f_dark = fsum > rr;
    wire f_shd  = fsum > rh;

    // the same dot and holes, scaled by rad / 4
    wire signed [8:0] fdot_x = (dot_x * $signed({1'b0, fb_rad})) >>> 2;
    wire signed [8:0] fdot_y = (dot_y * $signed({1'b0, fb_rad})) >>> 2;
    wire signed [8:0] fmx = (mx * $signed({1'b0, fb_rad})) >>> 2;
    wire signed [8:0] fmy = (my * $signed({1'b0, fb_rad})) >>> 2;
    wire [3:0] fsp = (fb_rad >= 4'd8) ? {2'b00, fb_rad[3:2]} : 4'd1;
    wire signed [10:0] edx = fdx - fdot_x;
    wire signed [10:0] edy = fdy - fdot_y;
    wire signed [10:0] ehx = fdx - fmx;
    wire signed [10:0] ehy = fdy - fmy;
    wire signed [10:0] esp = $signed({7'd0, fsp});
    wire f_mark = (fb_rad >= 4'd4) &&
                  ((edx == 0 && edy == 0) || (fb_rad >= 4'd6 && (edx == 0 || edx == 1) && (edy == 0 || edy == 1)));
    wire big = (fb_rad >= 4'd8);
    wire h1 = (ehx == 0) && (ehy == -esp);
    wire h2 = (ehx == -esp) && (ehy == esp);
    wire h3 = (ehx == esp) && (ehy == esp);
    wire h1b = big && (ehx == 0 || ehx == 1) && (ehy == -esp || ehy == -esp + 1);
    wire h2b = big && (ehx == -esp || ehx == -esp + 1) && (ehy == esp || ehy == esp + 1);
    wire h3b = big && (ehx == esp || ehx == esp + 1) && (ehy == esp || ehy == esp + 1);
    wire f_hole = holes_on && (fb_rad >= 4'd3) && (h1 || h2 || h3 || h1b || h2b || h3b);

    assign fb_color = f_hole ? 16'h1082 : f_spec ? `C_WHITE : f_mark ? lit : f_lit ? lit :
                      (f_dark || f_rim) ? dark : f_shd ? shade : base;
endmodule


// The shadow under the 3-D ball, and its reflection on the oiled lane
module ball_shadow (
    input  wire [8:0]  vx,
    input  wire [7:0]  vy,
    input  wire        fb_vis,
    input  wire [7:0]  fb_row,
    input  wire [3:0]  fb_rad,
    input  wire signed [10:0] fdx,
    input  wire [10:0] afx,
    input  wire [7:0]  fr2,
    output wire        in_shadow,
    output wire        in_refl,
    output wire        near_r
);
    // Flat dark shadow just above the floor row
    wire signed [10:0] sdy = $signed({3'b000, vy}) - $signed({3'b000, fb_row});
    wire signed [10:0] sdx = fdx - $signed({8'd0, fb_rad[3:2]});
    wire [10:0] asx = sdx[10] ? -sdx : sdx;

    assign in_shadow = fb_vis && (sdy >= -11'sd2) && (sdy <= 11'sd0) &&
                       (asx <= {7'd0, fb_rad} - ((sdy == -11'sd2) ? 11'd2 : 11'd0));

    // Reflection: the ball mirrored below the floor row.
    // Drawn as a dither pattern so the lane shows through
    wire signed [10:0] mdy = sdy - $signed({7'd0, fb_rad});
    wire [10:0] amd = mdy[10] ? -mdy : mdy;
    wire [9:0]  md2 = afx[4:0] * afx[4:0] + amd[4:0] * amd[4:0];

    assign near_r = (sdy <= $signed({8'd0, fb_rad[3:1]}));

    wire door = near_r ? (vx[0] ^ vy[0]) : (vx[0] & vy[0]);

    assign in_refl = fb_vis && (fb_rad >= 4'd3) && (sdy >= 11'sd1) && (sdy <= $signed({7'd0, fb_rad})) &&
                     (afx <= 11'd16) && (md2 <= {2'b00, fr2}) && door;
endmodule
