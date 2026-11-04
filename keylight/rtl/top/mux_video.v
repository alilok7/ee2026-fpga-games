`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// mux_video.v : choose the screen, add the overlay, apply theme/brightness
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student D
// Purpose     : Exactly one renderer is "on air" per mode (B's Free Play,
//               C's Play screen, D's screens, or the colour-bar self test).
//               D's overlay (hint bar, pause banner) is drawn on top, then
//               ONE post-processing stage applies the display settings to
//               the final RGB565 value, so every screen obeys them:
//                 theme light : black <-> near-white, white -> black
//                 brightness  : each channel x 1, 3/4, 1/2 or 1/4 using
//                               shifts (x - x/4, x/2, x/4), no multiplier
// Timing      : output register = stage 3 of the video pipeline.
//               A full renderer (string ROM -> font ROM -> compositing ->
//               brightness) takes more than one 10 ns clock. It does not
//               need to: each pixel position is held for 256 clocks. So the
//               output register only CAPTURES on `capture`, 7 clocks after
//               px_x/px_y last changed, and the XDC gives every path into
//               oled_data 6 clocks (set_multicycle_path). The capture is
//               still ~6 clocks before Oled_Display samples the colour.
//=============================================================================
module mux_video (
    input  wire                      clk,
    input  wire [`KL_MODE_W-1:0]     mode,
    input  wire [6:0]                px_x,
    input  wire [5:0]                px_y,
    input  wire [15:0]               px_play,
    input  wire [15:0]               px_free,
    input  wire [15:0]               px_ui,
    input  wire [15:0]               ov_color,
    input  wire                      ov_en,
    input  wire [`KL_SETTINGS_W-1:0] settings,
    output reg  [15:0]               oled_data
);
    // ---- colour bars: lane = x / 12 = (x * 43) >> 9 (exact for x < 96) ----
    wire [12:0] p43 = px_x * 6'd43;
    wire [15:0] bar_color;
    note_palette u_bars (.lane(p43[11:9]), .dark(1'b0), .color(bar_color));

    reg [15:0] base;
    always @(*) begin
        case (mode)
            `KL_MODE_PLAY: base = px_play;
            `KL_MODE_FREE: base = px_free;
            `KL_MODE_TEST: base = bar_color;
            default:       base = px_ui;
        endcase
    end
    wire [15:0] layered = ov_en ? ov_color : base;

    // ---- theme ----
    wire        light  = settings[`KL_SET_THEME];
    wire [15:0] themed = !light ? layered :
                         (layered == `KL_BLACK) ? 16'hEF7D :
                         (layered == `KL_WHITE) ? `KL_BLACK : layered;

    // ---- brightness: scale R (5b), G (6b), B (5b) independently ----
    wire [4:0] r = themed[15:11];
    wire [5:0] g = themed[10:5];
    wire [4:0] b = themed[4:0];
    reg  [4:0] r2, b2;
    reg  [5:0] g2;
    always @(*) begin
        case (settings[`KL_SET_BRIGHT])
            2'd3:    begin r2 = r;              g2 = g;              b2 = b;              end
            2'd2:    begin r2 = r - (r >> 2);   g2 = g - (g >> 2);   b2 = b - (b >> 2);   end
            2'd1:    begin r2 = r >> 1;         g2 = g >> 1;         b2 = b >> 1;         end
            default: begin r2 = r >> 2;         g2 = g >> 2;         b2 = b >> 2;         end
        endcase
    end

    // ---- capture enable: count 6 clocks after the pixel position changes ----
    reg [6:0] x_d    = 7'd0;
    reg [5:0] y_d    = 6'd0;
    reg [2:0] settle = 3'd0;
    always @(posedge clk) begin
        x_d <= px_x;
        y_d <= px_y;
        if (px_x != x_d || px_y != y_d) settle <= 3'd6;        // new pixel: restart
        else if (settle != 3'd0)        settle <= settle - 3'd1;
        if (settle == 3'd1) oled_data <= {r2, g2, b2};         // capture once settled
    end
endmodule
