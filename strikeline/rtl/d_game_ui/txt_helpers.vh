//=============================================================================
// txt_helpers.vh : helpers for building text requests (include INSIDE a module)
//-----------------------------------------------------------------------------
// Owner   : Student D (text engine)
// Cell grids
//   5x7 font : 6 x 8 px cells, 16 columns x 8 rows
//              col = x / 6 = (x * 43) >> 8 (exact for x < 128), fx = x - 6*col
//              row = y >> 3, fy = y & 7
//   3x5 font : 4 x 6 px cells, 24 columns x 10 rows
//              col = x >> 2, fx = x & 3
//              row = y / 6 = (y * 43) >> 8, fy = y - 6*row
//=============================================================================
function [3:0] c6;                 // x / 6
    input [6:0] x;
    reg [12:0] p;
    begin p = x * 6'd43; c6 = p[11:8]; end
endfunction
function [2:0] f6;                 // x mod 6
    input [6:0] x;
    reg [3:0] c; reg [6:0] r;
    begin c = c6(x); r = x - {c, 2'b00} - {1'b0, c, 1'b0}; f6 = r[2:0]; end
endfunction
// string character: string ROM address
function [`TX_W-1:0] tx_s;
    input [10:0] addr;
    input        font;              // 0 = 5x7, 1 = 3x5
    input [2:0]  fx, fy;
    input [15:0] fg, bg;
    input        bgen;
    tx_s = {bgen, bg, fg, fy, fx, font, addr, 1'b0, 1'b1};
endfunction
// literal glyph code (digits: code = 16 + digit, i.e. ASCII '0' - 0x20)
function [`TX_W-1:0] tx_l;
    input [5:0]  code;
    input        font;
    input [2:0]  fx, fy;
    input [15:0] fg, bg;
    input        bgen;
    tx_l = {bgen, bg, fg, fy, fx, font, 5'd0, code, 1'b1, 1'b1};
endfunction
function [5:0] dig;                // BCD digit -> glyph code
    input [3:0] d;
    dig = 6'd16 + {2'b00, d};
endfunction
