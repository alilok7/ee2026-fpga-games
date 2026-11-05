`timescale 1ns / 1ps
//=============================================================================
// button_events.v - press / long press / auto-repeat for one button
//-----------------------------------------------------------------------------
// Owner   : Student D
// The menus need three kinds of pulse from one debounced button:
//   press         when the button goes down
//   long_press    once, after it has been held for LONG_MS ms
//   repeat_pulse  after REP_DELAY ms, then every REP_PERIOD ms while held
//                 (so holding Down keeps scrolling a list)
// Each output has its own small always block so it is easy to follow:
//   1. prev       last value of the button (for edge detection, Lab 4)
//   2. press      rising edge = level is 1 now and was 0 last clock
//   3. hold_ms    how many ms the button has been held
//   4. long_press compare hold_ms with LONG_MS
//   5. repeat     a second counter that restarts every REP_PERIOD ms
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
    reg [10:0] hold_ms;                // counts up to 2047 ms and then stops
    reg [6:0]  rep_ms;

    wire rising = (level == 1) && (prev == 0);    // button just went down
    wire held   = (level == 1) && (prev == 1);    // button is still down

    // 1. remember the last value (on reset too, so a button held through
    //    reset is not counted as a press)
    always @(posedge clk) begin
        prev <= level;
    end

    // 2. press pulse
    always @(posedge clk) begin
        if (rst == 1)
            press <= 0;
        else if (rising)
            press <= 1;
        else
            press <= 0;
    end

    // 3. hold time in ms
    always @(posedge clk) begin
        if (rst == 1 || level == 0 || rising)
            hold_ms <= 0;
        else if (tick_1ms == 1 && hold_ms != 11'd2047)
            hold_ms <= hold_ms + 1;
    end

    // 4. long press pulse (once, when hold_ms reaches LONG_MS)
    always @(posedge clk) begin
        if (rst == 1)
            long_press <= 0;
        else if (held && tick_1ms == 1 && hold_ms == LONG_MS - 1)
            long_press <= 1;
        else
            long_press <= 0;
    end

    // 5. repeat pulses
    always @(posedge clk) begin
        if (rst == 1) begin
            repeat_pulse <= 0;
            rep_ms       <= 0;
        end
        else begin
            repeat_pulse <= 0;
            if (rising) begin
                rep_ms <= 0;
            end
            else if (held && tick_1ms == 1) begin
                if (hold_ms == REP_DELAY - 1) begin           // first repeat
                    repeat_pulse <= 1;
                    rep_ms       <= 0;
                end
                else if (hold_ms >= REP_DELAY) begin          // the next ones
                    if (rep_ms == REP_PERIOD - 1) begin
                        repeat_pulse <= 1;
                        rep_ms       <= 0;
                    end
                    else begin
                        rep_ms <= rep_ms + 1;
                    end
                end
            end
        end
    end
endmodule
