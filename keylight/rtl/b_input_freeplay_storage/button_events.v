`timescale 1ns / 1ps
//=============================================================================
// button_events.v : press / long-press / auto-repeat for ONE debounced button
//-----------------------------------------------------------------------------
// Owner   : Student B
// Purpose : Menus need three kinds of event from a single button:
//             press   - the moment it goes down
//             long    - once, when it has been held for LONG_MS
//             repeat  - after REP_DELAY ms, then every REP_PERIOD ms while
//                       held (holding Down scrolls a list)
//           A hold-time counter (in ms) drives all three, like the lab's
//           counters that advance on a 1 kHz enable.
// Ports
//   level   debounced button level (from debounce.v)
//   press, long_press, repeat   1-cycle pulses
//=============================================================================
module button_events #(
    parameter LONG_MS    = 1000,
    parameter REP_DELAY  = 400,
    parameter REP_PERIOD = 100
) (
    input  wire clk,
    input  wire rst,
    input  wire tick_1ms,
    input  wire level,
    output reg  press,
    output reg  long_press,
    output reg  repeat_pulse
);
    reg        prev;
    reg [10:0] hold_ms;                 // saturates at 2047 ms
    reg [6:0]  rep_ms;

    always @(posedge clk) begin
        press        <= 1'b0;
        long_press   <= 1'b0;
        repeat_pulse <= 1'b0;
        if (rst) begin
            prev    <= level;           // a button held through reset is not a press
            hold_ms <= 11'd0;
            rep_ms  <= 7'd0;
        end else begin
            prev <= level;
            if (level && !prev) begin                    // rising edge
                press   <= 1'b1;
                hold_ms <= 11'd0;
                rep_ms  <= 7'd0;
            end else if (level && tick_1ms) begin
                if (hold_ms != 11'h7FF) hold_ms <= hold_ms + 11'd1;
                if (hold_ms == LONG_MS - 1) long_press <= 1'b1;
                if (hold_ms == REP_DELAY - 1) begin
                    repeat_pulse <= 1'b1;
                    rep_ms       <= 7'd0;
                end else if (hold_ms >= REP_DELAY) begin
                    if (rep_ms == REP_PERIOD - 1) begin
                        repeat_pulse <= 1'b1;
                        rep_ms       <= 7'd0;
                    end else begin
                        rep_ms <= rep_ms + 7'd1;
                    end
                end
            end
        end
    end
endmodule
