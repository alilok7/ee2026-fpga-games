`timescale 1ns / 1ps

module string_rom #(
    parameter MEM_FILE = "strings.mem"
) (
    input  wire [10:0] addr,
    output wire [5:0]  ch
);
    reg [5:0] rom [0:2047];
    initial $readmemh(MEM_FILE, rom);
    assign ch = rom[addr];
endmodule
