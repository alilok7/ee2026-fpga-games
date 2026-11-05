`timescale 1ns / 1ps
//=============================================================================
// string_rom.v : every on-screen word, as glyph codes
//-----------------------------------------------------------------------------
// Owner   : Student D (shared text engine). Screen 1 uses one 2048-deep copy;
//           Student C's screen 2 has its own small ROM (AW = 9, 512 deep).
// Purpose : Screens never compare against hard-coded characters; they ask
//           for "character k of string S" = rom[S_<name> + k]. Addresses and
//           lengths are in strings_map.vh, generated with the data by
//           tools/strings_to_mem.py from text/strings.txt.
//           2048 x 6 bits, combinational read (distributed ROM).
//=============================================================================
module string_rom #(
    parameter MEM_FILE = "strings.mem",
    parameter AW       = 11              // address bits: depth = 2^AW
) (
    input  wire [10:0] addr,
    output wire [5:0]  ch
);
    reg [5:0] rom [0:(1 << AW) - 1];
    initial $readmemh(MEM_FILE, rom);
    assign ch = rom[addr[AW-1:0]];
endmodule
