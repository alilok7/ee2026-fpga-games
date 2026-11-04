`timescale 1ns / 1ps
//=============================================================================
// timebase.v : the ONE place where slow timing is made
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student A
// Purpose     : Every module runs on the single 100 MHz clock. Instead of each
//               module making its own slow clock (the Lab 4 "clock divider"
//               style), we divide ONCE here and hand out 1-cycle-wide
//               "tick" pulses (clock enables). A module that wants to act at
//               1 kHz writes   if (tick_1ms) ...   inside its 100 MHz block.
//               This is the same counter as the lab clock divider, but the
//               counter output is used as an enable, not as a clock, so the
//               whole design stays in one clock domain (no clock skew and
//               timing analysis can check every path).
// Ports
//   clk          100 MHz board clock (W5)
//   rst          synchronous active-high reset
//   oled_sending Oled_Display.sending_pixels (6.25 MHz domain): high while a
//                frame is being streamed to the screen
//   tick_1ms     1 pulse every 100 000 clocks (1 kHz)
//   tick_sample  1 pulse every 2 048 clocks (48 828.125 Hz audio rate)
//   tick_frame   1 pulse per OLED frame (60 Hz), at the END of the pixel
//                stream, so game state updated on this tick never changes
//                while a frame is being drawn (no tearing)
//   clk6p25m     100 MHz / 16 = 6.25 MHz square wave, ONLY for Oled_Display
// Timing : all ticks are registered and last exactly one clk period.
//=============================================================================
module timebase #(
    parameter MS_DIV = 100_000         // 100 MHz / 1 kHz (testbenches use less)
) (
    input  wire clk,
    input  wire rst,
    input  wire oled_sending,
    output reg  tick_1ms,
    output reg  tick_sample,
    output reg  tick_frame,
    output wire clk6p25m
);
    localparam SAMPLE_DIV = 2_048;     // power of two -> the counter just wraps

    // --- 6.25 MHz for the OLED: bit 3 of a free-running 4-bit counter -------
    // Not reset on purpose: the OLED clock must keep running so the
    // Oled_Display state machine can come out of its own reset cleanly.
    reg [3:0] div16 = 4'd0;
    always @(posedge clk) div16 <= div16 + 4'd1;
    assign clk6p25m = div16[3];        // 8 clocks high, 8 clocks low

    // --- 1 kHz tick ---------------------------------------------------------
    reg [16:0] ms_cnt;
    always @(posedge clk) begin
        if (rst) begin
            ms_cnt   <= 17'd0;
            tick_1ms <= 1'b0;
        end else if (ms_cnt == MS_DIV - 1) begin
            ms_cnt   <= 17'd0;
            tick_1ms <= 1'b1;
        end else begin
            ms_cnt   <= ms_cnt + 17'd1;
            tick_1ms <= 1'b0;
        end
    end

    // --- audio sample tick --------------------------------------------------
    reg [10:0] smp_cnt;
    always @(posedge clk) begin
        if (rst) begin
            smp_cnt     <= 11'd0;
            tick_sample <= 1'b0;
        end else begin
            smp_cnt     <= smp_cnt + 11'd1;          // wraps at 2048
            tick_sample <= (smp_cnt == SAMPLE_DIV - 1);
        end
    end

    // --- frame tick: falling edge of oled_sending ---------------------------
    // oled_sending comes from the 6.25 MHz domain, so it passes through a
    // 2-flop synchroniser first (same idea as the button synchroniser, L1).
    reg [2:0] send_sync;
    always @(posedge clk) begin
        if (rst) begin
            send_sync  <= 3'b000;
            tick_frame <= 1'b0;
        end else begin
            send_sync  <= {send_sync[1:0], oled_sending};
            tick_frame <= send_sync[2] & ~send_sync[1];   // 1 -> 0 edge
        end
    end
endmodule
