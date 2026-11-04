`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// text_engine.v : the ONE place where characters are turned into pixels
//-----------------------------------------------------------------------------
// Owner   : Student D (used by A's labels and every D screen)
// Purpose : Every text-drawing layer sends a "text request" for the current
//           pixel (strike_defs.vh, TX_*): which character (a string ROM
//           address, or a literal glyph code for digits), which font, where
//           in the glyph cell this pixel is, and its colours. The compositor
//           passes the request of the top-most text layer here, so the whole
//           design needs only one string ROM and one copy of each font:
//              string ROM (2048 x 6)  ->  glyph code
//              font ROM {glyph, row}  ->  row bits  ->  bit for column fx
//           5x7 font: bit 4 is the left column, columns 5 and up are spacing.
//           3x5 font: bit 2 is the left column, column 3 is spacing.
//=============================================================================
module text_engine (
    input  wire [`TX_W-1:0] req,
    output wire        on,               // request valid and the glyph bit is set
    output wire        in_cell,          // request valid (cell background shown?)
    output wire [15:0] fg,
    output wire [15:0] bg,
    output wire        bg_en
);
    reg [4:0] font7 [0:511];
    reg [2:0] font5 [0:511];
    initial begin
        $readmemh("font5x7.mem", font7);
        $readmemh("font3x5.mem", font5);
    end

    wire [5:0] str_ch;
    string_rom u_str (.addr(req[`TX_VAL]), .ch(str_ch));
    wire [5:0] glyph = req[`TX_LIT] ? req[7:2] : str_ch;     // VALUE[5:0]
    wire [2:0] fx = req[`TX_FX];
    wire [2:0] fy = req[`TX_FY];

    wire [4:0] r7 = font7[{glyph, fy}];
    wire [2:0] r5 = font5[{glyph, fy}];
    wire bit7 = (fx <= 3'd4) ? r7[3'd4 - fx] : 1'b0;
    wire bit5 = (fx <= 3'd2) ? r5[3'd2 - fx] : 1'b0;

    assign in_cell = req[`TX_VALID];
    assign on    = req[`TX_VALID] && (req[`TX_FONT] ? bit5 : bit7);
    assign fg    = req[`TX_FG];
    assign bg    = req[`TX_BG];
    assign bg_en = req[`TX_BGEN];
endmodule
