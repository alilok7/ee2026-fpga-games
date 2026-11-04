`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// chart_reader.v : ONE read port over every song chart
//-----------------------------------------------------------------------------
// Owner   : Student C (also used by D's Learn mode)
// Purpose : Hides where a song lives. Songs 0..3 come from the chart ROM
//           (data/songs.mem, 4 x 512 words, one block RAM); song 4 (MY SONG)
//           comes from B's recording RAM through the my_addr/my_data port.
//           Whoever reads (C's game or D's Learn mode, never both at once)
//           sees the same 24-bit words with the same 1-cycle latency.
// Ports
//   song_id            selected song (D)
//   sel_learn          1 = Learn mode owns the port, 0 = game engine
//   game_addr / learn_addr   word address 0..511
//   chart_data         word at the address given ONE clock earlier
//   my_addr / my_data  to/from B's MY SONG RAM (also 1-cycle latency)
//=============================================================================
module chart_reader #(
    parameter MEM_FILE = "songs.mem"
) (
    input  wire                   clk,
    input  wire [2:0]             song_id,
    input  wire                   sel_learn,
    input  wire [`KL_CHART_AW-1:0] game_addr,
    input  wire [`KL_CHART_AW-1:0] learn_addr,
    output wire [`KL_CHART_DW-1:0] chart_data,
    output wire [`KL_CHART_AW-1:0] my_addr,
    input  wire [`KL_CHART_DW-1:0] my_data
);
    // 2048 x 24 bits, synchronous read -> Vivado maps it to block RAM.
    reg [`KL_CHART_DW-1:0] rom [0:2047];
    initial $readmemh(MEM_FILE, rom);

    wire [`KL_CHART_AW-1:0] addr = sel_learn ? learn_addr : game_addr;
    reg  [`KL_CHART_DW-1:0] rom_q;
    reg                     is_my;
    always @(posedge clk) begin
        rom_q <= rom[{song_id[1:0], addr}];
        is_my <= (song_id == `KL_SONG_MYSONG);
    end

    assign my_addr    = addr;
    assign chart_data = is_my ? my_data : rom_q;
endmodule
