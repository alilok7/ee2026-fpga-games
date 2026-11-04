`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// lane_render.v : the lane (back layer) and the minimap
//-----------------------------------------------------------------------------
// Owner   : Student B
// Purpose : A pure function of the pixel position and a few registers, so it
//           needs no frame buffer. For a lane pixel (px < 60):
//             world x = px (1 px = 1 in), world y = cam_y + 63 - py
//           and the colour comes from which real-lane zone that point is in:
//             y < 0 approach | y = 0 foul line | lane boards (oil sheen while
//             y < oil length) | arrows at 14.5-16 ft | dots at 7 ft |
//             pin deck from 708 in with the 10 spots | pit from 756 in
//           x 0..8 and 51..59 are the gutters, with kickback walls beside
//           the deck. Two themes: wood, and neon "cosmic bowling".
//           Minimap (sw[1], x 61..69): 1 px = 12 in along the lane and
//           6 in across it (stretched 2x so a hook is visible). It shows
//           the oil zone, the ball, the path the ball has taken
//           (ball_trace) and a bracket for the part of the lane on screen.
//=============================================================================
(* use_dsp = "yes" *)   // multiplies go to idle DSP slices (saves LUTs; resource squeeze)
module lane_render (
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire signed [10:0] cam_y,
    input  wire        fp,               // first-person view (else overhead)
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
    output reg  [15:0] color,
    output reg         en
);
    wire neon = settings[`SET_THEME];
    // ---------------- screen pixel -> lane point ------------------------------
    // overhead: 1 px = 1 in, lane x = px, lane y = cam_y + 63 - py
    // first person: row py looks dist[py] inches ahead of the camera and
    //   lane x = 30 + (px - 30) * inv[py] / 256   (persp.mem, one multiply)
    reg [25:0] persp_rom [0:63];
    initial $readmemh("persp.mem", persp_rom);
    wire [25:0] pr   = persp_rom[px_y];
    wire [10:0] pdst = pr[25:15];
    wire [14:0] pinv = pr[14:0];
    wire signed [22:0] pmul = $signed({1'b0, px_x} - 8'sd30) * $signed({1'b0, pinv});
    wire signed [11:0] fx_s = 12'sd30 + (pmul >>> 8);
    wire sky      = fp && (px_y <= 6'd12);
    wire off_lane = fp && (fx_s < 0 || fx_s > 12'sd59);           // beside the lane
    wire [6:0] lx = fp ? fx_s[6:0] : px_x;                        // lane x (inches)
    wire signed [11:0] wy = fp ? $signed({cam_fp[10], cam_fp}) + $signed({1'b0, pdst})
                               : cam_y + 12'sd63 - $signed({6'd0, px_y});
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
    wire [15:0] c_spot    = neon ? 16'h0410 : 16'hB46B;
    wire [15:0] c_wall    = neon ? 16'hA01F : 16'h4185;

    // ---------------- arrows: 7 V-shaped targets ----------------------------
    // board 5..35 (every 5th, counted from the right) at 14.5..16 ft
    function arrow_hit;
        input [6:0] x;
        input signed [11:0] y;
        reg [6:0] cx; reg [9:0] tip; reg signed [11:0] d; reg [6:0] adx;
        integer i;
        begin
            arrow_hit = 1'b0;
            for (i = 0; i < 7; i = i + 1) begin
                cx  = 7'd45 - 7'd5 * i[6:0] - ((i > 3) ? 7'd1 : 7'd0);
                tip = 10'd192 - 10'd6 * ((i < 3) ? 10'd3 - i[9:0] : i[9:0] - 10'd3);
                d   = $signed({2'b00, tip}) - y;                 // 0 at the tip
                adx = (x > cx) ? x - cx : cx - x;
                if (d >= 0 && d <= 4 && adx <= {5'd0, d[2:1]}) arrow_hit = 1'b1;
            end
        end
    endfunction

    // pin spots (integer inches)
    function spot_hit;
        input [6:0] x;
        input signed [11:0] y;
        begin
            spot_hit = (y == 720 && x == 30) ||
                       (y == 730 && (x == 24 || x == 36)) ||
                       (y == 741 && (x == 18 || x == 30 || x == 42)) ||
                       (y == 751 && (x == 12 || x == 24 || x == 36 || x == 48));
        end
    endfunction

    wire gutter_l = (lx <= 7'd8);
    wire gutter_r = (lx >= 7'd51) && (lx <= 7'd59);
    wire gut_mid  = (lx == 7'd4) || (lx == 7'd5) || (lx == 7'd54) || (lx == 7'd55);
    wire wall     = (lx == 7'd0 || lx == 7'd59) && (wy >= 12'sd690);
    wire dots     = (wy == 12'sd84) && (lx == 7'd47 || lx == 7'd45 || lx == 7'd42 ||
                     lx == 7'd18 || lx == 7'd15 || lx == 7'd13);
    // oil sheen: thin diagonal glints every 32 rows (they slide past as the camera scrolls)
    wire sheen    = fine && (((wy[4:0] + {lx[3:0], 1'b0}) & 5'h1F) == 5'd0);

    // ---------------- minimap ------------------------------------------------
    wire [6:0]  mx   = px_x - `SCR_MAP_X0;                    // 0..8
    wire [5:0]  my   = 6'd63 - px_y;                          // world y / 12
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
        case (px_y[1:0])
            2'd0: map_pin = (mx == 1 && pins_standing[6]) || (mx == 3 && pins_standing[7]) ||
                            (mx == 5 && pins_standing[8]) || (mx == 7 && pins_standing[9]);
            2'd1: map_pin = (mx == 2 && pins_standing[3]) || (mx == 4 && pins_standing[4]) ||
                            (mx == 6 && pins_standing[5]);
            2'd2: map_pin = (mx == 3 && pins_standing[1]) || (mx == 5 && pins_standing[2]);
            default: map_pin = (mx == 4 && pins_standing[0]);
        endcase
    end

    always @(*) begin
        en    = 1'b1;
        color = `C_BLACK;
        if (px_x < `SCR_LANE_W) begin
            // ------------------------- lane view --------------------------
            if (sky)                          color = (px_y >= 6'd9) ? (neon ? 16'h300C : 16'h4208) :
                                                          (neon ? 16'h0806 : 16'h0109);       // masking unit
            else if (off_lane)                color = neon ? 16'h1004 : 16'h2104;            // next to the lane
            else if (wall)                    color = c_wall;
            else if (wy >= 12'sd756)          color = (wy >= 12'sd770) ? 16'h18E3 : `C_BLACK;  // pit
            else if (gutter_l || gutter_r)    color = gut_mid ? c_gut_mid : c_gutter;
            else if (wy < 0)                  color = (wy[3:0] == 4'h0 && lx[2:0] == 3'd4) ? c_spot : c_approach;
            else if (wy == 0 || (fp && wy > 0 && wy < 12'sd3))
                                              color = c_foul;     // (first person: 2 in so far rows still hit it)
            else if (wy >= 12'sd708)          color = spot_hit(lx, wy) ? c_spot : c_deck;
            else if (arrow_hit(lx, wy) || dots) color = c_arrow;
            else if (wy < $signed({2'b00, oil_in}) && sheen) color = c_oil;
            else                              color = (fine && lx[0]) ? c_board_a : c_board_b;
        end else if (minimap_on && px_x >= `SCR_MAP_X0 && px_x <= `SCR_MAP_X0 + 7'd8) begin
            // ------------------------- minimap -----------------------------
            if (px_y < 6'd4 && mx != 0 && mx != 8)
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
