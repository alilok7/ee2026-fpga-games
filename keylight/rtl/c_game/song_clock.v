`timescale 1ns / 1ps
//=============================================================================
// song_clock.v : song time in milliseconds and in 16th-note steps
//-----------------------------------------------------------------------------
// Owner   : Student C
// Purpose : Two counters driven by tick_1ms (Lecture 2 counters):
//             song_ms   - milliseconds since the count-in started
//             song_step - 16th-note steps; a ms_in_step counter rolls over
//                         every step_ms ms, so no division is needed to
//                         know which beat we are on.
//           Pause (sw[0]) simply stops both counters, so EVERYTHING that is
//           timed from song_ms (falling notes, judgement, misses) freezes.
// Ports
//   run         count only while 1 (after the header is loaded)
//   beat        1-cycle pulse on the first ms of every beat (4 steps)
//   downbeat    1-cycle pulse on the first ms of every bar (16 steps)
//=============================================================================
module song_clock (
    input  wire        clk,
    input  wire        clr,
    input  wire        tick_1ms,
    input  wire        run,
    input  wire        paused,
    input  wire [9:0]  step_ms,
    output reg  [19:0] song_ms,
    output reg  [11:0] song_step,
    output reg         beat,
    output reg         downbeat
);
    reg [9:0] ms_in_step;

    always @(posedge clk) begin
        beat     <= 1'b0;
        downbeat <= 1'b0;
        if (clr) begin
            song_ms    <= 20'd0;
            song_step  <= 12'd0;
            ms_in_step <= 10'd0;
        end else if (run && !paused && tick_1ms) begin
            if (ms_in_step == 10'd0 && song_step[1:0] == 2'b00) beat <= 1'b1;
            if (ms_in_step == 10'd0 && song_step[3:0] == 4'b0000) downbeat <= 1'b1;
            if (song_ms != 20'hFFFFF) song_ms <= song_ms + 20'd1;
            if (ms_in_step == step_ms - 10'd1) begin
                ms_in_step <= 10'd0;
                song_step  <= song_step + 12'd1;
            end else begin
                ms_in_step <= ms_in_step + 10'd1;
            end
        end
    end
endmodule
