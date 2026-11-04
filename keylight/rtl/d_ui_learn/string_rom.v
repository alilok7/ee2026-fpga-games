`timescale 1ns / 1ps
//=============================================================================
// string_rom.v : every on-screen word, as glyph codes
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : Screens never compare against hard-coded characters; they ask
//           for "character k of string S" = rom[S_<name> + k]. Addresses and
//           lengths are in strings_map.vh, generated with the data by
//           tools/strings_to_mem.py from text/strings.txt.
//           1024 x 6 bits, combinational read (distributed ROM).
//=============================================================================
module string_rom #(
    parameter MEM_FILE = "strings.mem"
) (
    input  wire [9:0] addr,
    output wire [5:0] ch
);
    reg [5:0] rom [0:1023];
    initial $readmemh(MEM_FILE, rom);
    assign ch = rom[addr];
endmodule
