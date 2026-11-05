`timescale 1ns / 1ps
//=============================================================================
// debounce.v - debouncer for one switch or button
//-----------------------------------------------------------------------------
// Owner   : Student D
// How it works:
//   A switch "bounces" for a few ms when it moves. We keep the last accepted
//   value in `level`. When din is different from level we count milliseconds
//   (tick_1ms comes from timebase.v, once every 100,000 clocks). If din stays
//   different for N_MS ms in a row, we accept it. If din goes back to the old
//   value before that, the count starts again from 0.
//   This is a counter with an enable, like the Lab 4 counters.
// Ports
//   din      input, already passed through 2 flip-flops (input_conditioner)
//   level    the clean (debounced) value
//   toggled  1 for one clock when level changes (not used at the moment)
// Reset: level is loaded with din, so a switch that is already up at power-on
//   is not seen as a change.
//=============================================================================
module debounce #(
    parameter N_MS = 5,              // how many ms din must stay stable
    parameter W    = 4               // counter width (2^W must be > N_MS)
) (
    input  wire clk,
    input  wire rst,
    input  wire tick_1ms,
    input  wire din,
    output reg  level,
    output reg  toggled
);
    reg [W-1:0] count;

    always @(posedge clk) begin
        if (rst == 1) begin
            level   <= din;
            count   <= 0;
            toggled <= 0;
        end
        else begin
            toggled <= 0;                         // only high for one clock

            if (din == level) begin
                count <= 0;                       // same as before: nothing to do
            end
            else if (tick_1ms == 1) begin         // different: count 1 ms
                if (count == N_MS - 1) begin      // different for N_MS ms
                    level   <= din;
                    toggled <= 1;
                    count   <= 0;
                end
                else begin
                    count <= count + 1;
                end
            end
        end
    end
endmodule
