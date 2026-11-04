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
// FSM     : IDLE -> (throw) ROLLING -> (ball in pit) QUIET -> FINISH ->
//           SPLIT -> IDLE.  Timeout jumps from ROLLING/QUIET to FORCE.
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
    localparam [12:0] QUIET_T   = 13'd512;          // 0.5 s
    localparam [12:0] TIMEOUT_T = 13'd4096;         // 4 s

    localparam S_IDLE = 3'd0, S_ROLL = 3'd1, S_QUIET = 3'd2, S_FORCE = 3'd3,
               S_FINISH = 3'd4, S_SPLIT = 3'd5;
    reg [2:0]  st;
    reg [12:0] quiet_cnt, deck_cnt;
    reg        on_deck;
    reg [4:0]  wait_cnt;

    wire ball_done = (ball_phase == `BP_PIT);
    wire quiet     = (busy == 10'd0);

    reg  sp_start;
    wire sp_split, sp_done;
    split_detect u_split (.clk(clk), .rst(rst), .start(sp_start), .standing(standing),
                          .split(sp_split), .done(sp_done));

    // popcount of the knocked-down pins
    reg [3:0] cnt;
    integer k;
    always @(*) begin
        cnt = 4'd0;
        for (k = 0; k < 10; k = k + 1)
            cnt = cnt + (standing_before[k] & ~standing[k]);
    end

    always @(posedge clk) begin
        force_settle <= 1'b0; settle_done <= 1'b0; sp_start <= 1'b0;
        if (rst) begin
            st <= S_IDLE; quiet_cnt <= 0; deck_cnt <= 0; on_deck <= 1'b0; wait_cnt <= 0;
            pins_down_this_ball <= 0; split_flag <= 0; standing_before <= 10'h3FF;
        end else begin
            // timeout clock: runs once the ball reached the pin deck
            if (st == S_ROLL || st == S_QUIET) begin
                if (ball_y >= `W_DECK_Y || ball_done) on_deck <= 1'b1;
                if (tick_phys && on_deck) deck_cnt <= deck_cnt + 13'd1;
            end
            case (st)
                S_IDLE: if (throw_go) begin
                    standing_before <= standing;
                    on_deck <= 1'b0; deck_cnt <= 0; quiet_cnt <= 0;
                    st <= S_ROLL;
                end
                S_ROLL: begin
                    quiet_cnt <= 0;
                    if (deck_cnt == TIMEOUT_T) st <= S_FORCE;
                    else if (ball_done) st <= S_QUIET;
                end
                S_QUIET: begin
                    if (!quiet) quiet_cnt <= 0;
                    else if (tick_phys) quiet_cnt <= quiet_cnt + 13'd1;
                    if (deck_cnt == TIMEOUT_T) st <= S_FORCE;
                    else if (quiet_cnt == QUIET_T) begin wait_cnt <= 0; st <= S_FINISH; end
                end
                S_FORCE: begin                          // tell C to finish every animation
                    force_settle <= 1'b1;
                    wait_cnt <= 0;
                    st <= S_FINISH;
                end
                S_FINISH: begin                         // give C a few clocks to apply it
                    wait_cnt <= wait_cnt + 5'd1;
                    if (wait_cnt == 5'd31) begin sp_start <= 1'b1; st <= S_SPLIT; end
                end
                S_SPLIT: if (sp_done) begin
                    pins_down_this_ball <= cnt;
                    split_flag  <= sp_split;
                    settle_done <= 1'b1;
                    st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
