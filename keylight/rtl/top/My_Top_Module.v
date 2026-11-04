`timescale 1ns / 1ps
`include "keylight_defs.vh"
//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME:   (sound engine, timebase)
//  STUDENT B NAME:   (input, Free Play, storage, IO mux)
//  STUDENT C NAME:   (rhythm game engine)
//  STUDENT D NAME:   (UI, Learn, mode FSM, pixel_xy, video mux)
//////////////////////////////////////////////////////////////////////////////////
//=============================================================================
// My_Top_Module.v : KeyLight top level - wiring only, no logic of its own
//-----------------------------------------------------------------------------
// Data flow (see docs/INTERFACES.md):
//   switches/buttons -> B input_conditioner -> key_strike / btn events
//   btn events -> D mode_fsm -> mode, song, difficulty, settings -> everyone
//   key_strike -> C game (Play) / B piano (Free) -> note events -> A sound
//   C results -> D results screen
//   video: B / C / D renderers -> D mux_video (+ overlay, brightness) -> OLED
//   LEDs, 7-seg, sound bus: B mux_io picks the owner by mode
//=============================================================================
module My_Top_Module (
    input  wire        clk,
    input  wire [15:0] sw,
    input  wire        btnU, btnD, btnL, btnR, btnC,
    output wire [15:0] led,
    output wire [6:0]  seg,
    output wire        dp,
    output wire [3:0]  an,
    output wire [7:0]  JC,           // Pmod OLED
    output wire [3:0]  JA            // Pmod AMP2 (top row of JA)
);
    // ---------------- clocks, ticks, reset -----------------------------------
    wire rst, por_rst, soft_reset_req;
    wire tick_1ms, tick_sample, tick_frame, clk6p25m;
    wire oled_sending;

    reset_gen u_reset (.clk(clk), .soft_req(soft_reset_req), .rst(rst), .por_rst(por_rst));

    timebase u_time (
        .clk(clk), .rst(rst), .oled_sending(oled_sending),
        .tick_1ms(tick_1ms), .tick_sample(tick_sample), .tick_frame(tick_frame),
        .clk6p25m(clk6p25m));

    // ---------------- B: input -----------------------------------------------
    wire [12:0] key_strike, key_level;
    wire [2:0]  ctl_level;                 // {octave, mute, pause}
    wire [4:0]  btn_level, btn_press, btn_long, btn_repeat;

    input_conditioner u_input (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .sw(sw),
        .btn({btnU, btnD, btnL, btnR, btnC}),
        .key_strike(key_strike), .key_level(key_level), .ctl_level(ctl_level),
        .btn_level(btn_level), .btn_press(btn_press), .btn_long(btn_long),
        .btn_repeat(btn_repeat), .soft_reset_req(soft_reset_req));

    wire octave_up = ctl_level[2];
    wire muted     = ctl_level[1];
    wire paused    = ctl_level[0];

    // ---------------- D: mode FSM --------------------------------------------
    wire [`KL_MODE_W-1:0]     mode;
    wire [2:0]                menu_idx, song_id;
    wire [1:0]                difficulty;
    wire                      learn_sel;
    wire [`KL_SETTINGS_W-1:0] settings;
    wire                      sfx_v_d;
    wire [3:0]                sfx_i_d;
    wire                      rec_exists;
    wire                      res_valid;

    mode_fsm u_mode (
        .clk(clk), .rst(rst), .btn_press(btn_press), .btn_long(btn_long),
        .btn_repeat(btn_repeat), .rec_exists(rec_exists), .res_valid(res_valid),
        .mode(mode), .menu_idx(menu_idx), .song_id(song_id), .difficulty(difficulty),
        .learn_sel(learn_sel), .settings(settings), .sfx_valid(sfx_v_d), .sfx_id(sfx_i_d));

    // ---------------- video pipeline: OLED + pixel coordinates ----------------
    wire [12:0] pixel_index;
    wire [15:0] oled_data;
    wire [6:0]  px_x;
    wire [5:0]  px_y;
    wire        frame_begin_unused, sample_pixel_unused;

    Oled_Display u_oled (
        .clk(clk6p25m), .reset(por_rst), .frame_begin(frame_begin_unused),
        .sending_pixels(oled_sending), .sample_pixel(sample_pixel_unused),
        .pixel_index(pixel_index), .pixel_data(oled_data),
        .cs(JC[0]), .sdin(JC[1]), .sclk(JC[3]), .d_cn(JC[4]), .resn(JC[5]),
        .vccen(JC[6]), .pmoden(JC[7]));
    assign JC[2] = 1'b0;                   // JC3 is not used by the OLED

    pixel_xy u_xy (.clk(clk), .pixel_index(pixel_index), .px_x(px_x), .px_y(px_y));

    // ---------------- C: rhythm game -------------------------------------------
    wire [`KL_CHART_AW-1:0] game_addr, my_addr;
    wire [`KL_CHART_DW-1:0] chart_data;
    wire [15:0] px_play, led_c;
    wire [23:0] seg_g_c;
    wire [3:0]  seg_dp_c, seg_bl_c, sfx_i_c;
    wire        ev_v_c, sfx_v_c;
    wire [6:0]  ev_n_c;
    wire [1:0]  ev_l_c;
    wire [9:0]  step_ms;
    wire [19:0] res_score;
    wire [8:0]  res_perfect, res_good, res_miss, res_maxcombo;
    wire [6:0]  res_acc;
    wire [2:0]  res_grade;

    chart_reader u_chart (
        .clk(clk), .song_id(song_id), .sel_learn(mode == `KL_MODE_LEARN),
        .game_addr(game_addr), .learn_addr(9'd0), .chart_data(chart_data),
        .my_addr(my_addr), .my_data(24'd0));      // MY SONG RAM: Phase 3 (B)

    game_top u_game (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .tick_frame(tick_frame), .mode(mode),
        .difficulty(difficulty), .settings(settings), .paused(paused), .key_strike(key_strike),
        .px_x(px_x), .px_y(px_y), .px_color(px_play),
        .chart_addr(game_addr), .chart_data(chart_data),
        .ev_valid(ev_v_c), .ev_note(ev_n_c), .ev_vel(ev_l_c),
        .sfx_valid(sfx_v_c), .sfx_id(sfx_i_c),
        .led_req(led_c), .seg_glyphs(seg_g_c), .seg_dp(seg_dp_c), .seg_blink(seg_bl_c),
        .step_ms(step_ms), .res_valid(res_valid), .res_score(res_score),
        .res_perfect(res_perfect), .res_good(res_good), .res_miss(res_miss),
        .res_maxcombo(res_maxcombo), .res_acc(res_acc), .res_grade(res_grade));

    // ---------------- B: Free Play ---------------------------------------------
    wire [15:0] px_free, led_b;
    wire [23:0] seg_g_b;
    wire [3:0]  seg_dp_b, seg_bl_b;
    wire        ev_v_b;
    wire [6:0]  ev_n_b;
    wire [1:0]  ev_l_b;

    free_play u_free (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .mode(mode), .key_strike(key_strike),
        .octave_up(octave_up), .px_x(px_x), .px_y(px_y), .px_color(px_free),
        .ev_valid(ev_v_b), .ev_note(ev_n_b), .ev_vel(ev_l_b), .led_req(led_b),
        .seg_glyphs(seg_g_b), .seg_dp(seg_dp_b), .seg_blink(seg_bl_b),
        .rec_exists(rec_exists));

    // ---------------- D: results, screens, status --------------------------------
    wire [19:0] r_score;
    wire [2:0]  r_grade;
    wire [23:0] r_score_bcd;
    wire [11:0] r_perf_bcd, r_good_bcd, r_miss_bcd, r_max_bcd, r_acc_bcd;

    results_latch u_res (
        .clk(clk), .rst(rst), .res_valid(res_valid), .res_score(res_score),
        .res_perfect(res_perfect), .res_good(res_good), .res_miss(res_miss),
        .res_maxcombo(res_maxcombo), .res_acc(res_acc), .res_grade(res_grade),
        .score(r_score), .grade(r_grade), .score_bcd(r_score_bcd), .perf_bcd(r_perf_bcd),
        .good_bcd(r_good_bcd), .miss_bcd(r_miss_bcd), .max_bcd(r_max_bcd), .acc_bcd(r_acc_bcd));

    wire [15:0] px_ui, ov_color, led_d;
    wire        ov_en;
    ui_renderer u_ui (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .px_x(px_x), .px_y(px_y),
        .mode(mode), .menu_idx(menu_idx), .song_id(song_id), .difficulty(difficulty),
        .rec_exists(rec_exists), .paused(paused),
        .best_bcd(24'd0), .best_initials(15'd0),          // high scores: Phase 4 (B)
        .res_score_bcd(r_score_bcd), .res_perf_bcd(r_perf_bcd), .res_good_bcd(r_good_bcd),
        .res_miss_bcd(r_miss_bcd), .res_max_bcd(r_max_bcd), .res_acc_bcd(r_acc_bcd),
        .res_grade(r_grade), .ui_color(px_ui), .ov_color(ov_color), .ov_en(ov_en));

    wire [23:0] seg_g_d;
    wire [3:0]  seg_dp_d, seg_bl_d;
    ui_status u_status (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .mode(mode), .menu_idx(menu_idx),
        .difficulty(difficulty), .res_grade(r_grade), .res_acc_bcd(r_acc_bcd),
        .seg_glyphs(seg_g_d), .seg_dp(seg_dp_d), .seg_blink(seg_bl_d), .led_req(led_d));

    mux_video u_vmux (
        .clk(clk), .mode(mode), .px_x(px_x), .px_y(px_y), .px_play(px_play), .px_free(px_free),
        .px_ui(px_ui), .ov_color(ov_color), .ov_en(ov_en), .settings(settings),
        .oled_data(oled_data));

    // ---------------- B: IO mux ---------------------------------------------------
    wire [23:0] seg_glyphs;
    wire [3:0]  seg_dp, seg_blink;
    wire        ev_valid, sfx_valid;
    wire [6:0]  ev_note;
    wire [1:0]  ev_vel;
    wire [3:0]  sfx_id;

    mux_io u_iomux (
        .mode(mode), .muted(muted), .paused(paused), .recording(1'b0),
        .led_c(led_c), .led_b(led_b), .led_d(led_d),
        .seg_g_c(seg_g_c), .seg_g_b(seg_g_b), .seg_g_d(seg_g_d),
        .seg_dp_c(seg_dp_c), .seg_dp_b(seg_dp_b), .seg_dp_d(seg_dp_d),
        .seg_bl_c(seg_bl_c), .seg_bl_b(seg_bl_b), .seg_bl_d(seg_bl_d),
        .ev_v_c(ev_v_c), .ev_v_b(ev_v_b), .ev_v_d(1'b0),
        .ev_n_c(ev_n_c), .ev_n_b(ev_n_b), .ev_n_d(7'd0),
        .ev_l_c(ev_l_c), .ev_l_b(ev_l_b), .ev_l_d(2'd0),
        .sfx_v_c(sfx_v_c), .sfx_v_d(sfx_v_d), .sfx_i_c(sfx_i_c), .sfx_i_d(sfx_i_d),
        .led(led), .seg_glyphs(seg_glyphs), .seg_dp(seg_dp), .seg_blink(seg_blink),
        .ev_valid(ev_valid), .ev_note(ev_note), .ev_vel(ev_vel),
        .sfx_valid(sfx_valid), .sfx_id(sfx_id));

    seg7_driver u_seg (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .glyphs(seg_glyphs), .dps(seg_dp),
        .blink(seg_blink), .blink_phase(1'b0), .seg(seg), .dp(dp), .an(an));

    // ---------------- A: sound ------------------------------------------------------
    wire [7:0] sample, scope_sample;
    wire [3:0] voice_active;
    sound_engine u_sound (
        .clk(clk), .rst(rst), .tick_sample(tick_sample), .tick_1ms(tick_1ms),
        .ev_valid(ev_valid), .ev_note(ev_note), .ev_vel(ev_vel),
        .sfx_valid(sfx_valid), .sfx_id(sfx_id), .settings(settings), .mute(muted),
        .sample(sample), .scope_sample(scope_sample), .voice_active(voice_active));

    audio_out u_audio (.clk(clk), .rst(rst), .sample(sample), .ja(JA));
endmodule
