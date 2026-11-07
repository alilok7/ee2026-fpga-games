`timescale 1ns / 1ps
`include "strike_defs.vh"
// save_image.v - the 128 bytes we keep in flash (layout in strike_defs.vh)
// Student D
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
    // the memory
    reg [7:0] mem [0:127];

    integer k;
    initial for (k = 0; k < 128; k = k + 1) mem[k] = 8'd0;

    // flash_ctrl writes first if both want to, otherwise persist_ctrl
    wire       we = we_flash | we_game;
    wire [6:0] wa = we_flash ? wa_flash : wa_game;
    wire [7:0] wd = we_flash ? wd_flash : wd_game;

    always @(posedge clk) begin
        if (we) mem[wa] <= wd;
    end

    // 7 read ports so every module can read at the same time
    assign rd0 = mem[ra0];
    assign rd1 = mem[ra1];
    assign rd2 = mem[ra2];
    assign rd3 = mem[ra3];
    assign rd4 = mem[ra4];
    assign rd5 = mem[ra5];
    assign rd6 = mem[ra6];
endmodule
