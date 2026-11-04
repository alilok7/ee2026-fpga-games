`timescale 1ns / 1ps
//=============================================================================
// font_rom.v : 5x7 font, one glyph row per read
//-----------------------------------------------------------------------------
// Owner   : Student D (text engine, used by B, C and D)
// Purpose : Glyph code (ASCII - 0x20) and row 0..7 -> 5 pixel bits.
//           Bit 4 is the LEFTMOST pixel, so the bit for column fx is
//           bits[4 - fx]. Data comes from tools/font_to_mem.py.
//           512 x 5 bits reads combinationally (distributed ROM in LUTs),
//           so a renderer can stay a pure function of the pixel position.
//=============================================================================
module font_rom #(
    parameter MEM_FILE = "font.mem"
) (
    input  wire [5:0] ch,
    input  wire [2:0] row,
    output wire [4:0] bits
);
    reg [4:0] rom [0:511];
    initial $readmemh(MEM_FILE, rom);
    assign bits = rom[{ch, row}];
endmodule
