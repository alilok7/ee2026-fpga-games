`timescale 1ns / 1ps
//=============================================================================
// text_grid.v : pixel -> character cell coordinates
//-----------------------------------------------------------------------------
// Owner   : Student D (text engine)
// Purpose : The screen is a 16 x 8 grid of 6x8-pixel cells.
//             col = x / 6  computed as (x * 43) >> 8   (exact for x < 96)
//             fx  = x - 6*col = x - (col << 2) - (col << 1)   (0..5)
//             row = y >> 3,  fy = y & 7
//           For 2x text one character covers 2x2 cells (12x16 pixels):
//             col2 = col >> 1, and the pixel inside the 12-wide character
//             is fx2 = (col[0] ? fx + 6 : fx) >> 1. fy2 depends on which
//             row the big text starts on, so the screen computes it as
//             {row[0] ^ start_row[0], fy[2:1]}.
//           Pure combinational; renderers that draw text instantiate it.
//=============================================================================
module text_grid (
    input  wire [6:0] px_x,
    input  wire [5:0] px_y,
    output wire [3:0] col,
    output wire [2:0] fx,
    output wire [2:0] row,
    output wire [2:0] fy,
    output wire [2:0] col2,
    output wire [2:0] fx2
);
    wire [12:0] prod = px_x * 6'd43;
    assign col  = prod[11:8];
    wire [6:0] col6 = {col, 2'b00} + {1'b0, col, 1'b0};
    wire [6:0] fxw  = px_x - col6;
    assign fx   = fxw[2:0];
    assign row  = px_y[5:3];
    assign fy   = px_y[2:0];
    assign col2 = col[3:1];
    wire [3:0] fx12 = col[0] ? {1'b0, fx} + 4'd6 : {1'b0, fx};
    assign fx2  = fx12[3:1];
endmodule
