`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// pin_settle.v : decides when the pin action is over, and what it scored
//-----------------------------------------------------------------------------
// Owner   : Student C
// Purpose : After a throw we must wait until nothing on the deck moves.
//           "Quiet" = no pin wobbling or falling and every fallen pin has
//           stopped sliding (busy = 0).
//             done when: the ball is in the pit AND quiet for 0.5 s
//             or       : 4 s after the ball reached the deck (timeout). The
//                        timeout forces wobblers upright and fallen pins
//                        still, so a pin rocking forever cannot hang a game.
//           Then the result: pins knocked down this ball = pins standing
//           at the throw AND not standing now (popcount), plus the split
//           flag from split_detect.
// FSM     : IDLE -> (throw) ROLL -> (ball in pit) QUIET -> FINISH ->
//           SPLIT -> IDLE.  Timeout jumps from ROLL/QUIET to FORCE.
//=============================================================================
module pin_settle (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_phys,
    input  wire        throw_go,         // the ball was released
    input  wire [`BP_W-1:0] ball_phase,
    input  wire [15:0] ball_y,
    input  wire [9:0]  standing,
    input  wire [9:0]  busy,
    output reg         force_settle,
    output reg         settle_done,      // 1-cycle: results below are valid
    output reg  [3:0]  pins_down_this_ball,
    output reg         split_flag,
    output reg  [9:0]  standing_before
);

    // ---------- 1. Constants and states ----------
    localparam [12:0] QUIET_T   = 13'd512;          // 0.5 s
    localparam [12:0] TIMEOUT_T = 13'd4096;         // 4 s

    localparam [2:0] S_IDLE   = 3'd0;
    localparam [2:0] S_ROLL   = 3'd1;
    localparam [2:0] S_QUIET  = 3'd2;
    localparam [2:0] S_FORCE  = 3'd3;
    localparam [2:0] S_FINISH = 3'd4;
    localparam [2:0] S_SPLIT  = 3'd5;

    reg [2:0]  STATE;
    reg [12:0] QUIET_COUNT, DECK_COUNT;
    reg        ON_DECK;
    reg [4:0]  WAIT_COUNT;

    wire BALL_DONE = (ball_phase == `BP_PIT);
    wire QUIET     = (busy == 10'd0);

    // ---------- 2. Split detector ----------
    reg  SPLIT_START;
    wire SPLIT_RESULT, SPLIT_DONE;
    split_detect split_module (
        .clk(clk), .rst(rst), .start(SPLIT_START), .standing(standing),
        .split(SPLIT_RESULT), .done(SPLIT_DONE));

    // ---------- 3. Popcount of the knocked-down pins ----------
    reg [3:0] DOWN_COUNT;
    integer k;
    always @ (*) begin
        DOWN_COUNT = 4'd0;
        for (k = 0; k < 10; k = k + 1)
            DOWN_COUNT = DOWN_COUNT + (standing_before[k] & ~standing[k]);
    end

    // ---------- 4. FSM ----------
    always @ (posedge clk) begin
        force_settle <= 1'b0;
        settle_done <= 1'b0;
        SPLIT_START <= 1'b0;
        if (rst) begin
            STATE <= S_IDLE;
            QUIET_COUNT <= 0;
            DECK_COUNT <= 0;
            ON_DECK <= 1'b0;
            WAIT_COUNT <= 0;
            pins_down_this_ball <= 0;
            split_flag <= 0;
            standing_before <= 10'h3FF;
        end
        else begin
            // timeout clock: runs once the ball reached the pin deck
            if (STATE == S_ROLL || STATE == S_QUIET) begin
                if (ball_y >= `W_DECK_Y || BALL_DONE)
                    ON_DECK <= 1'b1;
                if (tick_phys && ON_DECK)
                    DECK_COUNT <= DECK_COUNT + 13'd1;
            end

            case (STATE)
                S_IDLE: begin
                    if (throw_go) begin
                        standing_before <= standing;
                        ON_DECK <= 1'b0;
                        DECK_COUNT <= 0;
                        QUIET_COUNT <= 0;
                        STATE <= S_ROLL;
                    end
                end

                S_ROLL: begin
                    if (DECK_COUNT == TIMEOUT_T)
                        STATE <= S_FORCE;
                    else if (BALL_DONE)
                        STATE <= S_QUIET;
                end

                S_QUIET: begin
                    if (!QUIET)
                        QUIET_COUNT <= 0;
                    else if (tick_phys)
                        QUIET_COUNT <= QUIET_COUNT + 13'd1;

                    if (DECK_COUNT == TIMEOUT_T)
                        STATE <= S_FORCE;
                    else if (QUIET_COUNT == QUIET_T) begin
                        WAIT_COUNT <= 0;
                        STATE <= S_FINISH;
                    end
                end

                S_FORCE: begin                          // tell pin_physics to finish every animation
                    force_settle <= 1'b1;
                    WAIT_COUNT <= 0;
                    STATE <= S_FINISH;
                end

                S_FINISH: begin                         // give pin_physics 32 clocks to apply it
                    WAIT_COUNT <= WAIT_COUNT + 5'd1;
                    if (WAIT_COUNT == 5'd31) begin
                        SPLIT_START <= 1'b1;
                        STATE <= S_SPLIT;
                    end
                end

                S_SPLIT: begin
                    if (SPLIT_DONE) begin
                        pins_down_this_ball <= DOWN_COUNT;
                        split_flag <= SPLIT_RESULT;
                        settle_done <= 1'b1;
                        STATE <= S_IDLE;
                    end
                end

                default: STATE <= S_IDLE;
            endcase
        end
    end
endmodule
