`timescale 1ns / 1ps
// button_events.v : press / long-press / auto-repeat for ONE debounced button
// Owner: Student A
module button_events #(
    parameter LONG_MS = 1000,
    parameter REP_DELAY = 400,
    parameter REP_PERIOD = 100,
    parameter HOLD_W = 10,
    parameter REPEAT_W = 9
) (
    input wire clk, rst, tick_1ms, level,
    output reg press, long_press, repeat_pulse
);
    localparam IDLE = 0, HELD = 1, REPEATING = 2;
    reg [1:0] state;
    reg [1:0] next_state;
    reg [HOLD_W-1:0] hold_ms;
    reg [REPEAT_W-1:0] repeat_ms;

    reg [2:0] startup;

    always @(*) begin
        next_state = state;
        if (startup != 4) begin
            if (level) next_state = HELD;
            else next_state = IDLE;
        end else if (!level) begin
            next_state = IDLE;
        end else begin
            case (state)
                IDLE: next_state = HELD;
                HELD: begin
                    if (tick_1ms && repeat_ms == REP_DELAY - 1) next_state = REPEATING;
                end
                REPEATING: next_state = REPEATING;
                default: next_state = IDLE;
            endcase
        end
    end

    always @(posedge clk) begin
        if (rst) state <= IDLE;
        else state <= next_state;
    end

    always @(posedge clk) begin
        press <= 0;
        long_press <= 0;
        repeat_pulse <= 0;

        if (rst) begin
            hold_ms <= 0;
            repeat_ms <= 0;
            startup <= 0;
        end else if (startup != 4) begin
            startup <= startup + 1'b1;
            hold_ms <= 0;
            repeat_ms <= 0;
        end else if (!level) begin
            hold_ms <= 0;
            repeat_ms <= 0;
        end else begin
            if (state != IDLE && tick_1ms && hold_ms < LONG_MS) begin
                hold_ms <= hold_ms + 1;
                if (hold_ms == LONG_MS - 1) long_press <= 1;
            end

            case (state)
                IDLE: begin
                    press <= 1;

                    hold_ms <= 0;
                    repeat_ms <= 0;
                end
                HELD: begin
                    if (tick_1ms) begin
                        if (repeat_ms == REP_DELAY - 1) begin
                            repeat_pulse <= 1;
                            repeat_ms <= 0;
                        end else begin
                            repeat_ms <= repeat_ms + 1;
                        end
                    end
                end
                REPEATING: begin
                    if (tick_1ms) begin
                        if (repeat_ms == REP_PERIOD - 1) begin
                            repeat_pulse <= 1;
                            repeat_ms <= 0;
                        end else begin
                            repeat_ms <= repeat_ms + 1;
                        end
                    end
                end
                default: begin
                    hold_ms <= 0;
                    repeat_ms <= 0;
                end
            endcase
        end
    end
endmodule
