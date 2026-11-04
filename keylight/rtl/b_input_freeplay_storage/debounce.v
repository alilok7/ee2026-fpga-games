`timescale 1ns / 1ps
//=============================================================================
// debounce.v : stable-count debouncer for ONE already-synchronised input
//-----------------------------------------------------------------------------
// Owner   : Student B
// Purpose : A mechanical contact "bounces" for a few ms when it moves. We
//           only accept a new level after the input has disagreed with the
//           current level for N_MS consecutive milliseconds. Any bounce back
//           to the old level restarts the count.
//           Compared with the project manual's "200 ms lock-out" debouncer:
//           a lock-out would block a second strike for 200 ms, far too slow
//           for a rhythm game, while a stable count only adds N_MS of fixed
//           latency and allows strikes as fast as every 2*N_MS.
// Ports
//   din      synchronised input (2-flop synchroniser is in the parent)
//   level    debounced level
//   toggled  1-cycle pulse whenever `level` changes, in EITHER direction
// Reset   : `level` is loaded with the current input, so a switch that is
//           already up at power-on does NOT produce a fake strike.
//=============================================================================
module debounce #(
    parameter N_MS = 5,              // required stable time in ms
    parameter W    = 4               // counter width, 2^W > N_MS
) (
    input  wire clk,
    input  wire rst,
    input  wire tick_1ms,
    input  wire din,
    output reg  level,
    output reg  toggled
);
    reg [W-1:0] cnt;

    always @(posedge clk) begin
        toggled <= 1'b0;
        if (rst) begin
            level <= din;
            cnt   <= {W{1'b0}};
        end else if (din == level) begin
            cnt <= {W{1'b0}};                    // agrees again: forget bounce
        end else if (tick_1ms) begin
            if (cnt == N_MS - 1) begin           // disagreed for N_MS ms
                level   <= din;
                toggled <= 1'b1;
                cnt     <= {W{1'b0}};
            end else begin
                cnt <= cnt + 1'b1;
            end
        end
    end
endmodule
