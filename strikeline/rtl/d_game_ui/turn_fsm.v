`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// turn_fsm.v : the bowling sub-FSM (one ball at a time) of the game FSM
//-----------------------------------------------------------------------------
// Owner   : Student C (v3.5 team split; before: Student D)
// Lecture 4 structure: game_fsm (modes and menus) starts this FSM with
//   go_new / go_resume and gets game_over back; while it runs, game_state
//   comes from here.
// One ball: RACK -> AIM -(grab)-> THROW -(release)-> ROLL -(deck)-> PIN
//           -(ball in pit)-> SETTLE -(settle_done)-> RESULT -> NEXT
//   A rejected / cancelled swipe returns THROW -> AIM.
// Frame rules (frames 1-9): strike ends the frame, else 2 balls (rake the
//   fallen pins between them). Frame 10: a strike or spare earns more balls,
//   and a cleared deck is re-racked in full.
// Turn order: 2 players alternate every frame. Quick game = frames 8-10.
// After every finished frame: game header -> save image, then flash save.
// (The Spare Challenge is not in v3.5: spare_made / spare_tries stay 0,
//  leave_mask is not used.)
// The timer `ms` keeps its lower-case name: tb_screens forces it.
//=============================================================================
module turn_fsm (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_game,        // 1 ms, stopped while paused
    input  wire        go_new,
    input  wire        go_resume,
    input  wire [`PK_W-1:0] kind_in,
    input  wire [9:0]  leave_mask,
    input  wire        abort,
    // gesture (A)
    input  wire        grabbing,
    input  wire        throw_valid,
    input  wire        swipe_fail,       // reject / cancel / too short
    // ball (B), pins (C)
    input  wire [`BP_W-1:0] ball_phase,
    input  wire [15:0] ball_y,
    input  wire        settle_done,
    input  wire [3:0]  pins_down,
    input  wire        split_flag,
    input  wire [9:0]  standing,
    input  wire [9:0]  standing_before,
    input  wire        rack_busy,
    // user
    input  wire        skip,             // left click / btnC in RESULT
    input  wire        want_replay,      // middle click / btnD in RESULT
    input  wire        replay_done,
    // save image read port (resume)
    output reg  [6:0]  ra,
    input  wire [7:0]  rd,
    input  wire        persist_busy,
    // outputs
    output reg  [`GS_W-1:0] tstate,
    output reg  [`PK_W-1:0] kind,
    output reg         active,
    output reg         game_over,
    output reg         rack_go,
    output reg  [1:0]  rack_cmd,
    output reg  [9:0]  rack_mask,
    output reg         c_roll,
    output reg         roll_p,
    output reg  [4:0]  roll_idx,
    output reg  [3:0]  roll_val,
    output reg         c_hdr,
    output reg         hdr_valid,
    output reg         hdr_player,
    output reg  [3:0]  hdr_frame,
    output reg         c_clear,
    output reg         c_strike,
    output reg         c_spare,
    output reg         score_start,
    output reg         save_req,
    output reg         replay_start,
    output reg         replay_fast,      // this replay is the automatic one (real speed)
    output reg         player,
    output reg  [3:0]  frame,            // 0..9
    output reg  [1:0]  ball_no,          // 0..2
    output wire [3:0]  start_frame,
    output reg  [3:0]  popup_id,         // 15 = none
    output reg  [3:0]  popup_n,          // pins for the "n PINS" popup
    output reg         card_auto,        // show the scorecard (frame just ended)
    output reg         banner,           // "FRAME n" banner at a frame start
    output reg         ghost,            // first throw of the game: show the demo swipe
    output reg  [7:0]  spare_made,
    output reg  [7:0]  spare_tries
);

    // ---------- 1. Constants and states ----------
    // popup ids = slots in the popup string table (6, 7: Spare Challenge)
    localparam [3:0] P_STRIKE = 4'd0;
    localparam [3:0] P_SPARE  = 4'd1;
    localparam [3:0] P_GUTTER = 4'd2;
    localparam [3:0] P_SPLIT  = 4'd3;
    localparam [3:0] P_TURKEY = 4'd4;
    localparam [3:0] P_DOUBLE = 4'd5;
    localparam [3:0] P_PINS   = 4'd8;
    localparam [3:0] P_NONE   = 4'd15;

    // after the result: rack the standing pins, a full rack, or end the frame
    localparam [1:0] A_SWEEP = 2'd0;
    localparam [1:0] A_FULL  = 2'd1;
    localparam [1:0] A_FRAME = 2'd2;

    localparam [3:0] T_IDLE   = 4'd0;
    localparam [3:0] T_CLEAR  = 4'd1;
    localparam [3:0] T_RES    = 4'd2;
    localparam [3:0] T_RACK   = 4'd3;
    localparam [3:0] T_RACKW  = 4'd4;
    localparam [3:0] T_AIM    = 4'd5;
    localparam [3:0] T_THROW  = 4'd6;
    localparam [3:0] T_ROLL   = 4'd7;
    localparam [3:0] T_PIN    = 4'd8;
    localparam [3:0] T_SETTLE = 4'd9;
    localparam [3:0] T_RESULT = 4'd10;
    localparam [3:0] T_REPLAY = 4'd11;
    localparam [3:0] T_NEXT   = 4'd12;
    localparam [3:0] T_OVER   = 4'd13;

    reg [3:0]  STATE;
    reg [11:0] ms;                      // timer in ms
    reg [11:0] CARD_MS, BANNER_MS;
    reg [4:0]  N_ROLLS [0:1];           // rolls thrown per player
    reg [1:0]  STREAK  [0:1];           // strikes in a row per player (max 3)
    reg [3:0]  FIRST_BALL;              // first ball of this frame (10th-frame rules)
    reg [1:0]  ACTION;
    reg        GUTTER_SEEN;
    reg        SCORE_PENDING;           // rescore once persist_ctrl wrote the roll
    reg [2:0]  RESUME_STEP;
    reg [1:0]  FAIL_MS;
    reg        AUTO_DONE;               // this ball's automatic replay has been shown

    assign start_frame = kind[`PK_FULL] ? 4'd0 : 4'd7;
    wire       FULL_BEFORE = (standing_before == 10'h3FF);
    wire       CLEARED     = (standing == 10'h000);
    wire       STRIKE      = FULL_BEFORE && CLEARED;
    wire [4:0] N_CUR       = N_ROLLS[player];
    wire [1:0] CUR_STREAK  = STREAK[player];
    wire       LAST_FRAME  = (!kind[`PK_TWO] || player) && frame == 4'd9;

    // ---------- 2. Game state shown to everyone ----------
    always @ (*) begin
        case (STATE)
            T_AIM:            tstate = `GS_AIM;
            T_THROW:          tstate = `GS_THROW;
            T_ROLL:           tstate = `GS_ROLL;
            T_PIN:            tstate = `GS_PINACTION;
            T_SETTLE:         tstate = `GS_SETTLE;
            T_RESULT, T_NEXT: tstate = `GS_RESULT;
            T_REPLAY:         tstate = `GS_REPLAY;
            default:          tstate = `GS_SWEEP;    // clearing, resuming, racking
        endcase
    end

    // ---------- 3. FSM ----------
    always @ (posedge clk) begin
        // one-clock pulses
        game_over <= 0;
        rack_go <= 0;
        c_roll <= 0;
        c_hdr <= 0;
        c_clear <= 0;
        c_strike <= 0;
        c_spare <= 0;
        score_start <= 0;
        save_req <= 0;
        replay_start <= 0;

        if (rst) begin
            STATE <= T_IDLE; active <= 0; kind <= 0;
            ms <= 0; CARD_MS <= 0; BANNER_MS <= 0;
            AUTO_DONE <= 0; replay_fast <= 0;
            N_ROLLS[0] <= 0; N_ROLLS[1] <= 0; STREAK[0] <= 0; STREAK[1] <= 0;
            FIRST_BALL <= 0; ACTION <= 0; GUTTER_SEEN <= 0;
            SCORE_PENDING <= 0; RESUME_STEP <= 0; FAIL_MS <= 0; ra <= 0;
            rack_cmd <= `RK_FULL; rack_mask <= 10'h3FF; roll_p <= 0; roll_idx <= 0; roll_val <= 0;
            hdr_valid <= 0; hdr_player <= 0; hdr_frame <= 0;
            player <= 0; frame <= 0; ball_no <= 0; popup_id <= P_NONE; popup_n <= 0;
            card_auto <= 0; banner <= 0; ghost <= 0; spare_made <= 0; spare_tries <= 0;
        end
        else begin
            // background timers
            if (tick_game && ms != 12'hFFF)
                ms <= ms + 12'd1;
            if (tick_game && CARD_MS != 0)
                CARD_MS <= CARD_MS - 12'd1;
            if (tick_game && BANNER_MS != 0)
                BANNER_MS <= BANNER_MS - 12'd1;
            card_auto <= (CARD_MS != 0);
            banner <= (BANNER_MS != 0);
            if (SCORE_PENDING && !persist_busy) begin
                SCORE_PENDING <= 0;
                score_start <= 1;
            end

            if (abort && STATE != T_IDLE) begin
                STATE <= T_IDLE;
                active <= 0;
                popup_id <= P_NONE;
            end
            else case (STATE)
                T_IDLE: begin
                    if (go_new) begin
                        kind <= kind_in & 3'b011;          // no Spare Challenge bit
                        active <= 1;
                        player <= 0;
                        ball_no <= 0;
                        N_ROLLS[0] <= 0;
                        N_ROLLS[1] <= 0;
                        STREAK[0] <= 0;
                        STREAK[1] <= 0;
                        frame <= kind_in[`PK_FULL] ? 4'd0 : 4'd7;
                        ghost <= 1'b1;
                        popup_id <= P_NONE;
                        c_clear <= 1;
                        STATE <= T_CLEAR;
                    end
                    else if (go_resume) begin
                        active <= 1;
                        RESUME_STEP <= 0;
                        ra <= `IM_GKIND;
                        ghost <= 0;
                        popup_id <= P_NONE;
                        ball_no <= 0;
                        STREAK[0] <= 0;
                        STREAK[1] <= 0;
                        STATE <= T_RES;
                    end
                end

                T_CLEAR: begin
                    if (!persist_busy && !c_clear) begin
                        SCORE_PENDING <= 1;                // blank scorecard
                        BANNER_MS <= 12'd1000;
                        rack_cmd <= `RK_FULL;
                        STATE <= T_RACK;
                    end
                end

                T_RES: begin                               // read the saved header
                    RESUME_STEP <= RESUME_STEP + 3'd1;
                    // ra was set one clock earlier, so rd belongs to it
                    case (RESUME_STEP)
                        3'd0: begin kind <= rd[2:0] & 3'b011; ra <= `IM_GPLAYER; end
                        3'd1: begin player <= rd[0]; ra <= `IM_GFRAME; end
                        3'd2: begin frame <= (rd[3:0] > 4'd9) ? 4'd9 : rd[3:0]; ra <= `IM_NROLL0; end
                        3'd3: begin N_ROLLS[0] <= rd[4:0]; ra <= `IM_NROLL1; end
                        default: begin
                            N_ROLLS[1] <= rd[4:0];
                            SCORE_PENDING <= 1;
                            BANNER_MS <= 12'd1000;
                            rack_cmd <= `RK_FULL;
                            STATE <= T_RACK;
                        end
                    endcase
                end

                T_RACK: begin
                    rack_go <= 1;
                    STATE <= T_RACKW;
                end

                T_RACKW: begin
                    if (!rack_busy && !rack_go)
                        STATE <= T_AIM;
                end

                T_AIM: begin
                    if (grabbing) begin
                        FAIL_MS <= 0;
                        STATE <= T_THROW;
                    end
                end

                T_THROW: begin
                    if (throw_valid) begin
                        GUTTER_SEEN <= 0;
                        ghost <= 0;
                        ms <= 0;
                        STATE <= T_ROLL;
                    end
                    else if (swipe_fail)
                        STATE <= T_AIM;
                    else if (!grabbing && tick_game) begin      // safety: nothing came
                        FAIL_MS <= FAIL_MS + 2'd1;
                        if (FAIL_MS == 2'd3)
                            STATE <= T_AIM;
                    end
                end

                T_ROLL: begin
                    if (ball_phase == `BP_GUTTER)
                        GUTTER_SEEN <= 1;
                    if (ball_y >= `W_DECK_Y || ball_phase == `BP_PIT)
                        STATE <= T_PIN;
                end

                T_PIN: begin
                    if (ball_phase == `BP_PIT)
                        STATE <= T_SETTLE;
                end

                T_SETTLE: begin
                    if (settle_done) begin
                        ms <= 0;
                        popup_n <= pins_down;
                        AUTO_DONE <= 0;
                        STATE <= T_RESULT;

                        // record the roll
                        c_roll <= 1;
                        roll_p <= player;
                        roll_idx <= N_CUR;
                        roll_val <= pins_down;
                        N_ROLLS[player] <= N_CUR + 5'd1;
                        SCORE_PENDING <= 1;

                        // popup + lifetime stats
                        if (STRIKE) begin
                            c_strike <= 1;
                            popup_id <= (CUR_STREAK == 2'd2) ? P_TURKEY :
                                        (CUR_STREAK == 2'd1) ? P_DOUBLE :
                                                               P_STRIKE;
                            STREAK[player] <= (CUR_STREAK == 2'd3) ? 2'd3 : CUR_STREAK + 2'd1;
                        end
                        else begin
                            STREAK[player] <= 0;
                            if (CLEARED) begin
                                c_spare <= 1;
                                popup_id <= P_SPARE;
                            end
                            else if (GUTTER_SEEN && pins_down == 0)
                                popup_id <= P_GUTTER;
                            else if (split_flag && FULL_BEFORE)
                                popup_id <= P_SPLIT;
                            else
                                popup_id <= P_PINS;
                        end

                        // what comes next (frame rules)
                        if (ball_no == 0)
                            FIRST_BALL <= pins_down;
                        if (frame != 4'd9)
                            ACTION <= (ball_no == 0 && !STRIKE) ? A_SWEEP : A_FRAME;
                        else case (ball_no)
                            2'd0: ACTION <= CLEARED ? A_FULL : A_SWEEP;
                            2'd1: ACTION <= (FIRST_BALL == 4'd10 || FIRST_BALL + pins_down == 5'd10) ?
                                            (CLEARED ? A_FULL : A_SWEEP) : A_FRAME;
                            default: ACTION <= A_FRAME;
                        endcase
                    end
                end

                T_RESULT: begin
                    // 0.6 s into every result the throw is replayed once at
                    // real speed (a click skips it); middle click / btnU asks
                    // for the half-speed replay
                    if (want_replay) begin
                        replay_start <= 1;
                        replay_fast <= 0;
                        STATE <= T_REPLAY;
                    end
                    else if (!AUTO_DONE && ms >= 12'd600) begin
                        replay_start <= 1;
                        replay_fast <= 1;
                        AUTO_DONE <= 1;
                        STATE <= T_REPLAY;
                    end
                    else if (ms >= 12'd1500 || (skip && ms >= 12'd300)) begin
                        popup_id <= P_NONE;
                        STATE <= T_NEXT;
                    end
                end

                T_REPLAY: begin                            // after the automatic replay ~0.8 s of the result remain
                    if (replay_done) begin
                        ms <= replay_fast ? 12'd700 : 12'd0;
                        STATE <= T_RESULT;
                    end
                end

                T_NEXT: begin
                    AUTO_DONE <= 0;
                    if (ACTION != A_FRAME) begin
                        ball_no <= ball_no + 2'd1;
                        rack_cmd <= (ACTION == A_FULL) ? `RK_FULL : `RK_SWEEP;
                        STATE <= T_RACK;
                    end
                    else begin
                        // frame finished: save, then the next player / frame
                        ball_no <= 0;
                        CARD_MS <= 12'd2000;
                        c_hdr <= 1;
                        save_req <= 1;
                        if (kind[`PK_TWO] && !player) begin
                            player <= 1;
                            hdr_player <= 1;
                            hdr_frame <= frame;
                        end
                        else begin
                            player <= 0;
                            hdr_player <= 0;
                            hdr_frame <= frame + 4'd1;
                            frame <= frame + 4'd1;
                        end

                        if (LAST_FRAME) begin              // game finished
                            hdr_valid <= 0;
                            STATE <= T_OVER;
                        end
                        else begin
                            hdr_valid <= 1;
                            BANNER_MS <= 12'd1000;
                            rack_cmd <= `RK_FULL;
                            STATE <= T_RACK;
                        end
                    end
                end

                T_OVER: begin
                    if (!persist_busy && !SCORE_PENDING) begin
                        game_over <= 1;
                        active <= 0;
                        STATE <= T_IDLE;
                    end
                end

                default: STATE <= T_IDLE;
            endcase
        end
    end
endmodule
