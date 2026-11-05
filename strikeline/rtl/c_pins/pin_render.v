`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// pin_render.v : the 10 pins and the rake (top-down), and the 3-D pins
//-----------------------------------------------------------------------------
// Owner   : Student C
// Top-down (UI space): 10 identical per-pin renderers run in parallel
//           (generate loop), then a priority pick: upright pins first (they
//           stand taller than fallen ones), then fallen pins, lowest pin
//           number first.
//   upright : 5x5 pattern, a white disc with the red neck ring around a
//             white head. A WOBBLING pin is drawn 1 px to the side on every
//             other 4-frame step (it visibly rocks).
//   fallen  : sprite ROM, base directions N and NE only. For a pin at pixel
//             offset (ox, oy) in direction d the ROM is read at
//               N  (ox,  oy)   E (oy, -ox)   S  (ox, -oy)   W  (oy,  ox)
//               NE (ox,  oy)   SE(ox, -oy)   SW (-ox, -oy)  NW (-ox, oy)
//             i.e. a mirror and/or an x<->y swap, which is just wiring.
//   rake    : a 2-row steel bar across the deck while the pin-setter works.
//   debug   : (sw[2]) pins are tinted by state: wobbling yellow, falling
//             orange, down grey.
// 3-D (v3, VGA; v3.2 at 320 x 240): from persp_proj, per pin either
//   a silhouette (standing / wobbling / just hit): pin_fp.mem gives the half
//             width of each row above the base for 32 sizes (2..53 px); white
//             body, a highlight on the left edge, a shaded right edge (2 px on
//             big pins) and the red neck stripes, or
//   a bar (falling / lying): a rounded box hw x hh around the pin's centre,
//             lit on top, shaded below, red neck toward the head.
//   The NEAREST pin (largest screen row) wins, and its row goes out as
//   `depth` so the compositor can put it in front of the ball when needed.
// ROMs (v3 resource squeeze): the 10 pins read the silhouette and the sprite
//   tables through 5 + 5 two-port block-RAM ROMs (rom2p) instead of 10 + 10
//   LUT copies; the read takes one clock inside render_scan's 8-clock pixel.
//=============================================================================
module pin_render (
    input  wire         clk,
    input  wire [8:0]   vx,              // VGA pixel, 320 x 240 (3-D view)
    input  wire [7:0]   vy,
    input  wire [6:0]   ux,              // UI-space pixel (top-down)
    input  wire [5:0]   uy,
    input  wire signed [10:0] cam_y,
    input  wire [239:0] pin_vis,
    input  wire [9:0]   rake_y,
    input  wire         wobble_phase,
    input  wire         debug,
    input  wire         fp,              // 3-D view
    input  wire [359:0] pins_fp,         // 10 x 36 bit from persp_proj
    output reg  [15:0]  color,
    output reg          en,
    output reg  [7:0]   depth
);
    wire signed [11:0] wy = cam_y + 12'sd63 - $signed({6'd0, uy});

    // per-pin results
    wire [9:0] up_hit, dn_hit, f_hit;
    wire [1:0] up_c [0:9];
    wire [1:0] dn_c [0:9];
    wire [1:0] f_c  [0:9];
    wire [7:0] f_row [0:9];
    wire [2:0] st_v [0:9];
    // ROM addresses and data
    wire [10:0] fp_a [0:9];
    wire [4:0]  fp_d [0:9];
    wire [10:0] sp_a [0:9];
    wire [1:0]  sp_d [0:9];

    genvar g;
    generate
        for (g = 0; g < 5; g = g + 1) begin : g_rom
            rom2p #(.AW(11), .DW(5), .FILE("pin_fp.mem"))      u_fp (.clk(clk), .a0(fp_a[2*g]), .a1(fp_a[2*g+1]),
                                                                    .d0(fp_d[2*g]), .d1(fp_d[2*g+1]));
            rom2p #(.AW(11), .DW(2), .FILE("pin_sprites.mem")) u_sp (.clk(clk), .a0(sp_a[2*g]), .a1(sp_a[2*g+1]),
                                                                    .d0(sp_d[2*g]), .d1(sp_d[2*g+1]));
        end
        for (g = 0; g < 10; g = g + 1) begin : g_pin
            // ---------------- 3-D -------------------------------------------
            // o = {vis, bar, x[9:0], row[7:0], cls|hw[4:0], hh[4:0], neck[4:0], 0}
            wire [35:0] o = pins_fp[36*g +: 36];
            wire [4:0]  o_hw = o[15:11], o_hh = o[10:6], o_nk = o[5:1];
            wire signed [10:0] odx = $signed({2'b00, vx}) - $signed({o[33], o[33:24]});
            wire [10:0] oax = odx[10] ? -odx : odx;
            wire signed [10:0] ody = $signed({3'b000, vy}) - $signed({3'b000, o[23:16]});
            wire [10:0] oay = ody[10] ? -ody : ody;
            wire signed [9:0] ov = $signed({2'b00, o[23:16]}) - $signed({2'b00, vy});   // rows above the base
            assign fp_a[g] = {o_hw, ov[5:0]};
            wire [4:0]  w  = fp_d[g];
            wire [10:0] ww = {7'd0, w[3:0]};
            wire h_up  = o[35] && !o[34] && ov >= 0 && ov <= 63 && w != 5'h1F && oax <= ww;
            wire [1:0] c_up = w[4] ? 2'd2 :
                              (odx > 0 && w[3:0] != 0 && (oax == ww || (w[3:0] >= 4'd4 && oax == ww - 11'd1))) ? 2'd1 :
                              (odx < 0 && w[3:0] >= 4'd3 && oax == ww - 11'd1) ? 2'd3 : 2'd0;
            wire h_bar = o[35] && o[34] && oax <= {6'd0, o_hw} && oay <= {6'd0, o_hh} &&
                         !(oax == {6'd0, o_hw} && oay == {6'd0, o_hh} && o_hw > 5'd1);
            wire [1:0] c_bar = (o_nk != 5'd0 && (odx == $signed({{6{o_nk[4]}}, o_nk}) ||
                                                  (o_hw >= 5'd8 && odx == $signed({{6{o_nk[4]}}, o_nk}) + 11'sd1))) ? 2'd2 :
                               (ody < 0 && oay == {6'd0, o_hh}) ? 2'd3 : (ody > 0) ? 2'd1 : 2'd0;
            assign f_hit[g] = h_up || h_bar;
            assign f_c[g]   = h_up ? c_up : c_bar;
            assign f_row[g] = o[23:16];

            // ---------------- top-down --------------------------------------
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
            wire signed [11:0] ox = $signed({5'd0, ux}) - $signed({6'd0, x_i}) - (jig ? 12'sd1 : 12'sd0);
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
            reg signed [4:0] u, w2;
            always @(*) begin
                case (d)
                    3'd0: begin u =  ox[4:0]; w2 =  oy[4:0]; end   // N
                    3'd2: begin u =  oy[4:0]; w2 = -ox[4:0]; end   // E
                    3'd4: begin u =  ox[4:0]; w2 = -oy[4:0]; end   // S
                    3'd6: begin u =  oy[4:0]; w2 =  ox[4:0]; end   // W
                    3'd1: begin u =  ox[4:0]; w2 =  oy[4:0]; end   // NE
                    3'd3: begin u =  ox[4:0]; w2 = -oy[4:0]; end   // SE
                    3'd5: begin u = -ox[4:0]; w2 = -oy[4:0]; end   // SW
                    default: begin u = -ox[4:0]; w2 = oy[4:0]; end // NW
                endcase
            end
            wire [3:0] su = u[3:0] + 4'd8, sw = w2[3:0] + 4'd8;
            assign sp_a[g] = {d[0], stage, sw, su};
            wire [1:0] sp = sp_d[g];
            wire in_sp = (u >= -8 && u <= 7 && w2 >= -8 && w2 <= 7);
            assign dn_hit[g] = (s == `PS_FALLING || s == `PS_DOWN) && near16 && in_sp && (sp != 2'd0);
            assign dn_c[g]   = sp;
        end
    endgenerate

    // ---------------- 3-D: the nearest pin wins ------------------------------
    reg        fp_hit;
    reg [1:0]  fp_c;
    reg [7:0]  fp_row;
    integer    kk;
    always @(*) begin
        fp_hit = 1'b0; fp_c = 2'd0; fp_row = 8'd0;
        for (kk = 0; kk < 10; kk = kk + 1)
            if (f_hit[kk] && (!fp_hit || f_row[kk] > fp_row)) begin
                fp_hit = 1'b1; fp_row = f_row[kk]; fp_c = f_c[kk];
            end
    end

    // ---------------- top-down priority pick ---------------------------------
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
                   (wy <= $signed({2'b00, rake_y}) + 12'sd1) && (ux >= 7'd1) && (ux <= 7'd58);

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
        en = 1'b0; color = `C_WHITE; depth = fp_row;
        if (fp) begin
            if (vx < `H_VIEW_W && vy >= `H_TOP_H && fp_hit) begin
                en = 1'b1;
                case (fp_c)
                    2'd2:    color = `C_RED;
                    2'd1:    color = 16'hC618;
                    2'd3:    color = 16'hFFFF;
                    default: color = 16'hF79E;
                endcase
            end
        end else if (ux < `SCR_LANE_W) begin
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
