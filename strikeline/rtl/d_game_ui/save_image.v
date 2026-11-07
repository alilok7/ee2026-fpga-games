`timescale 1ns / 1ps
`include "strike_defs.vh"
// save_image.v : the 128 bytes that survive power-off (layout IM_* in strike_defs.vh)
// Student D. One write port (flash_ctrl at boot has priority, then persist_ctrl),
// 7 read ports: 0 flash, 1 persist, 2 C score, 3 game_fsm, 4/5 menu, 6 C turn.
module save_image (
    input  wire       clk,
    input  wire       we_flash,           // flash_ctrl: write enable
    input  wire [6:0] wa_flash,           //             address
    input  wire [7:0] wd_flash,           //             data
    input  wire       we_game,            // persist_ctrl: write enable
    input  wire [6:0] wa_game,
    input  wire [7:0] wd_game,
    input  wire [6:0] ra0, ra1, ra2, ra3, ra4, ra5, ra6,   // read addresses
    output wire [7:0] rd0, rd1, rd2, rd3, rd4, rd5, rd6    // read data
);
    // 128 x 8 memory (LUT-RAM)
    reg [7:0] mem [0:127];

    // all zero at power-on (the FPGA RAM starts this way; also needed in simulation)
    integer k;
    initial for (k = 0; k < 128; k = k + 1) mem[k] = 8'd0;

    // write port: 2-to-1 mux, flash first
    wire       we = we_flash | we_game;
    wire [6:0] wa = we_flash ? wa_flash : wa_game;
    wire [7:0] wd = we_flash ? wd_flash : wd_game;

    // write one byte per clock
    always @(posedge clk) begin
        if (we) mem[wa] <= wd;
    end

    // read ports (asynchronous: data follows the address)
    assign rd0 = mem[ra0];
    assign rd1 = mem[ra1];
    assign rd2 = mem[ra2];
    assign rd3 = mem[ra3];
    assign rd4 = mem[ra4];
    assign rd5 = mem[ra5];
    assign rd6 = mem[ra6];
endmodule
