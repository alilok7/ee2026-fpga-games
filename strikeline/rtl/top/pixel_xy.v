`timescale 1ns / 1ps
//=============================================================================
// pixel_xy.v : pixel_index -> (x, y), computed ONCE and broadcast
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student D
// Purpose     : The project manual hints at x = index % 96, y = index / 96.
//               A real divider is large and slow, so we use the fact that
//               96 = 32 * 3:
//                   y = (index / 32) / 3   and   n / 3 == (n * 171) >> 9
//               for every n in 0..191 (checked exhaustively in
//               sim/d/tb_pixel_xy.v). "* 171" is a constant, so synthesis
//               builds it from a few adders (171 = 128 + 32 + 8 + 2 + 1).
//               Then x = index - 96*y = index - (y << 6) - (y << 5).
// Pipeline    : 2 registers (capture index, register x/y). Oled_Display holds
//               pixel_index steady for 16 system clocks before it samples
//               pixel_data (see docs/INTERFACES.md, "Pixel timing"), so the
//               2 + 1 cycle video pipeline has 13 cycles of margin.
// Ports
//   pixel_index  0..6143 from Oled_Display (6.25 MHz domain, slow-changing)
//   px_x         0..95, px_y 0..63 (100 MHz domain)
//=============================================================================
module pixel_xy (
    input  wire        clk,
    input  wire [12:0] pixel_index,
    output reg  [6:0]  px_x,
    output reg  [5:0]  px_y
);
    // Stage 1: bring the index into the 100 MHz domain. It changes only once
    // every 256 system clocks, so a single register is enough; a value
    // caught mid-change is overwritten by the correct one the next cycle,
    // long before the OLED samples the colour.
    reg [12:0] idx;
    always @(posedge clk) idx <= pixel_index;

    // Stage 2: divide-free x / y
    wire [7:0]  n    = idx[12:5];                 // index / 32, 0..191
    wire [15:0] prod = n * 8'd171;                // constant multiply
    wire [5:0]  y    = prod[14:9];                // >> 9  ==  n / 3
    wire [12:0] y96  = {y, 6'b0} + {1'b0, y, 5'b0};
    wire [12:0] x    = idx - y96;

    always @(posedge clk) begin
        px_y <= y;
        px_x <= x[6:0];
    end
endmodule
