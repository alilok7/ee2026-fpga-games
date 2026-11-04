`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// pin_render.v : the 10 pins and the rake, seen from above
//-----------------------------------------------------------------------------
// Owner   : Student C
// Purpose : 10 identical per-pin renderers run in parallel (generate loop),
//           then a priority pick: upright pins first (they stand taller than
//           fallen ones), then fallen pins, lowest pin number first.
//   upright : 5x5 pattern, a white disc with the red neck ring around a
//             white head. A WOBBLING pin is drawn 1 px to the side on every
//             other 4-frame step (it visibly rocks).
//   fallen  : sprite ROM, base directions N and NE only. For a pin at pixel
//             offset (ox, oy) in direction d the ROM is read at
//               N  (ox,  oy)   E (oy, -ox)   S  (ox, -oy)   W  (oy,  ox)
//               NE (ox,  oy)   SE(ox, -oy)   SW (-ox, -oy)  NW (-ox, oy)
//             i.e. a mirror and/or an x<->y swap, which is just wiring.
//   rake    : a 2-row steel bar across the deck while the pin-setter works,
//             behind upright pins.
//   debug   : (sw[2]) pins are tinted by state: wobbling yellow, falling
//             orange, down grey.
//=============================================================================
module pin_render (
    input  wire [6:0]   px_x,
    input  wire [5:0]   px_y,
    input  wire signed [10:0] cam_y,
    input  wire [239:0] pin_vis,
    input  wire [9:0]   rake_y,
    input  wire         wobble_phase,
    input  wire         debug,
    output reg  [15:0]  color,
    output reg          en
);
    reg [1:0] spr_rom [0:2047];
    initial $readmemh("pin_sprites.mem", spr_rom);

    wire signed [11:0] wy = cam_y + 12'sd63 - $signed({6'd0, px_y});

    wire [9:0] up_hit, dn_hit;
    wire [1:0] up_c [0:9];
    wire [1:0] dn_c [0:9];
    wire [2:0] st_v [0:9];

    genvar g;
    generate
        for (g = 0; g < 10; g = g + 1) begin : g_pin
            wire [23:0] v     = pin_vis[24*g +: 24];
            wire [5:0]  x_i   = v[23:18];
            wire [9:0]  y_i   = v[17:8];
            wire [2:0]  s     = v[7:5];
            wire [2:0]  d     = v[4:2];
            wire [1:0]  stage = v[1:0];
            assign st_v[g] = s;
            wire upright = (s == `PS_STANDING) || (s == `PS_WOBBLING);
            wire jig     = (s == `PS_WOBBLING) && wobble_phase;
            // offset of this pixel from the pin centre (screen: y down)
            wire signed [11:0] ox = $signed({5'd0, px_x}) - $signed({6'd0, x_i}) - (jig ? 12'sd1 : 12'sd0);
            wire signed [11:0] oy = $signed({2'b00, y_i}) - wy;
            wire near5  = (ox >= -2 && ox <= 2 && oy >= -2 && oy <= 2);
            wire near16 = (ox >= -8 && ox <= 7 && oy >= -8 && oy <= 7);
            // ---- upright 5x5 pattern ----
            wire [2:0] ax = ox[2:0] + 3'd2, ay = oy[2:0] + 3'd2;      // 0..4
            wire corner = (ax == 0 || ax == 4) && (ay == 0 || ay == 4);
            wire ring   = (ax >= 1 && ax <= 3 && ay >= 1 && ay <= 3) && !(ax == 2 && ay == 2);
            assign up_hit[g] = upright && near5 && !corner;
            assign up_c[g]   = ring ? 2'd2 : 2'd1;
            // ---- fallen: symmetry transform into the N / NE base sprite ----
            reg signed [4:0] u, w;
            always @(*) begin
                case (d)
                    3'd0: begin u =  ox[4:0]; w =  oy[4:0]; end   // N
                    3'd2: begin u =  oy[4:0]; w = -ox[4:0]; end   // E
                    3'd4: begin u =  ox[4:0]; w = -oy[4:0]; end   // S
                    3'd6: begin u =  oy[4:0]; w =  ox[4:0]; end   // W
                    3'd1: begin u =  ox[4:0]; w =  oy[4:0]; end   // NE
                    3'd3: begin u =  ox[4:0]; w = -oy[4:0]; end   // SE
                    3'd5: begin u = -ox[4:0]; w = -oy[4:0]; end   // SW
                    default: begin u = -ox[4:0]; w = oy[4:0]; end // NW
                endcase
            end
            wire [3:0] su = u[3:0] + 4'd8, sw = w[3:0] + 4'd8;
            wire [1:0] sp = spr_rom[{d[0], stage, sw, su}];
            wire in_sp = (u >= -8 && u <= 7 && w >= -8 && w <= 7);
            assign dn_hit[g] = (s == `PS_FALLING || s == `PS_DOWN) && near16 && in_sp && (sp != 2'd0);
            assign dn_c[g]   = sp;
        end
    endgenerate

    // ---------------- priority pick ----------------------------------------
    reg        hit;
    reg [1:0]  pc;
    reg [2:0]  ps;
    reg        pick_up;
    integer k;
    always @(*) begin
        hit = 1'b0; pc = 2'd0; ps = 3'd0; pick_up = 1'b0;
        for (k = 9; k >= 0; k = k - 1)                  // lowest index wins
            if (dn_hit[k]) begin hit = 1'b1; pc = dn_c[k]; ps = st_v[k]; end
        for (k = 9; k >= 0; k = k - 1)
            if (up_hit[k]) begin hit = 1'b1; pc = up_c[k]; ps = st_v[k]; pick_up = 1'b1; end
    end

    wire on_rake = (rake_y != 10'd0) && (wy >= $signed({2'b00, rake_y})) &&
                   (wy <= $signed({2'b00, rake_y}) + 12'sd1) && (px_x >= 7'd1) && (px_x <= 7'd58);

    reg [15:0] white;
    always @(*) begin
        white = `C_WHITE;
        if (debug)
            case (ps)
                `PS_WOBBLING: white = `C_YELLOW;
                `PS_FALLING:  white = `C_ORANGE;
                `PS_DOWN:     white = 16'hBDF7;
                default:      white = `C_WHITE;
            endcase
    end

    always @(*) begin
        en = 1'b0; color = `C_WHITE;
        if (px_x < `SCR_LANE_W) begin
            if (hit && pick_up) begin
                en = 1'b1; color = (pc == 2'd2) ? `C_RED : white;
            end else if (on_rake) begin
                en = 1'b1; color = (wy == $signed({2'b00, rake_y})) ? 16'hC618 : 16'h6B4D;
            end else if (hit) begin
                en = 1'b1;
                color = (pc == 2'd2) ? `C_RED : (pc == 2'd3) ? 16'h9CD3 : white;
            end
        end
    end
endmodule
