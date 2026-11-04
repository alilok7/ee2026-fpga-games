`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// turn_fsm.v : the bowling sub-FSM (one ball at a time) of the game FSM
//-----------------------------------------------------------------------------
// Owner   : Student D
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
// Spare Challenge: rack the chosen leave, one ball, CLEARED or MISSED, again.
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
    localparam P_STRIKE = 4'd0, P_SPARE = 4'd1, P_GUTTER = 4'd2, P_SPLIT = 4'd3, P_TURKEY = 4'd4,
               P_DOUBLE = 4'd5, P_CLEARED = 4'd6, P_MISSED = 4'd7, P_PINS = 4'd8, P_NONE = 4'd15;
    localparam A_SWEEP = 2'd0, A_FULL = 2'd1, A_FRAME = 2'd2;

    localparam T_IDLE = 4'd0, T_CLEAR = 4'd1, T_RES = 4'd2, T_RACK = 4'd3, T_RACKW = 4'd4,
               T_AIM = 4'd5, T_THROW = 4'd6, T_ROLL = 4'd7, T_PIN = 4'd8, T_SETTLE = 4'd9,
               T_RESULT = 4'd10, T_REPLAY = 4'd11, T_NEXT = 4'd12, T_OVER = 4'd13;
    reg [3:0]  st;
    reg [11:0] ms;                      // timer in ms
    reg [11:0] card_ms, banner_ms;
    reg [4:0]  n0, n1;                  // rolls thrown per player
    reg [3:0]  b1;                      // first ball of this frame (10th-frame rules)
    reg [1:0]  action;
    reg        gutter_seen;
    reg [1:0]  streak0, streak1;
    reg        sc_pend;                 // rescore once persist_ctrl wrote the roll
    reg [2:0]  rs;                      // resume read step
    reg [1:0]  fail_ms;

    assign start_frame = kind[`PK_FULL] ? 4'd0 : 4'd7;
    wire spare_mode = kind[`PK_SPARE];
    wire full_before = (standing_before == 10'h3FF);
    wire cleared = (standing == 10'h000);
    wire [4:0] n_cur = player ? n1 : n0;
    wire [1:0] streak = player ? streak1 : streak0;

    // game_state shown to everyone
    always @(*) begin
        case (st)
            T_AIM:              tstate = `GS_AIM;
            T_THROW:            tstate = `GS_THROW;
            T_ROLL:             tstate = `GS_ROLL;
            T_PIN:              tstate = `GS_PINACTION;
            T_SETTLE:           tstate = `GS_SETTLE;
            T_RESULT, T_NEXT:   tstate = `GS_RESULT;
            T_REPLAY:           tstate = `GS_REPLAY;
            default:            tstate = `GS_SWEEP;  // clearing, resuming, racking
        endcase
    end

    always @(posedge clk) begin
        game_over <= 0; rack_go <= 0; c_roll <= 0; c_hdr <= 0; c_clear <= 0; c_strike <= 0;
        c_spare <= 0; score_start <= 0; save_req <= 0; replay_start <= 0;
        if (rst) begin
            st <= T_IDLE; active <= 0; kind <= 0; ms <= 0; card_ms <= 0; banner_ms <= 0;
            n0 <= 0; n1 <= 0; b1 <= 0; action <= 0; gutter_seen <= 0; streak0 <= 0; streak1 <= 0;
            sc_pend <= 0; rs <= 0; fail_ms <= 0; ra <= 0;
            rack_cmd <= `RK_FULL; rack_mask <= 10'h3FF; roll_p <= 0; roll_idx <= 0; roll_val <= 0;
            hdr_valid <= 0; hdr_player <= 0; hdr_frame <= 0;
            player <= 0; frame <= 0; ball_no <= 0; popup_id <= P_NONE; popup_n <= 0;
            card_auto <= 0; banner <= 0; ghost <= 0; spare_made <= 0; spare_tries <= 0;
        end else begin
            // ---- background timers ----
            if (tick_game && ms != 12'hFFF) ms <= ms + 12'd1;
            if (tick_game && card_ms != 0) card_ms <= card_ms - 12'd1;
            if (tick_game && banner_ms != 0) banner_ms <= banner_ms - 12'd1;
            card_auto <= (card_ms != 0);
            banner    <= (banner_ms != 0);
            if (sc_pend && !persist_busy) begin sc_pend <= 0; score_start <= 1; end

            if (abort && st != T_IDLE) begin
                st <= T_IDLE; active <= 0; popup_id <= P_NONE;
            end else case (st)
                T_IDLE: begin
                    if (go_new) begin
                        kind <= kind_in; active <= 1;
                        player <= 0; ball_no <= 0; n0 <= 0; n1 <= 0; streak0 <= 0; streak1 <= 0;
                        frame <= kind_in[`PK_FULL] ? 4'd0 : 4'd7;
                        spare_made <= 0; spare_tries <= 0; ghost <= 1'b1; popup_id <= P_NONE;
                        rack_mask <= leave_mask;
                        if (!kind_in[`PK_SPARE]) c_clear <= 1;
                        st <= T_CLEAR;
                    end else if (go_resume) begin
                        active <= 1; rs <= 0; ra <= `IM_GKIND; ghost <= 0; popup_id <= P_NONE;
                        ball_no <= 0; streak0 <= 0; streak1 <= 0;
                        st <= T_RES;
                    end
                end
                T_CLEAR: if (!persist_busy && !c_clear) begin
                    sc_pend <= !spare_mode;                // blank scorecard
                    banner_ms <= 12'd1000;
                    rack_cmd <= spare_mode ? `RK_LEAVE : `RK_FULL;
                    st <= T_RACK;
                end
                T_RES: begin                               // read the saved header
                    rs <= rs + 3'd1;
                    // ra was set one clock earlier, so rd belongs to it
                    case (rs)
                        3'd0: begin kind  <= rd[2:0] & 3'b011; ra <= `IM_GPLAYER; end
                        3'd1: begin player <= rd[0]; ra <= `IM_GFRAME; end
                        3'd2: begin frame <= (rd[3:0] > 4'd9) ? 4'd9 : rd[3:0]; ra <= `IM_NROLL0; end
                        3'd3: begin n0 <= rd[4:0]; ra <= `IM_NROLL1; end
                        default: begin
                            n1 <= rd[4:0];
                            sc_pend <= 1; banner_ms <= 12'd1000;
                            rack_cmd <= `RK_FULL;
                            st <= T_RACK;
                        end
                    endcase
                end
                T_RACK: begin rack_go <= 1; st <= T_RACKW; end
                T_RACKW: if (!rack_busy && !rack_go) st <= T_AIM;
                T_AIM: if (grabbing) begin fail_ms <= 0; st <= T_THROW; end
                T_THROW: begin
                    if (throw_valid) begin
                        gutter_seen <= 0; ghost <= 0; ms <= 0; st <= T_ROLL;
                    end else if (swipe_fail) st <= T_AIM;
                    else if (!grabbing && tick_game) begin             // safety: nothing came
                        fail_ms <= fail_ms + 2'd1;
                        if (fail_ms == 2'd3) st <= T_AIM;
                    end
                end
                T_ROLL: begin
                    if (ball_phase == `BP_GUTTER) gutter_seen <= 1;
                    if (ball_y >= `W_DECK_Y || ball_phase == `BP_PIT) st <= T_PIN;
                end
                T_PIN: if (ball_phase == `BP_PIT) st <= T_SETTLE;
                T_SETTLE: if (settle_done) begin
                    ms <= 0; popup_n <= pins_down;
                    st <= T_RESULT;
                    if (spare_mode) begin
                        spare_tries <= spare_tries + 8'd1;
                        if (cleared) begin spare_made <= spare_made + 8'd1; popup_id <= P_CLEARED; end
                        else popup_id <= P_MISSED;
                        action <= A_SWEEP;
                    end else begin
                        // ---- record the roll ----
                        c_roll <= 1; roll_p <= player; roll_idx <= n_cur; roll_val <= pins_down;
                        if (player) n1 <= n1 + 5'd1; else n0 <= n0 + 5'd1;
                        sc_pend <= 1;
                        // ---- popup + lifetime stats ----
                        if (full_before && cleared) begin
                            c_strike <= 1;
                            popup_id <= (streak == 2'd2) ? P_TURKEY : (streak == 2'd1) ? P_DOUBLE : P_STRIKE;
                            if (player) streak1 <= (streak1 == 2'd3) ? 2'd3 : streak1 + 2'd1;
                            else        streak0 <= (streak0 == 2'd3) ? 2'd3 : streak0 + 2'd1;
                        end else begin
                            if (player) streak1 <= 0; else streak0 <= 0;
                            if (cleared)                          begin c_spare <= 1; popup_id <= P_SPARE; end
                            else if (gutter_seen && pins_down == 0) popup_id <= P_GUTTER;
                            else if (split_flag && full_before)   popup_id <= P_SPLIT;
                            else                                  popup_id <= P_PINS;
                        end
                        // ---- what comes next (frame rules) ----
                        if (frame != 4'd9) begin
                            if (ball_no == 0 && !(full_before && cleared)) begin b1 <= pins_down; action <= A_SWEEP; end
                            else action <= A_FRAME;
                        end else begin
                            case (ball_no)
                                2'd0: begin b1 <= pins_down; action <= cleared ? A_FULL : A_SWEEP; end
                                2'd1: action <= (b1 == 4'd10 || {1'b0, b1} + {1'b0, pins_down} == 5'd10) ?
                                                (cleared ? A_FULL : A_SWEEP) : A_FRAME;
                                default: action <= A_FRAME;
                            endcase
                        end
                    end
                end
                T_RESULT: begin
                    if (want_replay) begin replay_start <= 1; st <= T_REPLAY; end
                    else if (ms >= 12'd1500 || (skip && ms >= 12'd300)) begin
                        popup_id <= P_NONE; st <= T_NEXT;
                    end
                end
                T_REPLAY: if (replay_done) begin ms <= 0; st <= T_RESULT; end
                T_NEXT: begin
                    if (spare_mode) begin
                        rack_cmd <= `RK_LEAVE; st <= T_RACK;
                    end else if (action != A_FRAME) begin
                        ball_no <= ball_no + 2'd1;
                        rack_cmd <= (action == A_FULL) ? `RK_FULL : `RK_SWEEP;
                        st <= T_RACK;
                    end else begin
                        // frame finished: next player / frame, save, re-rack
                        ball_no <= 0; card_ms <= 12'd2000;
                        if (kind[`PK_TWO] && !player) begin
                            player <= 1;
                            hdr_player <= 1; hdr_frame <= frame;
                        end else begin
                            player <= 0;
                            hdr_player <= 0; hdr_frame <= frame + 4'd1;
                            frame <= frame + 4'd1;
                        end
                        if ((!kind[`PK_TWO] || player) && frame == 4'd9) begin
                            hdr_valid <= 0; c_hdr <= 1; save_req <= 1;     // game finished
                            st <= T_OVER;
                        end else begin
                            hdr_valid <= 1; c_hdr <= 1; save_req <= 1;
                            banner_ms <= 12'd1000;
                            rack_cmd <= `RK_FULL; st <= T_RACK;
                        end
                    end
                end
                T_OVER: if (!persist_busy && !sc_pend) begin
                    game_over <= 1; active <= 0; st <= T_IDLE;
                end
                default: st <= T_IDLE;
            endcase
        end
    end
endmodule
