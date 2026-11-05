`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// lane_render.v : the lane (back layer) and the minimap
//-----------------------------------------------------------------------------
// Owner   : Student B
// Purpose : A pure function of the pixel position and a few registers. Two
//           ways of looking at the same lane:
//   TOP-DOWN (UI space, OLED and the VGA's framed window), lane px < 60:
//             world x = ux (1 px = 1 in), world y = cam_y + 63 - uy
//   3-D (the VGA during play; v3.2 at 320 x 240, v3.3 the whole screen):
//             row vy looks dist[vy] inches ahead of the camera (persp_v.mem),
//             world x = 30 + (vx - 160) * inv[vy] / 256   (one multiply)
//             Above the horizon (row 60): ceiling and the lit masking unit.
//   The colour comes from which real-lane zone that point is in:
//             y < 0 approach | y = 0 foul line | lane boards (oil sheen while
//             y < oil length) | arrows at 14.5-16 ft | dots at 7 ft |
//             range finders at 34-40 ft | pin deck from 708 in with the 10
//             spots | pit from 756 in; x 0..8 and 51..59 are the gutters,
//             with kickback walls beside the deck. Themes: wood, neon.
//   AIM GUIDE (v3, 3-D view while aiming): a dotted line on the lane from the
//             stance board through the chosen target arrow to the pins, and a
//             yellow marker on the target. Brighter while zoomed.
//   ZOOM (v3.1, right button held): the camera's longer lens scales the
//             distance of every row (dist x (256 + 7 zl) / 256); see camera.v.
//   Minimap (sw[1], UI x 61..69): 1 px = 12 in along the lane and 6 in
//             across it. It shows the oil zone, the ball, the path the ball
//             has taken (ball_trace) and a bracket for the part on screen.
//=============================================================================
(* use_dsp = "yes" *)   // multiplies go to idle DSP slices (saves LUTs; resource squeeze)
module lane_render (
    input  wire [8:0]  vx,               // VGA pixel, 320 x 240 (3-D view)
    input  wire [7:0]  vy,
    input  wire [6:0]  ux,               // UI-space pixel (top-down)
    input  wire [5:0]  uy,
    input  wire        fp,               // this pixel belongs to the 3-D view
    input  wire signed [10:0] cam_y,
    input  wire signed [10:0] cam_fp,    // first-person camera (world y, inches)
    input  wire [`SET_W-1:0] settings,
    input  wire        minimap_on,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire        ball_visible,
    output wire [5:0]  trace_row,        // minimap row -> ball_trace
    input  wire [3:0]  trace_data,       // {valid, column}
    input  wire [9:0]  pins_standing,
    input  wire        blink,            // ~4 Hz
    input  wire [7:0]  frame_cnt,
    input  wire        aim_guide,        // draw the dotted aim guide (aiming)
    input  wire        aim_zoom,         // zoom held: guide drawn bright
    input  wire [7:0]  zoom_lvl,         // v3.1: 0..255, the lens is (256 + 7 zl) / 256 times longer
    input  wire [6:0]  stance_in,        // stance board (inches)
    input  wire [6:0]  target_in,        // target (inches) at the arrows, 16 ft
    output reg  [15:0] color,
    output reg         en
);
    wire neon = settings[`SET_THEME];
    // ---------------- 3-D: screen pixel -> lane point ------------------------
    reg [26:0] persp_rom [0:255];
    initial $readmemh("persp_v.mem", persp_rom);
    wire [26:0] pr   = persp_rom[vy];
    wire [11:0] pdst = pr[26:15];
    wire [14:0] pinv = pr[14:0];
    // v3.1 zoom: a longer lens (K x m) sees row r at m times the distance, and
    // one inch is still r / 51 px there, so only the distance scales:
    //   dist = pdst * (256 + 7 zl) / 256     (camera.v: K = 3060 + 84 zl, same ratio)
    wire [10:0] zmul = 11'd256 + {zoom_lvl, 3'b000} - {3'b000, zoom_lvl};
    wire [22:0] dzm  = pdst * zmul;
    wire [11:0] dz   = (dzm[22:8] > 15'd3400) ? 12'd3400 : dzm[19:8];   // (beyond the pit anyway)
    wire signed [25:0] pmul = $signed({1'b0, vx} - {1'b0, `H_CX}) * $signed({1'b0, pinv});
    wire signed [12:0] fx_s = 13'sd30 + (pmul >>> 8);
    wire sky      = fp && (vy <= `H_HOR);
    wire off_lane = fp && (fx_s < 0 || fx_s > 13'sd59);           // beside the lane
    wire [6:0] lx = fp ? fx_s[6:0] : ux;                          // lane x (inches)
    wire signed [12:0] wy = fp ? $signed({cam_fp[10], cam_fp}) + $signed({1'b0, dz})
                               : cam_y + 13'sd63 - $signed({7'd0, uy});
    // one screen row covers about dist / r inches of lane: more than 8 (far
    // rows, and most of the lane when zoomed) and the 16 in dot pattern would
    // alias, so the guide is dotted by screen row there instead
    wire [7:0]  vr   = vy - `H_HOR;
    wire        coarse = (dz > {1'b0, vr, 3'b000});
    wire fine = !fp || (pinv <= 15'd512);      // boards visible only where 1 in >= 0.5 px
    wire [9:0] oil_in = settings[`SET_OIL] ? 10'd540 : 10'd480;

    // ---------------- palettes ----------------------------------------------
    wire [15:0] c_board_a = neon ? 16'h10A7 : 16'hDDD0;
    wire [15:0] c_board_b = neon ? 16'h18C8 : 16'hCD0D;
    wire [15:0] c_oil     = neon ? 16'h2132 : 16'hE654;
    wire [15:0] c_approach= neon ? 16'h0865 : 16'hF6F6;
    wire [15:0] c_gutter  = neon ? 16'h500F : 16'h5ACC;
    wire [15:0] c_gut_mid = neon ? 16'h2808 : 16'h39E8;
    wire [15:0] c_foul    = neon ? `C_MAGENTA : 16'h2945;
    wire [15:0] c_arrow   = neon ? `C_CYAN : 16'h38E2;
    wire [15:0] c_deck    = neon ? 16'h294C : 16'hEE74;
    wire [15:0] c_deck_lit= neon ? 16'h3A0F : 16'hF6F7;
    wire [15:0] c_spot    = neon ? 16'h0410 : 16'hB46B;
    wire [15:0] c_wall    = neon ? 16'hA01F : 16'h4185;

    // ---------------- arrows: 7 V-shaped targets ----------------------------
    // board 5..35 (every 5th, counted from the right) at 14.5..16 ft
    function arrow_hit;
        input [6:0] x;
        input signed [12:0] y;
        reg [6:0] cx; reg [9:0] tip; reg signed [12:0] d; reg [6:0] adx;
        integer i;
        begin
            arrow_hit = 1'b0;
            for (i = 0; i < 7; i = i + 1) begin
                cx  = 7'd45 - 7'd5 * i[6:0] - ((i > 3) ? 7'd1 : 7'd0);
                tip = 10'd192 - 10'd6 * ((i < 3) ? 10'd3 - i[9:0] : i[9:0] - 10'd3);
                d   = $signed({3'b000, tip}) - y;                // 0 at the tip
                adx = (x > cx) ? x - cx : cx - x;
                if (d >= 0 && d <= 4 && adx <= {5'd0, d[2:1]}) arrow_hit = 1'b1;
            end
        end
    endfunction

    // pin spots (integer inches); the 3-D view samples each row once, so the
    // spots there are widened by one inch in depth (else they flicker)
    function spot_hit;
        input [6:0] x;
        input signed [12:0] y;
        input wide;
        reg [12:0] d0, d1, d2, d3;
        begin
            d0 = y - 13'sd720; d1 = y - 13'sd730; d2 = y - 13'sd741; d3 = y - 13'sd751;
            spot_hit = ((d0 == 0 || (wide && d0 == 1)) && x == 30) ||
                       ((d1 == 0 || (wide && d1 == 1)) && (x == 24 || x == 36)) ||
                       ((d2 == 0 || (wide && d2 == 1)) && (x == 18 || x == 30 || x == 42)) ||
                       ((d3 == 0 || (wide && d3 == 1)) && (x == 12 || x == 24 || x == 36 || x == 48));
        end
    endfunction

    wire gutter_l = (lx <= 7'd8);
    wire gutter_r = (lx >= 7'd51) && (lx <= 7'd59);
    wire gut_mid  = (lx == 7'd4) || (lx == 7'd5) || (lx == 7'd54) || (lx == 7'd55);
    wire wall     = (lx == 7'd0 || lx == 7'd59) && (wy >= 13'sd690);
    // 7 ft dots (2 in deep in 3-D so that they never drop out)
    wire dot_row  = (wy == 13'sd84) || (fp && wy == 13'sd85);
    wire dots     = dot_row && (lx == 7'd47 || lx == 7'd45 || lx == 7'd42 ||
                     lx == 7'd18 || lx == 7'd15 || lx == 7'd13);
    // range finders (v3): short board marks at 34-40 ft on boards 10 and 15 from each side
    wire range_f  = fp && (wy >= 13'sd408) && (wy <= 13'sd480) && (wy[3:0] < 4'd6) &&
                    (lx == 7'd19 || lx == 7'd24 || lx == 7'd36 || lx == 7'd41);
    // oil sheen: thin diagonal glints every 32 rows (they slide past as the camera scrolls)
    wire sheen    = fine && (((wy[4:0] + {lx[3:0], 1'b0}) & 5'h1F) == 5'd0);

    // ---------------- aim guide (3-D) ----------------------------------------
    // x_line(wy) = stance + (target - stance) * wy / 192   (1/192 = 341 / 2^16)
    wire signed [7:0]  dxt   = $signed({1'b0, target_in}) - $signed({1'b0, stance_in});
    wire signed [17:0] kslp  = dxt * 18'sd341;
    wire signed [30:0] gmul  = kslp * wy;
    wire signed [12:0] x_ln  = $signed({6'd0, stance_in}) + (gmul >>> 16);
    wire signed [12:0] gdx   = $signed({6'd0, lx}) - x_ln;
    wire [12:0]        agdx  = gdx[12] ? -gdx : gdx;
    wire [6:0]         gtol  = (pinv[14:8] == 0) ? 7'd0 : pinv[14:8];        // inches per pixel
    wire on_guide = fp && aim_guide && (wy > 13'sd8) && (wy < 13'sd760) && (agdx <= {6'd0, gtol}) &&
                    (coarse ? (vy[1] == 1'b0) : (wy[3] == 1'b0)) && !gutter_l && !gutter_r;
    wire signed [12:0] tdy = wy - 13'sd196;
    wire [6:0]  atx = (lx > target_in) ? lx - target_in : target_in - lx;
    // (a diamond; on coarse rows a 2-row bar, else it would be one row or none)
    wire on_target = fp && aim_guide && (coarse ?
                     ((tdy >= -13'sd12) && (tdy <= 13'sd12) && ({6'd0, atx} <= 13'd2 + {6'd0, gtol})) :
                     ((tdy >= -13'sd6) && (tdy <= 13'sd6) &&
                      ({6'd0, atx} + (tdy[12] ? -tdy : tdy) <= 13'd5 + {6'd0, gtol})));
    wire [15:0] c_guide = aim_zoom ? `C_YELLOW : (neon ? 16'hFFF0 : 16'hFEA0);

    // ---------------- 3-D surroundings --------------------------------------
    // masking unit: a lit band above the pins; ceiling above it. A light runs
    // along the band in the neon theme.
    wire [7:0] mu_row = `H_HOR - vy;                                // 0 at the horizon
    wire mu_light = neon && (vx[8:4] == frame_cnt[6:2]) ;
    wire [15:0] c_sky = (mu_row >= 8'd16) ? (neon ? 16'h0806 : 16'h1082) :          // ceiling
                        (mu_row == 8'd15 || mu_row == 8'd0) ? (neon ? `C_CYAN : 16'hC5A0) :  // trim
                        (mu_row == 8'd14 || mu_row == 8'd1) ? (neon ? 16'h0410 : 16'h8360) : // trim shade
                        mu_light ? `C_MAGENTA : (neon ? 16'h300C : 16'h6000);          // band
    // next to the lane: capping, then the neighbouring approaches
    wire [12:0] aoff = fx_s[12] ? -fx_s : fx_s - 13'sd59;
    wire [15:0] c_side = (aoff <= 13'd4) ? (neon ? 16'h2004 : 16'h3986) : (neon ? 16'h1004 : 16'h2104);

    // ---------------- minimap (UI space) -------------------------------------
    wire [6:0]  mx   = ux - `SCR_MAP_X0;                      // 0..8
    wire [5:0]  my   = 6'd63 - uy;                            // world y / 12
    wire [15:0] my12 = {my, 3'b000} + {1'b0, my, 2'b00};      // my * 12 (inches)
    // ball row = y / 12 = (y * 1366) >> 14 (exact for y < 768);  column = x / 6
    wire [23:0] by_m = ball_y[15:6] * 14'd1366;
    wire [5:0]  b_row = (ball_y[15:6] > 10'd767) ? 6'd63 : by_m[19:14];
    wire [6:0]  bxi  = (ball_x[15:6] < 10'd9) ? 7'd0 : ball_x[12:6] - 7'd9;
    wire [12:0] bx_m = bxi * 6'd43;
    wire [2:0]  b_col = (bx_m[10:8] > 3'd6) ? 3'd7 : bx_m[10:8] + 3'd1;
    assign trace_row = my;
    wire [3:0]  tr   = trace_data;
    wire signed [11:0] cam_top = cam_y + 12'sd63;
    wire in_view = ($signed({1'b0, my12}) >= cam_y - 12'sd11) && ($signed({1'b0, my12}) <= cam_top);
    // schematic rack in the top 4 rows: 7-8-9-10 / 4-5-6 / 2-3 / 1
    reg map_pin;
    always @(*) begin
        case (uy[1:0])
            2'd0: map_pin = (mx == 1 && pins_standing[6]) || (mx == 3 && pins_standing[7]) ||
                            (mx == 5 && pins_standing[8]) || (mx == 7 && pins_standing[9]);
            2'd1: map_pin = (mx == 2 && pins_standing[3]) || (mx == 4 && pins_standing[4]) ||
                            (mx == 6 && pins_standing[5]);
            2'd2: map_pin = (mx == 3 && pins_standing[1]) || (mx == 5 && pins_standing[2]);
            default: map_pin = (mx == 4 && pins_standing[0]);
        endcase
    end

    // the zone colour of lane point (lx, wy)
    reg [15:0] zone;
    always @(*) begin
        if (wall)                         zone = c_wall;
        else if (wy >= 13'sd756)          zone = (wy >= 13'sd770) ? 16'h18E3 : `C_BLACK;  // pit
        else if (gutter_l || gutter_r)    zone = gut_mid ? c_gut_mid : c_gutter;
        else if (wy < 0)                  zone = (wy[3:0] == 4'h0 && lx[2:0] == 3'd4) ? c_spot : c_approach;
        else if (wy == 0 || (fp && wy > 0 && wy < 13'sd3))
                                          zone = c_foul;     // (3-D: 2 in so far rows still hit it)
        else if (wy >= 13'sd708)          zone = spot_hit(lx, wy, fp) ? c_spot : (fp ? c_deck_lit : c_deck);
        else if (arrow_hit(lx, wy) || dots || range_f) zone = c_arrow;
        else if (wy < $signed({3'b000, oil_in}) && sheen) zone = c_oil;
        else                              zone = (fine && lx[0]) ? c_board_a : c_board_b;
    end

    always @(*) begin
        en    = 1'b1;
        color = `C_BLACK;
        if (fp) begin
            // ------------------------- 3-D view (VGA) ---------------------
            if (vx >= `H_VIEW_W || vy < `H_TOP_H) en = 1'b0;
            else if (sky)                     color = c_sky;
            else if (off_lane)                color = c_side;
            else if (on_target)               color = `C_YELLOW;
            else if (on_guide)                color = c_guide;
            else                              color = zone;
        end else if (ux < `SCR_LANE_W) begin
            // ------------------------- top-down lane ----------------------
            color = zone;
        end else if (minimap_on && ux >= `SCR_MAP_X0 && ux <= `SCR_MAP_X0 + 7'd8) begin
            // ------------------------- minimap -----------------------------
            if (uy < 6'd4 && mx != 0 && mx != 8)
                color = map_pin ? `C_RED : c_deck;
            else if (mx == 0 || mx == 8)
                color = in_view ? `C_WHITE : c_gut_mid;                       // view bracket
            else if (ball_visible && my == b_row && mx[2:0] == b_col && blink)
                color = `C_WHITE;
            else if (tr[3] && tr[2:0] == mx[2:0])
                color = `C_YELLOW;
            else if (my12 < {6'd0, oil_in})
                color = neon ? 16'h18EB : 16'hB5DA;
            else
                color = c_board_b;
        end else begin
            en = 1'b0;                                       // HUD area belongs to D
        end
    end
endmodule
