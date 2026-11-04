`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// game_top.v : Student C's rhythm-game engine, wired together
//-----------------------------------------------------------------------------
// Owner   : Student C
// Flow FSM: IDLE -> LOAD (header) -> RUN (count-in + song) -> END (1 s
//           grace) -> SCORE (divider) -> DONE. Leaving Play mode at any time
//           clears every sub-module (clr), so a mid-song mode change is safe.
// It also owns the short-lived visual effects (lane flash 120 ms,
//           judgement pop-up 300 ms, Perfect burst 200 ms), converts score and
//           combo to digits once per frame, and turns judgements into sound:
//           a hit plays the NOTE (the player performs the melody), a stray
//           strike plays the lane's note softly, a Miss plays the miss thud.
//=============================================================================
module game_top (
    input  wire                      clk,
    input  wire                      rst,
    input  wire                      tick_1ms,
    input  wire                      tick_frame,
    input  wire [`KL_MODE_W-1:0]     mode,
    input  wire [1:0]                difficulty,
    input  wire [`KL_SETTINGS_W-1:0] settings,
    input  wire                      paused,
    input  wire [12:0]               key_strike,
    input  wire [6:0]                px_x,
    input  wire [5:0]                px_y,
    output wire [15:0]               px_color,
    output wire [`KL_CHART_AW-1:0]   chart_addr,
    input  wire [`KL_CHART_DW-1:0]   chart_data,
    output reg                       ev_valid,
    output reg  [6:0]                ev_note,
    output reg  [1:0]                ev_vel,
    output reg                       sfx_valid,
    output reg  [3:0]                sfx_id,
    output wire [15:0]               led_req,
    output wire [23:0]               seg_glyphs,
    output wire [3:0]                seg_dp,
    output wire [3:0]                seg_blink,
    output wire [9:0]                step_ms,
    output wire                      res_valid,
    output wire [19:0]               res_score,
    output wire [8:0]                res_perfect,
    output wire [8:0]                res_good,
    output wire [8:0]                res_miss,
    output wire [8:0]                res_maxcombo,
    output wire [6:0]                res_acc,
    output wire [2:0]                res_grade
);
    localparam N = 24;
    localparam [2:0] G_IDLE = 3'd0, G_LOAD = 3'd1, G_RUN = 3'd2, G_END = 3'd3,
                     G_SCORE = 3'd4, G_DONE = 3'd5;

    // ---- mode handshake: clear everything outside Play -----------------------
    wire active = (mode == `KL_MODE_PLAY);
    reg  active_d;
    always @(posedge clk) active_d <= active & ~rst;
    wire clr   = rst | ~active;
    wire start = active & ~active_d;

    // ---- difficulty: judgement windows and note speed ------------------------
    reg [7:0] perf_w, good_w;
    always @(*) begin
        case (difficulty)
            `KL_DIFF_EASY: begin perf_w = 8'd60; good_w = 8'd150; end   // x1.5
            `KL_DIFF_HARD: begin perf_w = 8'd30; good_w = 8'd75;  end   // x0.75
            default:       begin perf_w = 8'd40; good_w = 8'd100; end
        endcase
    end
    // ms per pixel = 2^speed_shift: slow 64, normal 32, fast 16, very fast 8;
    // Hard is one step faster.
    wire [2:0] base_shift  = 3'd6 - {1'b0, settings[`KL_SET_SPEED]};
    wire [2:0] speed_shift = (difficulty == `KL_DIFF_HARD && base_shift > 3'd3)
                             ? base_shift - 3'd1 : base_shift;

    // ---- lane strikes: the 8 white keys of key_strike --------------------------
    wire [7:0] lane_strike = {key_strike[12], key_strike[11], key_strike[9], key_strike[7],
                              key_strike[5], key_strike[4], key_strike[2], key_strike[0]};

    // ---- sub-modules -----------------------------------------------------------
    wire        hdr_valid, ld_done, evt_valid, evt_take, empty;
    wire [19:0] lead_ms, total_ms, evt_hit, song_ms;
    wire [2:0]  evt_lane;
    wire [6:0]  evt_note;
    wire [15:0] evt_len;
    wire [11:0] song_step;
    wire        beat, downbeat;
    reg  [2:0]  gstate;

    note_loader u_loader (
        .clk(clk), .clr(clr), .start(start), .chart_addr(chart_addr), .chart_data(chart_data),
        .hdr_valid(hdr_valid), .step_ms(step_ms), .lead_ms(lead_ms), .total_ms(total_ms),
        .evt_valid(evt_valid), .evt_lane(evt_lane), .evt_note(evt_note), .evt_hit(evt_hit),
        .evt_len(evt_len), .evt_take(evt_take), .done(ld_done));

    song_clock u_clock (
        .clk(clk), .clr(clr), .tick_1ms(tick_1ms), .run(gstate == G_RUN || gstate == G_END),
        .paused(paused), .step_ms(step_ms), .song_ms(song_ms), .song_step(song_step),
        .beat(beat), .downbeat(downbeat));

    wire        j_valid;
    wire [1:0]  j_type;
    wire [2:0]  j_lane;
    wire [6:0]  j_note;
    wire [N-1:0] r_vis, r_missed;
    wire [3*N-1:0] r_lane;
    wire [8*N-1:0] r_top, r_bot;
    wire [87:0] lane_dt;

    note_table #(.N(N)) u_table (
        .clk(clk), .clr(clr), .tick_1ms(tick_1ms), .tick_frame(tick_frame), .song_ms(song_ms),
        .paused(paused || gstate != G_RUN), .perf_w(perf_w), .good_w(good_w),
        .speed_shift(speed_shift), .lane_strike(lane_strike),
        .evt_valid(evt_valid), .evt_lane(evt_lane), .evt_note(evt_note), .evt_hit(evt_hit),
        .evt_len(evt_len), .evt_take(evt_take),
        .j_valid(j_valid), .j_type(j_type), .j_lane(j_lane), .j_note(j_note), .empty(empty),
        .r_vis(r_vis), .r_missed(r_missed), .r_lane(r_lane), .r_top(r_top), .r_bot(r_bot),
        .lane_dt(lane_dt));

    wire [19:0] score;
    wire [8:0]  combo, maxcombo, n_perfect, n_good, n_miss;
    wire [2:0]  mult, combo_tens;
    wire        milestone;
    reg         finish;
    scorer u_score (
        .clk(clk), .clr(clr), .j_valid(j_valid), .j_type(j_type), .finish(finish),
        .score(score), .combo(combo), .maxcombo(maxcombo), .n_perfect(n_perfect),
        .n_good(n_good), .n_miss(n_miss), .mult(mult), .combo_tens(combo_tens),
        .milestone(milestone), .res_valid(res_valid), .res_acc(res_acc), .res_grade(res_grade));
    assign res_score    = score;
    assign res_perfect  = n_perfect;
    assign res_good     = n_good;
    assign res_miss     = n_miss;
    assign res_maxcombo = maxcombo;

    // ---- flow FSM ----------------------------------------------------------------
    reg [10:0] end_ms;
    always @(posedge clk) begin
        finish <= 1'b0;
        if (clr) begin
            gstate <= G_IDLE;
            end_ms <= 11'd0;
        end else begin
            case (gstate)
                G_IDLE:  if (start)     gstate <= G_LOAD;
                G_LOAD:  if (hdr_valid) gstate <= G_RUN;
                G_RUN:   if (ld_done && empty && song_ms >= total_ms) begin
                             gstate <= G_END;
                             end_ms <= 11'd0;
                         end
                G_END:   if (tick_1ms && !paused) begin       // 1 s to enjoy the last note
                             end_ms <= end_ms + 11'd1;
                             if (end_ms == 11'd1000) begin
                                 finish <= 1'b1;
                                 gstate <= G_SCORE;
                             end
                         end
                G_SCORE: if (res_valid) gstate <= G_DONE;
                default: ;                                     // G_DONE: wait for mode change
            endcase
        end
    end

    // ---- count-in display: 2 bars = steps 0..31, the song starts at step 32 ----
    reg [2:0] countin;
    always @(*) begin
        countin = 3'd0;
        if (gstate == G_RUN && song_step < 12'd36) begin
            if      (song_step < 12'd16) countin = 3'd5;         // "FLIP LIT SWITCH"
            else if (song_step < 12'd20) countin = 3'd1;         // 3
            else if (song_step < 12'd24) countin = 3'd2;         // 2
            else if (song_step < 12'd28) countin = 3'd3;         // 1
            else                         countin = 3'd4;         // GO!
        end
    end

    // ---- effects timers (ms) -----------------------------------------------------
    reg [6:0] flash_t [0:7];
    reg [8:0] popup_t;
    reg [1:0] popup;
    reg [7:0] burst_t;
    reg [2:0] burst_lane;
    reg [7:0] flash;
    integer k;
    always @(posedge clk) begin
        if (clr) begin
            for (k = 0; k < 8; k = k + 1) flash_t[k] <= 7'd0;
            popup_t <= 9'd0; popup <= 2'd0; burst_t <= 8'd0; burst_lane <= 3'd0;
        end else begin
            if (tick_1ms) begin
                for (k = 0; k < 8; k = k + 1) if (flash_t[k] != 7'd0) flash_t[k] <= flash_t[k] - 7'd1;
                if (popup_t != 9'd0) popup_t <= popup_t - 9'd1; else popup <= 2'd0;
                if (burst_t != 8'd0) burst_t <= burst_t - 8'd1;
            end
            if (j_valid && j_type != 2'd3) begin
                popup   <= j_type + 2'd1;                       // 1 P, 2 G, 3 M
                popup_t <= 9'd300;
                if (j_type != 2'd2) flash_t[j_lane] <= 7'd120;
                if (j_type == 2'd0) begin burst_t <= 8'd200; burst_lane <= j_lane; end
            end
        end
    end
    always @(*) for (k = 0; k < 8; k = k + 1) flash[k] = (flash_t[k] != 7'd0);

    // ---- sound events --------------------------------------------------------------
    always @(posedge clk) begin
        ev_valid <= 1'b0; ev_note <= 7'd0; ev_vel <= `KL_VEL_NORMAL;
        sfx_valid <= 1'b0; sfx_id <= 4'd0;
        if (!clr) begin
            if (j_valid && j_type != 2'd2) begin                // hit or stray: play the note
                ev_valid <= 1'b1;
                ev_note  <= j_note;
                ev_vel   <= (j_type == 2'd3) ? `KL_VEL_SOFT : `KL_VEL_NORMAL;
            end
            if (j_valid && j_type == 2'd2) begin
                sfx_valid <= 1'b1; sfx_id <= `KL_SFX_MISS;
            end else if (milestone) begin
                sfx_valid <= 1'b1; sfx_id <= `KL_SFX_COMBO;
            end else if (beat && (song_step < 12'd32 || settings[`KL_SET_METRO])) begin
                sfx_valid <= 1'b1; sfx_id <= downbeat ? `KL_SFX_CLICK_HI : `KL_SFX_CLICK;
            end
        end
    end

    // ---- digits for the HUD, refreshed every frame ------------------------------
    wire [23:0] score_bcd, combo_bcd6;
    wire        bcd_done_a, bcd_done_b;
    bin2bcd #(.W(20), .D(6)) u_bcd_score (.clk(clk), .rst(clr), .start(tick_frame),
        .bin(score), .bcd(score_bcd), .done(bcd_done_a));
    bin2bcd #(.W(9), .D(3)) u_bcd_combo (.clk(clk), .rst(clr), .start(tick_frame),
        .bin(combo), .bcd(combo_bcd6[11:0]), .done(bcd_done_b));
    assign combo_bcd6[23:12] = 12'd0;

    // ---- progress bar: Bresenham-style accumulator, px = song_ms * 96 / total ------
    reg [6:0]  progress;
    reg [20:0] prog_acc;
    always @(posedge clk) begin
        if (clr || gstate == G_LOAD) begin
            progress <= 7'd0; prog_acc <= 21'd0;
        end else if (gstate == G_RUN && tick_1ms && !paused && progress < 7'd96) begin
            // every ms add 96; each time the sum passes total_ms, one more pixel
            if (prog_acc + 21'd96 >= {1'b0, total_ms}) begin
                prog_acc <= prog_acc + 21'd96 - {1'b0, total_ms};
                progress <= progress + 7'd1;
            end else begin
                prog_acc <= prog_acc + 21'd96;
            end
        end
    end

    // ---- renderer -------------------------------------------------------------------
    play_renderer #(.N(N)) u_render (
        .px_x(px_x), .px_y(px_y), .r_vis(r_vis), .r_missed(r_missed), .r_lane(r_lane),
        .r_top(r_top), .r_bot(r_bot), .flash(flash), .popup(popup),
        .burst_on(burst_t != 8'd0), .burst_lane(burst_lane), .score_bcd(score_bcd),
        .combo_bcd(combo_bcd6[11:0]), .mult(mult), .progress(progress), .countin(countin),
        .color(px_color));

    // ---- LEDs: guides above the lane switches, combo meter on led[7:3] -------------
    wire [7:0] guide;
    led_guides u_leds (
        .clk(clk), .rst(clr), .tick_frame(tick_frame), .enable(settings[`KL_SET_GUIDES]),
        .lane_dt(lane_dt), .perf_w(perf_w), .flash(flash), .blink(song_ms[6]), .leds(guide));
    // lane 0 (C4) sits under led[15], lane 7 (C5) under led[8]
    assign led_req[15:8] = {guide[0], guide[1], guide[2], guide[3],
                            guide[4], guide[5], guide[6], guide[7]};
    assign led_req[7:3]  = {combo_tens >= 3'd1, combo_tens >= 3'd2, combo_tens >= 3'd3,
                            combo_tens >= 3'd4, combo_tens >= 3'd5};
    assign led_req[2:0]  = 3'b000;

    // ---- 7-seg: multiplier digit (with dot) then 3-digit combo ----------------------
    assign seg_glyphs = {3'b000, mult, 2'b00, combo_bcd6[11:8], 2'b00, combo_bcd6[7:4],
                         2'b00, combo_bcd6[3:0]};
    assign seg_dp     = 4'b1000;
    assign seg_blink  = 4'b0000;
endmodule
