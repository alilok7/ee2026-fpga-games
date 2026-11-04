`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// save_image.v : the 128-byte image of everything that survives power-off
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : The single source of truth for settings, lifetime stats, the two
//           top-5 tables and the game in progress (layout: IM_* in
//           strike_defs.vh). It is a small distributed RAM: one write port
//           and several asynchronous read ports (Vivado copies the 128 x 8
//           RAM once per read port, ~16 LUTs each).
//           Writers: flash_ctrl (loading at boot, has priority) and
//           persist_ctrl (all game updates). They never overlap in time:
//           loading finishes before the title screen accepts a click.
//=============================================================================
module save_image (
    input  wire       clk,
    input  wire       we_flash,
    input  wire [6:0] wa_flash,
    input  wire [7:0] wd_flash,
    input  wire       we_game,
    input  wire [6:0] wa_game,
    input  wire [7:0] wd_game,
    input  wire [6:0] ra0, ra1, ra2, ra3, ra4, ra5, ra6,
    output wire [7:0] rd0, rd1, rd2, rd3, rd4, rd5, rd6
);
    reg [7:0] mem [0:127];
    integer k;
    initial for (k = 0; k < 128; k = k + 1) mem[k] = 8'd0;

    wire       we = we_flash | we_game;
    wire [6:0] wa = we_flash ? wa_flash : wa_game;
    wire [7:0] wd = we_flash ? wd_flash : wd_game;
    always @(posedge clk) if (we) mem[wa] <= wd;

    assign rd0 = mem[ra0];
    assign rd1 = mem[ra1];
    assign rd2 = mem[ra2];
    assign rd3 = mem[ra3];
    assign rd4 = mem[ra4];
    assign rd5 = mem[ra5];
    assign rd6 = mem[ra6];
endmodule
