`timescale 1ns / 1ps
`include "strike_defs.vh"
// lane_render.v : the lane (back layer) and the minimap
// Owner: Student B

(* use_dsp = "yes" *)
module lane_render (
    input  wire [8:0]  vx,
    input  wire [7:0]  vy,
    input  wire [6:0]  ux,
    input  wire [5:0]  uy,
    input  wire        fp,
    input  wire signed [10:0] cam_y,
    input  wire signed [10:0] cam_fp,
    input  wire [`SET_W-1:0] settings,
    input  wire        minimap_on,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire        ball_visible,
    output wire [5:0]  trace_row,
    input  wire [3:0]  trace_data,
    input  wire [9:0]  pins_standing,
    input  wire        blink,
    input  wire [7:0]  frame_cnt,
    input  wire        aim_guide,
    input  wire        aim_zoom,
    input  wire [7:0]  zoom_lvl,
    input  wire [6:0]  stance_in,
    input  wire [6:0]  target_in,
    output reg  [15:0] color,
    output reg         en,
    output reg  [1:0]  tint
);

    // ---------- 1. Which lane point this pixel shows ----------
    wire neon = settings[`SET_THEME];
    wire [6:0]  lx;
    wire signed [12:0] wy;
    wire [14:0] pinv;
    wire        off_lane, capping, sky, coarse, fine;
    wire [7:0]  vr;

    lane_point u_point (
        .vx(vx),
        .vy(vy),
        .ux(ux),
        .uy(uy),
        .fp(fp),
        .cam_y(cam_y),
        .cam_fp(cam_fp),
        .zoom_lvl(zoom_lvl),
        .lx(lx),
        .wy(wy),
        .pinv(pinv),
        .off_lane(off_lane),
        .capping(capping),
        .sky(sky),
        .coarse(coarse),
        .fine(fine),
        .vr(vr)
    );

    // ---------- 2. Colours of the lane zones ----------
    wire [9:0]  oil_in = settings[`SET_OIL] ? 10'd540 : 10'd480;
    wire [15:0] zone;
    wire        zboard;
    wire [15:0] c_deck, c_gut_mid, c_board_b;

    lane_zone u_zone (
        .neon(neon),
        .fp(fp),
        .fine(fine),
        .lx(lx),
        .wy(wy),
        .oil_in(oil_in),
        .zone(zone),
        .zboard(zboard),
        .c_deck(c_deck),
        .c_gut_mid(c_gut_mid),
        .c_board_b(c_board_b)
    );

    // ---------- 3. Dotted aim guide ----------
    wire on_guide, on_target;

    lane_guide u_guide (
        .fp(fp),
        .aim_guide(aim_guide),
        .off_lane(off_lane),
        .coarse(coarse),
        .vy(vy),
        .lx(lx),
        .wy(wy),
        .pinv(pinv),
        .stance_in(stance_in),
        .target_in(target_in),
        .on_guide(on_guide),
        .on_target(on_target)
    );

    wire [15:0] c_guide = aim_zoom ? `C_YELLOW : (neon ? 16'hFFF0 : 16'hFEA0);
    wire [15:0] c_sky = 16'h0841;
    wire [15:0] c_cap = neon ? 16'h2004 : 16'h4A49;

    // ---------- 4. Minimap ----------
    wire [15:0] map_color;
    wire [6:0]  mx;

    lane_minimap u_minimap (
        .ux(ux),
        .uy(uy),
        .neon(neon),
        .cam_y(cam_y),
        .ball_x(ball_x),
        .ball_y(ball_y),
        .ball_visible(ball_visible),
        .trace_row(trace_row),
        .trace_data(trace_data),
        .pins_standing(pins_standing),
        .blink(blink),
        .oil_in(oil_in),
        .c_deck(c_deck),
        .c_gut_mid(c_gut_mid),
        .c_board_b(c_board_b),
        .mx(mx),
        .map_color(map_color)
    );

    // ---------- 5. Wood grain and depth haze: how much darker this pixel is ----------
    wire grain = fp && fine && (((wy[6:3] ^ {lx[2:0], lx[0]}) == 4'd5) || (lx[2:0] == 3'd3 && wy[4]));
    wire haze1 = fp && (vr < 8'd34);
    wire haze2 = fp && (vr < 8'd22);
    wire [1:0] zt = (haze2 || (haze1 && zboard && grain)) ? 2'd2 : (haze1 || (zboard && grain)) ? 2'd1 : 2'd0;

    // ---------- 6. Pick the colour for this view ----------
    always @ (*) begin
        en = 1'b1;
        color = `C_BLACK;
        tint = 2'd0;
        if (fp) begin
            if (vx >= `H_VIEW_W || vy < `H_TOP_H)
                en = 1'b0;
            else if (sky)
                color = c_sky;
            else if (capping) begin
                color = c_cap;
                tint = zt;
            end
            else if (off_lane) begin
                color = zone;
                tint = (zt == 2'd0) ? 2'd1 : 2'd2;
            end
            else if (on_target)
                color = `C_YELLOW;
            else if (on_guide)
                color = c_guide;
            else begin
                color = zone;
                tint = zt;
            end
        end
        else if (ux < `SCR_LANE_W)
            color = zone;
        else if (minimap_on && ux >= `SCR_MAP_X0 && ux <= `SCR_MAP_X0 + 7'd8)
            color = map_color;
        else
            en = 1'b0;
    end
endmodule


// Screen pixel to lane point, using the per-row table and the zoom
(* use_dsp = "yes" *)
module lane_point (
    input  wire [8:0]  vx,
    input  wire [7:0]  vy,
    input  wire [6:0]  ux,
    input  wire [5:0]  uy,
    input  wire        fp,
    input  wire signed [10:0] cam_y,
    input  wire signed [10:0] cam_fp,
    input  wire [7:0]  zoom_lvl,
    output wire [6:0]  lx,
    output wire signed [12:0] wy,
    output wire [14:0] pinv,
    output wire        off_lane,
    output wire        capping,
    output wire        sky,
    output wire        coarse,
    output wire        fine,
    output wire [7:0]  vr
);
    reg [26:0] persp_rom [0:255];
    initial $readmemh("persp_v.mem", persp_rom);

    // Row table: how far away this row is, and how wide one pixel is there
    wire [26:0] pr = persp_rom[vy];
    wire [11:0] pdst = pr[26:15];
    assign pinv = pr[14:0];

    // Zoom scales the distance by (256 + 7*zl) / 256.
    // Lane x = 30 + (vx - 160) * pinv >> 8
    wire [10:0] zmul = 11'd256 + {zoom_lvl, 3'b000} - {3'b000, zoom_lvl};
    wire [22:0] dzm = pdst * zmul;
    wire [11:0] dz = (dzm[22:8] > 15'd3400) ? 12'd3400 : dzm[19:8];
    wire signed [25:0] pmul = $signed({1'b0, vx} - {1'b0, `H_CX}) * $signed({1'b0, pinv});
    wire signed [12:0] fx = 13'sd30 + (pmul >>> 8);

    assign sky = fp && (vy <= `H_HOR);
    assign off_lane = fp && (fx < 0 || fx > 13'sd59);
    assign lx = fp ? {1'b0, fx[5:0]} : ux;
    assign capping = fp && (fx[5:0] >= 6'd60);
    assign wy = fp ? $signed({cam_fp[10], cam_fp}) + $signed({1'b0, dz})
                   : cam_y + 13'sd63 - $signed({7'd0, uy});
    assign vr = vy - `H_HOR;
    assign coarse = (dz > {1'b0, vr, 3'b000});
    assign fine = !fp || (pinv <= 15'd512);
endmodule


// Colour of a lane point: boards, oil, arrows, deck, pit, gutters
(* use_dsp = "yes" *)
module lane_zone (
    input  wire        neon,
    input  wire        fp,
    input  wire        fine,
    input  wire [6:0]  lx,
    input  wire signed [12:0] wy,
    input  wire [9:0]  oil_in,
    output reg  [15:0] zone,
    output reg         zboard,
    output wire [15:0] c_deck,
    output wire [15:0] c_gut_mid,
    output wire [15:0] c_board_b
);
    // Wood and neon colours
    wire [15:0] c_board_a  = neon ? 16'h10A7 : 16'hDDD0;
    wire [15:0] c_oil      = neon ? 16'h2132 : 16'hE654;
    wire [15:0] c_approach = neon ? 16'h0865 : 16'hF6F6;
    wire [15:0] c_gutter   = neon ? 16'h500F : 16'h5ACC;
    wire [15:0] c_foul     = neon ? `C_MAGENTA : 16'h2945;
    wire [15:0] c_arrow    = neon ? `C_CYAN : 16'h38E2;
    wire [15:0] c_deck_lit = neon ? 16'h3A0F : 16'hF6F7;
    wire [15:0] c_spot     = neon ? 16'h0410 : 16'hB46B;
    wire [15:0] c_wall     = neon ? 16'hA01F : 16'h4185;
    assign c_board_b = neon ? 16'h18C8 : 16'hCD0D;
    assign c_gut_mid = neon ? 16'h2808 : 16'h39E8;
    assign c_deck    = neon ? 16'h294C : 16'hEE74;

    // the 7 V-shaped arrows
    function arrow;
        input [6:0] x;
        input signed [12:0] y;
        reg [6:0] cx;
        reg [9:0] tip;
        reg signed [12:0] d;
        reg [6:0] adx;
        integer i;
        begin
            arrow = 1'b0;
            for (i = 0; i < 7; i = i + 1) begin
                cx  = 7'd45 - 7'd5 * i[6:0] - ((i > 3) ? 7'd1 : 7'd0);
                tip = 10'd192 - 10'd6 * ((i < 3) ? 10'd3 - i[9:0] : i[9:0] - 10'd3);
                d   = $signed({3'b000, tip}) - y;
                adx = (x > cx) ? x - cx : cx - x;
                if (d >= 0 && d <= 4 && adx <= {5'd0, d[2:1]})
                    arrow = 1'b1;
            end
        end
    endfunction

    // the 10 pin spots
    function spot;
        input [6:0] x;
        input signed [12:0] y;
        input wide;
        reg [12:0] d0, d1, d2, d3;
        begin
            d0 = y - 13'sd720;
            d1 = y - 13'sd730;
            d2 = y - 13'sd741;
            d3 = y - 13'sd751;
            spot = ((d0 == 0 || (wide && d0 == 1)) && x == 30) ||
                   ((d1 == 0 || (wide && d1 == 1)) && (x == 24 || x == 36)) ||
                   ((d2 == 0 || (wide && d2 == 1)) && (x == 18 || x == 30 || x == 42)) ||
                   ((d3 == 0 || (wide && d3 == 1)) && (x == 12 || x == 24 || x == 36 || x == 48));
        end
    endfunction

    // Which lane feature this point falls on
    wire gutter_l = (lx <= 7'd8);
    wire gutter_r = (lx >= 7'd51) && (lx <= 7'd59);
    wire gut_mid  = (lx == 7'd4) || (lx == 7'd5) || (lx == 7'd54) || (lx == 7'd55);
    wire wall     = (lx == 7'd0 || lx == 7'd59) && (wy >= 13'sd690);
    wire dot_row  = (wy == 13'sd84) || (fp && wy == 13'sd85);
    wire dots     = dot_row && (lx == 7'd47 || lx == 7'd45 || lx == 7'd42 || lx == 7'd18 || lx == 7'd15 || lx == 7'd13);
    wire range    = fp && (wy >= 13'sd408) && (wy <= 13'sd480) && (wy[3:0] < 4'd6) &&
                    (lx == 7'd19 || lx == 7'd24 || lx == 7'd36 || lx == 7'd41);
    wire sheen    = fine && (((wy[4:0] + {lx[3:0], 1'b0}) & 5'h1F) == 5'd0);

    // First match wins, from the walls and pit down to the plain boards
    always @ (*) begin
        zboard = 1'b0;
        if (wall)
            zone = c_wall;
        else if (wy >= 13'sd756)
            zone = (wy >= 13'sd770) ? 16'h18E3 : `C_BLACK;
        else if (gutter_l || gutter_r)
            zone = gut_mid ? c_gut_mid : c_gutter;
        else if (wy < 0)
            zone = (wy[3:0] == 4'h0 && lx[2:0] == 3'd4) ? c_spot : c_approach;
        else if (wy == 0 || (fp && wy > 0 && wy < 13'sd3))
            zone = c_foul;
        else if (wy >= 13'sd708)
            zone = spot(lx, wy, fp) ? c_spot : (fp ? c_deck_lit : c_deck);
        else if (arrow(lx, wy) || dots || range)
            zone = c_arrow;
        else if (wy < $signed({3'b000, oil_in}) && sheen)
            zone = c_oil;
        else begin
            zone = (fine && lx[0]) ? c_board_a : c_board_b;
            zboard = 1'b1;
        end
    end
endmodule


// Dotted line from the stance through the target, and the target marker
(* use_dsp = "yes" *)
module lane_guide (
    input  wire        fp,
    input  wire        aim_guide,
    input  wire        off_lane,
    input  wire        coarse,
    input  wire [7:0]  vy,
    input  wire [6:0]  lx,
    input  wire signed [12:0] wy,
    input  wire [14:0] pinv,
    input  wire [6:0]  stance_in,
    input  wire [6:0]  target_in,
    output wire        on_guide,
    output wire        on_target
);
    wire gutter_l = (lx <= 7'd8);
    wire gutter_r = (lx >= 7'd51) && (lx <= 7'd59);

    // Line x = stance + (target - stance) * wy / 192
    wire signed [7:0]  dx_t = $signed({1'b0, target_in}) - $signed({1'b0, stance_in});
    wire signed [17:0] slope = dx_t * 18'sd341;
    wire signed [30:0] gmul = slope * wy;
    wire signed [12:0] line_x = $signed({6'd0, stance_in}) + (gmul >>> 16);
    wire signed [12:0] gdx = $signed({6'd0, lx}) - line_x;
    wire [12:0] agdx = gdx[12] ? -gdx : gdx;
    wire [6:0]  tol = (pinv[14:8] == 0) ? 7'd0 : pinv[14:8];

    assign on_guide = fp && aim_guide && !off_lane && (wy > 13'sd8) && (wy < 13'sd760) && (agdx <= {6'd0, tol}) &&
                      (coarse ? (vy[1] == 1'b0) : (wy[3] == 1'b0)) && !gutter_l && !gutter_r;

    // Target marker around the arrows: a box far away, a diamond up close
    wire signed [12:0] tdy = wy - 13'sd196;
    wire [6:0] atx = (lx > target_in) ? lx - target_in : target_in - lx;

    assign on_target = fp && aim_guide && !off_lane && (coarse ?
                       ((tdy >= -13'sd12) && (tdy <= 13'sd12) && ({6'd0, atx} <= 13'd2 + {6'd0, tol})) :
                       ((tdy >= -13'sd6) && (tdy <= 13'sd6) &&
                        ({6'd0, atx} + (tdy[12] ? -tdy : tdy) <= 13'd5 + {6'd0, tol})));
endmodule


// Minimap: oil zone, ball, its path, the part on screen and the pins left
(* use_dsp = "yes" *)
module lane_minimap (
    input  wire [6:0]  ux,
    input  wire [5:0]  uy,
    input  wire        neon,
    input  wire signed [10:0] cam_y,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire        ball_visible,
    output wire [5:0]  trace_row,
    input  wire [3:0]  trace_data,
    input  wire [9:0]  pins_standing,
    input  wire        blink,
    input  wire [9:0]  oil_in,
    input  wire [15:0] c_deck,
    input  wire [15:0] c_gut_mid,
    input  wire [15:0] c_board_b,
    output wire [6:0]  mx,
    output reg  [15:0] map_color
);
    // Minimap: 1 row per 12 in along the lane. Row and column are multiplies, not divides
    assign mx = ux - `SCR_MAP_X0;
    wire [5:0]  my = 6'd63 - uy;
    wire [15:0] my12 = {my, 3'b000} + {1'b0, my, 2'b00};
    wire [23:0] by_m = ball_y[15:6] * 14'd1366;
    wire [5:0]  b_row = (ball_y[15:6] > 10'd767) ? 6'd63 : by_m[19:14];
    wire [6:0]  bxi = (ball_x[15:6] < 10'd9) ? 7'd0 : ball_x[12:6] - 7'd9;
    wire [12:0] bx_m = bxi * 6'd43;
    wire [2:0]  b_col = (bx_m[10:8] > 3'd6) ? 3'd7 : bx_m[10:8] + 3'd1;
    wire signed [11:0] cam_top = cam_y + 12'sd63;
    wire in_view = ($signed({1'b0, my12}) >= cam_y - 12'sd11) && ($signed({1'b0, my12}) <= cam_top);

    assign trace_row = my;

    // Pin triangle in the top 4 rows
    reg map_pin;
    always @ (*) begin
        case (uy[1:0])
            2'd0: map_pin = (mx == 1 && pins_standing[6]) || (mx == 3 && pins_standing[7]) ||
                            (mx == 5 && pins_standing[8]) || (mx == 7 && pins_standing[9]);
            2'd1: map_pin = (mx == 2 && pins_standing[3]) || (mx == 4 && pins_standing[4]) ||
                            (mx == 6 && pins_standing[5]);
            2'd2: map_pin = (mx == 3 && pins_standing[1]) || (mx == 5 && pins_standing[2]);
            default: map_pin = (mx == 4 && pins_standing[0]);
        endcase
    end

    // Pick the colour, with the pins and the ball on top
    always @ (*) begin
        if (uy < 6'd4 && mx != 0 && mx != 8)
            map_color = map_pin ? `C_RED : c_deck;
        else if (mx == 0 || mx == 8)
            map_color = in_view ? `C_WHITE : c_gut_mid;
        else if (ball_visible && my == b_row && mx[2:0] == b_col && blink)
            map_color = `C_WHITE;
        else if (trace_data[3] && trace_data[2:0] == mx[2:0])
            map_color = `C_YELLOW;
        else if (my12 < {6'd0, oil_in})
            map_color = neon ? 16'h18EB : 16'hB5DA;
        else
            map_color = c_board_b;
    end
endmodule
