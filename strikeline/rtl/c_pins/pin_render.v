`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// pin_render.v : the 10 pins and the rake (top-down), and the 3-D pins
//-----------------------------------------------------------------------------
// Owner   : Student C
// Top-down (UI space): one renderer per pin (generate loop), then a priority
//   pick: upright pins first (they stand taller), then fallen pins, lowest
//   pin number first.
//   upright : 5x5 pattern, a white disc with the red neck ring around the
//             head. A WOBBLING pin is drawn 1 px to the side every other
//             4-frame step, so it rocks.
//   fallen  : sprite ROM holding directions N and NE only; the other six are
//             a mirror and/or an x<->y swap of the pixel offset (just wiring).
//   rake    : a 2-row steel bar across the deck while the pin-setter works.
//   debug   : (sw[2]) pins tinted by state: wobbling yellow, falling orange,
//             down grey.
// 3-D (VGA, 320 x 240): per pin from persp_proj either
//   a silhouette (upright): pin_fp.mem gives the half width of each row above
//             the base for 32 sizes; white body, left highlight, shaded right
//             edge and the red neck stripes, or
//   a bar (falling / lying): a rounded box hw x hh around the pin's centre,
//             lit on top, shaded below, red neck toward the head.
//   The nearest pin (largest screen row) wins; its row goes out as `depth`
//   so the compositor can put it in front of the ball.
// ROMs: the silhouette and sprite tables are 5 + 5 two-port block-RAM ROMs
//   (rom2p, 2 pins each); the read takes one clock of render_scan's pixel.
//   (The block name g_rom is used by the XDC timing constraints.)
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

    // ---------- 1. Per-pin results ----------
    wire signed [11:0] LANE_ROW = cam_y + 12'sd63 - $signed({6'd0, uy});   // lane row (inches) of this pixel

    // pin_vis one clock later: splits the path pin record -> sprite ROM address (timing)
    reg [239:0] PIN_VIS_Q;
    always @ (posedge clk)
        PIN_VIS_Q <= pin_vis;

    wire [9:0] UP_HIT, DOWN_HIT, FP_HIT;
    wire [1:0] UP_COLOUR   [0:9];
    wire [1:0] DOWN_COLOUR [0:9];
    wire [1:0] FP_COLOUR   [0:9];
    wire [7:0] FP_ROW      [0:9];
    wire [2:0] PIN_STATE   [0:9];
    // ROM addresses and data
    wire [10:0] FP_ADDR     [0:9];
    wire [4:0]  FP_DATA     [0:9];
    wire [10:0] SPRITE_ADDR [0:9];
    wire [1:0]  SPRITE_DATA [0:9];

    genvar g;
    generate
        // ---------- 2. ROMs: 2 pins per block-RAM ROM ----------
        for (g = 0; g < 5; g = g + 1) begin : g_rom
            rom2p #(.AW(11), .DW(5), .FILE("pin_fp.mem")) fp_rom_module (
                .clk(clk),
                .a0(FP_ADDR[2*g]), .a1(FP_ADDR[2*g+1]),
                .d0(FP_DATA[2*g]), .d1(FP_DATA[2*g+1]));
            rom2p #(.AW(11), .DW(2), .FILE("pin_sprites.mem")) sprite_rom_module (
                .clk(clk),
                .a0(SPRITE_ADDR[2*g]), .a1(SPRITE_ADDR[2*g+1]),
                .d0(SPRITE_DATA[2*g]), .d1(SPRITE_DATA[2*g+1]));
        end

        for (g = 0; g < 10; g = g + 1) begin : g_pin
            // ---------- 3. 3-D pin ----------
            // {vis, bar, x[9:0], row[7:0], hw[4:0], hh[4:0], neck[4:0], 0}
            wire [35:0] O     = pins_fp[36*g +: 36];
            wire        O_VIS = O[35];
            wire        O_BAR = O[34];
            wire [7:0]  O_ROW = O[23:16];
            wire [4:0]  O_HW  = O[15:11];
            wire [4:0]  O_HH  = O[10:6];
            wire [4:0]  O_NK  = O[5:1];
            wire signed [10:0] ODX = $signed({2'b00, vx}) - $signed({O[33], O[33:24]});
            wire signed [10:0] ODY = $signed({3'b000, vy}) - $signed({3'b000, O_ROW});
            wire [10:0] OAX = ODX[10] ? -ODX : ODX;
            wire [10:0] OAY = ODY[10] ? -ODY : ODY;
            wire signed [9:0] ROWS_UP = $signed({2'b00, O_ROW}) - $signed({2'b00, vy});   // rows above the base

            // silhouette: W = {neck stripe, half width} of this row, 5'h1F = above the pin
            assign FP_ADDR[g] = {O_HW, ROWS_UP[5:0]};
            wire [4:0]  W  = FP_DATA[g];
            wire [10:0] WW = {7'd0, W[3:0]};
            wire HIT_UP = O_VIS && !O_BAR && ROWS_UP >= 0 && ROWS_UP <= 63 && W != 5'h1F && OAX <= WW;
            wire [1:0] COLOUR_UP =
                W[4] ? 2'd2 :                                                             // neck stripe
                (ODX > 0 && W[3:0] != 0 &&
                 (OAX == WW || (W[3:0] >= 4'd4 && OAX == WW - 11'd1))) ? 2'd1 :           // shaded right edge
                (ODX < 0 && W[3:0] >= 4'd3 && OAX == WW - 11'd1) ? 2'd3 :                 // left highlight
                                                                   2'd0;                  // body

            // bar: box without its corners (on boxes wider than 1)
            wire signed [10:0] NECK = $signed({{6{O_NK[4]}}, O_NK});
            wire HIT_BAR = O_VIS && O_BAR && OAX <= {6'd0, O_HW} && OAY <= {6'd0, O_HH} &&
                           !(OAX == {6'd0, O_HW} && OAY == {6'd0, O_HH} && O_HW > 5'd1);
            wire [1:0] COLOUR_BAR =
                (O_NK != 5'd0 && (ODX == NECK || (O_HW >= 5'd8 && ODX == NECK + 11'sd1))) ? 2'd2 :   // neck
                (ODY < 0 && OAY == {6'd0, O_HH}) ? 2'd3 :                                          // lit top
                (ODY > 0)                        ? 2'd1 :                                          // shaded
                                                   2'd0;

            assign FP_HIT[g]    = HIT_UP || HIT_BAR;
            assign FP_COLOUR[g] = HIT_UP ? COLOUR_UP : COLOUR_BAR;
            assign FP_ROW[g]    = O_ROW;

            // ---------- 4. Top-down pin ----------
            wire [23:0] V     = PIN_VIS_Q[24*g +: 24];
            wire [5:0]  PIN_X = V[23:18];
            wire [9:0]  PIN_Y = V[17:8];
            wire [2:0]  S     = V[7:5];
            wire [2:0]  D     = V[4:2];
            wire [1:0]  STAGE = V[1:0];
            assign PIN_STATE[g] = S;
            wire UPRIGHT = (S == `PS_STANDING) || (S == `PS_WOBBLING);
            wire JIG     = (S == `PS_WOBBLING) && wobble_phase;
            // offset of this pixel from the pin centre (screen: y down)
            wire signed [11:0] OX = $signed({5'd0, ux}) - $signed({6'd0, PIN_X}) - (JIG ? 12'sd1 : 12'sd0);
            wire signed [11:0] OY = $signed({2'b00, PIN_Y}) - LANE_ROW;
            wire NEAR5  = (OX >= -2 && OX <= 2 && OY >= -2 && OY <= 2);
            wire NEAR16 = (OX >= -8 && OX <= 7 && OY >= -8 && OY <= 7);

            // upright 5x5 pattern
            wire [2:0] AX = OX[2:0] + 3'd2;                                  // 0..4
            wire [2:0] AY = OY[2:0] + 3'd2;
            wire CORNER = (AX == 0 || AX == 4) && (AY == 0 || AY == 4);
            wire RING   = (AX >= 1 && AX <= 3 && AY >= 1 && AY <= 3) && !(AX == 2 && AY == 2);
            assign UP_HIT[g]    = UPRIGHT && NEAR5 && !CORNER;
            assign UP_COLOUR[g] = RING ? 2'd2 : 2'd1;

            // fallen: map the offset into the N / NE base sprite
            reg signed [4:0] U, U2;
            always @ (*) begin
                case (D)
                    3'd0, 3'd1: begin U =  OX[4:0]; U2 =  OY[4:0]; end   // N, NE
                    3'd2:       begin U =  OY[4:0]; U2 = -OX[4:0]; end   // E
                    3'd3, 3'd4: begin U =  OX[4:0]; U2 = -OY[4:0]; end   // SE, S
                    3'd5:       begin U = -OX[4:0]; U2 = -OY[4:0]; end   // SW
                    3'd6:       begin U =  OY[4:0]; U2 =  OX[4:0]; end   // W
                    default:    begin U = -OX[4:0]; U2 =  OY[4:0]; end   // NW
                endcase
            end
            wire [3:0] SU = U[3:0] + 4'd8;
            wire [3:0] SW = U2[3:0] + 4'd8;
            assign SPRITE_ADDR[g] = {D[0], STAGE, SW, SU};
            wire [1:0] SP = SPRITE_DATA[g];
            wire IN_SPRITE = (U >= -8 && U <= 7 && U2 >= -8 && U2 <= 7);
            assign DOWN_HIT[g]    = (S == `PS_FALLING || S == `PS_DOWN) && NEAR16 && IN_SPRITE && (SP != 2'd0);
            assign DOWN_COLOUR[g] = SP;
        end
    endgenerate

    // ---------- 5. 3-D: the nearest pin wins ----------
    reg        FP_ANY;
    reg [1:0]  FP_PICK_COLOUR;
    reg [7:0]  FP_PICK_ROW;
    integer    kk;
    always @ (*) begin
        FP_ANY = 1'b0;
        FP_PICK_COLOUR = 2'd0;
        FP_PICK_ROW = 8'd0;
        for (kk = 0; kk < 10; kk = kk + 1)
            if (FP_HIT[kk] && (!FP_ANY || FP_ROW[kk] > FP_PICK_ROW)) begin
                FP_ANY = 1'b1;
                FP_PICK_ROW = FP_ROW[kk];
                FP_PICK_COLOUR = FP_COLOUR[kk];
            end
    end

    // ---------- 6. Top-down: upright over fallen, lowest pin first ----------
    reg        TD_ANY;
    reg [1:0]  TD_COLOUR;
    reg [2:0]  TD_STATE;
    reg        TD_UPRIGHT;
    integer k;
    always @ (*) begin
        TD_ANY = 1'b0;
        TD_COLOUR = 2'd0;
        TD_STATE = 3'd0;
        TD_UPRIGHT = 1'b0;
        for (k = 9; k >= 0; k = k - 1)
            if (DOWN_HIT[k]) begin
                TD_ANY = 1'b1;
                TD_COLOUR = DOWN_COLOUR[k];
                TD_STATE = PIN_STATE[k];
            end
        for (k = 9; k >= 0; k = k - 1)
            if (UP_HIT[k]) begin
                TD_ANY = 1'b1;
                TD_COLOUR = UP_COLOUR[k];
                TD_STATE = PIN_STATE[k];
                TD_UPRIGHT = 1'b1;
            end
    end

    wire ON_RAKE = (rake_y != 10'd0) && (LANE_ROW >= $signed({2'b00, rake_y})) &&
                   (LANE_ROW <= $signed({2'b00, rake_y}) + 12'sd1) && (ux >= 7'd1) && (ux <= 7'd58);

    // ---------- 7. Pin body colour (debug: tinted by state) ----------
    reg [15:0] WHITE;
    always @ (*) begin
        WHITE = `C_WHITE;
        if (debug)
            case (TD_STATE)
                `PS_WOBBLING: WHITE = `C_YELLOW;
                `PS_FALLING:  WHITE = `C_ORANGE;
                `PS_DOWN:     WHITE = 16'hBDF7;
                default:      WHITE = `C_WHITE;
            endcase
    end

    // ---------- 8. Output colour ----------
    always @ (*) begin
        en = 1'b0;
        color = `C_WHITE;
        depth = FP_PICK_ROW;
        if (fp) begin
            if (vx < `H_VIEW_W && vy >= `H_TOP_H && FP_ANY) begin
                en = 1'b1;
                case (FP_PICK_COLOUR)
                    2'd2:    color = `C_RED;
                    2'd1:    color = 16'hC618;
                    2'd3:    color = 16'hFFFF;
                    default: color = 16'hF79E;
                endcase
            end
        end
        else if (ux < `SCR_LANE_W) begin
            if (TD_ANY && TD_UPRIGHT) begin
                en = 1'b1;
                color = (TD_COLOUR == 2'd2) ? `C_RED : WHITE;
            end
            else if (ON_RAKE) begin
                en = 1'b1;
                color = (LANE_ROW == $signed({2'b00, rake_y})) ? 16'hC618 : 16'h6B4D;
            end
            else if (TD_ANY) begin
                en = 1'b1;
                color = (TD_COLOUR == 2'd2) ? `C_RED :
                        (TD_COLOUR == 2'd3) ? 16'h9CD3 :
                                              WHITE;
            end
        end
    end
endmodule
