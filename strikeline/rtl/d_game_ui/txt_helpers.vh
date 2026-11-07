// txt_helpers.vh : helpers for building text requests (include INSIDE a module)
// Owner: Student A
function [3:0] c6;
    input [6:0] x;
    reg [12:0] p;
    begin p = ({6'd0, x} << 5) + ({6'd0, x} << 3) + ({6'd0, x} << 1) + x; c6 = p[11:8]; end
endfunction
function [2:0] f6;
    input [6:0] x;
    reg [3:0] c; reg [6:0] r;
    begin c = c6(x); r = x - {c, 2'b00} - {1'b0, c, 1'b0}; f6 = r[2:0]; end
endfunction

function [`TX_W-1:0] tx_s;
    input [10:0] addr;
    input        font;
    input [2:0]  fx, fy;
    input [15:0] fg, bg;
    input        bgen;
    tx_s = {bgen, bg, fg, fy, fx, font, addr, 1'b0, 1'b1};
endfunction

function [`TX_W-1:0] tx_l;
    input [5:0]  code;
    input        font;
    input [2:0]  fx, fy;
    input [15:0] fg, bg;
    input        bgen;
    tx_l = {bgen, bg, fg, fy, fx, font, 5'd0, code, 1'b1, 1'b1};
endfunction
function [5:0] dig;
    input [3:0] d;
    dig = 6'd16 + {2'b00, d};
endfunction
