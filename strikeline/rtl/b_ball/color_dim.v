`timescale 1ns / 1ps
// color_dim.v : darken an RGB565 colour by 0, 1/8 or 1/4
// Owner: Student B

// Kept outside lane_render so these subtractions do not take DSP slices
module color_dim (
    input  wire [15:0] c,
    input  wire [1:0]  lvl,
    output reg  [15:0] o
);
    // Each colour channel is dimmed on its own, so the hue stays the same
    wire [4:0] r = c[15:11];
    wire [5:0] g = c[10:5];
    wire [4:0] b = c[4:0];

    always @ (*) begin
        case (lvl)
            2'd1:    o = {r - (r >> 3), g - (g >> 3), b - (b >> 3)};
            2'd2,
            2'd3:    o = {r - (r >> 2), g - (g >> 2), b - (b >> 2)};
            default: o = c;
        endcase
    end
endmodule
