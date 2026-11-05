`timescale 1ns / 1ps
//=============================================================================
// color_dim.v - darken an RGB565 colour by 0, 1/8 or 1/4 (lane depth haze and wood grain)
//-----------------------------------------------------------------------------
// Owner   : Student B
// Purpose : (v3.4) lane_render says how much darker a 3-D lane pixel is
//           (lvl: 0 = as is, 1 = 7/8, 2 = 3/4) and this module does the
//           per-channel subtraction c - c/8 or c - c/4. It is a module of its
//           own because lane_render asks for DSP slices for its multiplies,
//           and these small subtractions would take DSPs the chip does not
//           have (the v3.4 build needed 91 of 90). Pure combinational.
//=============================================================================
module color_dim (
    input  wire [15:0] c,
    input  wire [1:0]  lvl,
    output reg  [15:0] o
);
    wire [4:0] r = c[15:11], b = c[4:0];
    wire [5:0] g = c[10:5];
    always @(*) begin
        case (lvl)
            2'd1:    o = {r - (r >> 3), g - (g >> 3), b - (b >> 3)};
            2'd2,
            2'd3:    o = {r - (r >> 2), g - (g >> 2), b - (b >> 2)};
            default: o = c;
        endcase
    end
endmodule
