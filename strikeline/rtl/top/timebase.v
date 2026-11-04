`timescale 1ns / 1ps
//=============================================================================
// timebase.v : the ONE place where slow timing is made
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student B (owns the physics tick)
// Purpose     : Everything runs on the single 100 MHz clock. Instead of
//               dividing the clock for each module (the Lab 4 clock-divider
//               style) we divide ONCE here and hand out 1-cycle "tick"
//               pulses that modules use as clock ENABLES:
//                  if (tick_phys) ...   inside a 100 MHz always block.
//               One clock domain = no skew, and timing analysis checks
//               every path.
// Ticks
//   tick_1ms     1 kHz  (100 000 clocks)        debouncing, UI timers
//   tick_sample  200 Hz (500 000 clocks)        gesture sampling (A)
//   tick_phys    1024 Hz (97 656 clocks)        physics step (B, C)
//                1024 = 2^10, so "per second" constants are shifts.
//                sw[3] slow motion passes only every 4th tick; sw[0] pause
//                blocks it completely (and blocks tick_sample, tick_game).
//   tick_game    tick_1ms gated by pause, for game timers (popups, settle)
//   tick_frame   one pulse per OLED frame (60 Hz) at the END of the pixel
//                stream, so state updated on it never tears a frame.
//   clk6p25m     100 MHz / 16, ONLY for Oled_Display.
//=============================================================================
module timebase #(
    parameter MS_DIV   = 100_000,     // 100 MHz / 1 kHz (testbenches shrink these)
    parameter PHYS_DIV = 97_656,      // 100 MHz / 1024 Hz
    parameter SMP_DIV  = 500_000      // 100 MHz / 200 Hz
) (
    input  wire clk,
    input  wire rst,
    input  wire paused,               // sw[0]
    input  wire slowmo,               // sw[3] (or replay)
    input  wire oled_sending,
    output reg  tick_1ms,
    output reg  tick_game,
    output reg  tick_sample,
    output reg  tick_phys,
    output reg  tick_frame,
    output wire clk6p25m
);
    // --- 6.25 MHz for the OLED: bit 3 of a free-running counter. Not reset,
    //     so the OLED keeps its clock through a soft reset.
    reg [3:0] div16 = 4'd0;
    always @(posedge clk) div16 <= div16 + 4'd1;
    assign clk6p25m = div16[3];

    // --- the three counters are the lab "count to N then wrap" pattern ---
    reg [16:0] ms_cnt;
    reg [16:0] ph_cnt;
    reg [18:0] sm_cnt;
    reg [1:0]  slow_cnt;              // passes 1 of every 4 physics ticks
    always @(posedge clk) begin
        if (rst) begin
            ms_cnt <= 0; ph_cnt <= 0; sm_cnt <= 0; slow_cnt <= 0;
            tick_1ms <= 0; tick_game <= 0; tick_sample <= 0; tick_phys <= 0;
        end else begin
            tick_1ms    <= (ms_cnt == MS_DIV - 1);
            tick_game   <= (ms_cnt == MS_DIV - 1) && !paused;
            tick_sample <= (sm_cnt == SMP_DIV - 1) && !paused;
            ms_cnt <= (ms_cnt == MS_DIV - 1)   ? 17'd0 : ms_cnt + 17'd1;
            sm_cnt <= (sm_cnt == SMP_DIV - 1)  ? 19'd0 : sm_cnt + 19'd1;
            if (ph_cnt == PHYS_DIV - 1) begin
                ph_cnt   <= 17'd0;
                slow_cnt <= slow_cnt + 2'd1;
                tick_phys <= !paused && (!slowmo || slow_cnt == 2'd0);
            end else begin
                ph_cnt    <= ph_cnt + 17'd1;
                tick_phys <= 1'b0;
            end
        end
    end

    // --- frame tick: falling edge of oled_sending (6.25 MHz domain), after
    //     a 2-flop synchroniser (same idea as the button synchroniser, L1).
    reg [2:0] send_sync;
    always @(posedge clk) begin
        if (rst) begin
            send_sync  <= 3'b000;
            tick_frame <= 1'b0;
        end else begin
            send_sync  <= {send_sync[1:0], oled_sending};
            tick_frame <= send_sync[2] & ~send_sync[1];
        end
    end
endmodule
