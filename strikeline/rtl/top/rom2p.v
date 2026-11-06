`timescale 1ns / 1ps
//=============================================================================
// rom2p.v - a ROM in block RAM with two registered read ports (v3 resource squeeze)
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student C (v3.5 team split; before: shared helper (used by C's pin_render))
// Purpose : a renderer that looks the same table up for 10 pins at once
//           needed 10 LUT copies of it. In block RAM each copy costs no LUTs
//           and serves 2 pins. The read is registered (1 clock); render_scan
//           holds every pixel for 8 clocks and the XDC gives the address and
//           the data 3 clocks each, so the answer is ready in time.
//=============================================================================
module rom2p #(
    parameter AW = 9,
    parameter DW = 4,
    parameter FILE = "pin_fp.mem"
) (
    input  wire          clk,
    input  wire [AW-1:0] a0,
    input  wire [AW-1:0] a1,
    output reg  [DW-1:0] d0,
    output reg  [DW-1:0] d1
);

    (* rom_style = "block" *) reg [DW-1:0] ROM [0:(1 << AW) - 1];
    initial $readmemh(FILE, ROM);

    always @ (posedge clk) begin
        d0 <= ROM[a0];
        d1 <= ROM[a1];
    end
endmodule
