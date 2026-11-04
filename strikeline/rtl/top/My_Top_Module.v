`timescale 1ns / 1ps
`include "strike_defs.vh"
//////////////////////////////////////////////////////////////////////////////////
//  FILL IN THE FOLLOWING INFORMATION:
//  STUDENT A NAME:   (mouse input, gesture recognition)
//  STUDENT B NAME:   (ball physics, lane, camera)
//  STUDENT C NAME:   (pin physics, pin-setter, split / settle)
//  STUDENT D NAME:   (game FSM, scoring, UI, flash save)
//////////////////////////////////////////////////////////////////////////////////
//=============================================================================
// My_Top_Module.v : StrikeLine top level - wiring only, no logic of its own
//-----------------------------------------------------------------------------
// The physics chain (docs/INTERFACES.md):
//   mouse -> A gesture --throw--> B ball --impulses--> C pins --result--> D game
//   B reads C's pin positions, C watches B's ball phase, D commands C's
//   pin-setter, D's settings reach A (sensitivity, hand), B (oil, ball weight)
//   and the renderers (theme, brightness).
// Video: B lane < C pins < B ball < A trail/meters < D menus/HUD/scorecard
//        < A cursor  ->  D compositor (+ text engine)  ->  OLED on JC
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
    inout  wire        PS2Clk,       // USB HID host (mouse) on the Basys3
    inout  wire        PS2Data,
    output wire        QspiCSn,      // configuration flash (saves)
    inout  wire [3:0]  QspiDB
);
    // =================== clocks, ticks, reset, inputs =========================
    wire rst, por_rst, soft_reset_req;
    wire [15:0] sw_level;
    wire [4:0]  btn_level, btn_press, btn_long, btn_repeat;
    wire tick_1ms, tick_game, tick_sample, tick_phys, tick_frame, clk6p25m, oled_sending;

    reset_gen u_reset (.clk(clk), .soft_req(soft_reset_req), .rst(rst), .por_rst(por_rst));

    input_conditioner u_input (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .sw(sw), .btn({btnU, btnD, btnL, btnR, btnC}),
        .sw_level(sw_level), .btn_level(btn_level), .btn_press(btn_press), .btn_long(btn_long),
        .btn_repeat(btn_repeat), .soft_reset_req(soft_reset_req));

    wire paused  = sw_level[0];
    wire minimap = sw_level[1];
    wire debug   = sw_level[2];
    wire slowmo  = sw_level[3];
    wire lefty_sw = sw_level[15];

    // In simulation (tb_top) time runs ~65x faster; the RATIOS between the
    // ticks (1 ms : 5 ms sample : ~1 ms physics) stay as on the board.
`ifdef SIM
    timebase #(.MS_DIV(1000), .PHYS_DIV(1500), .SMP_DIV(5000)) u_time (
`else
    timebase u_time (
`endif
        .clk(clk), .rst(rst), .paused(paused), .slowmo(slowmo), .oled_sending(oled_sending),
        .tick_1ms(tick_1ms), .tick_game(tick_game), .tick_sample(tick_sample), .tick_phys(tick_phys),
        .tick_frame(tick_frame), .clk6p25m(clk6p25m));

    reg [7:0] frame_cnt;
    always @(posedge clk) if (rst) frame_cnt <= 0; else if (tick_frame) frame_cnt <= frame_cnt + 8'd1;

    // =================== OLED + pixel coordinates ============================
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
    assign JC[2] = 1'b0;
    pixel_xy u_xy (.clk(clk), .pixel_index(pixel_index), .px_x(px_x), .px_y(px_y));

    // =================== D: game FSM (owner of game_state and settings) ======
    wire [`GS_W-1:0]  game_state, tstate;
    wire [`SET_W-1:0] settings, settings_raw;
    wire [`PK_W-1:0]  t_kind, kind_out;

    // =================== A: mouse + gesture ===================================
    wire [11:0] m_xpos, m_ypos, m_value;
    wire [3:0]  m_zpos;
    wire        m_left, m_middle, m_right, m_new_event, m_setx, m_sety, m_setmax_x, m_setmax_y;
    MouseCtl u_mousectl (
        .clk(clk), .rst(rst), .xpos(m_xpos), .ypos(m_ypos), .zpos(m_zpos), .left(m_left),
        .middle(m_middle), .right(m_right), .new_event(m_new_event), .value(m_value),
        .setx(m_setx), .sety(m_sety), .setmax_x(m_setmax_x), .setmax_y(m_setmax_y),
        .ps2_clk(PS2Clk), .ps2_data(PS2Data));

    wire [6:0]  cursor_x;
    wire [5:0]  cursor_y;
    wire        delta_valid, l_level, r_level, mm_level, l_press, l_release, r_press, m_press;
    wire signed [11:0] delta_x, delta_y;
    wire signed [3:0]  wheel;
    mouse_setup u_mouse (
        .clk(clk), .rst(rst), .m_xpos(m_xpos), .m_ypos(m_ypos), .m_zpos(m_zpos), .m_left(m_left),
        .m_middle(m_middle), .m_right(m_right), .m_new_event(m_new_event), .m_value(m_value),
        .m_setx(m_setx), .m_sety(m_sety), .m_setmax_x(m_setmax_x), .m_setmax_y(m_setmax_y),
        .sens(settings[`SET_SENS_HI:`SET_SENS_LO]), .cursor_x(cursor_x), .cursor_y(cursor_y),
        .delta_valid(delta_valid), .delta_x(delta_x), .delta_y(delta_y), .wheel(wheel),
        .l_level(l_level), .r_level(r_level), .m_level(mm_level), .l_press(l_press),
        .l_release(l_release), .r_press(r_press), .m_press(m_press));

    wire [5:0]  ring_addr, feat_addr, plot_addr, wp;
    wire [63:0] ring_data;
    wire [6:0]  n_samples;
    wire grabbing, swipe_done, swipe_cancel, too_short, feat_busy, plot_busy;
    wire [15:0] stance_x;
    wire [2:0]  live_power;
    wire [415:0] trail_bus;
    wire [31:0] trail_valid;
    // features and plotting never overlap (the plot starts with 4096 clocks
    // of clearing), so the read-port select can be a register (timing)
    reg plot_sel;
    always @(posedge clk) plot_sel <= plot_busy;
    assign ring_addr = plot_sel ? plot_addr : feat_addr;

    swipe_capture u_swipe (
        .clk(clk), .rst(rst), .tick_sample(tick_sample), .tick_1ms(tick_1ms), .game_state(game_state),
        .busy(feat_busy | plot_busy), .delta_valid(delta_valid), .delta_x(delta_x), .delta_y(delta_y),
        .l_press(l_press), .l_release(l_release), .r_press(r_press), .cursor_x(cursor_x),
        .cursor_y(cursor_y), .rd_addr(ring_addr), .rd_data(ring_data), .wp(wp), .n_samples(n_samples),
        .grabbing(grabbing), .swipe_done(swipe_done), .swipe_cancel(swipe_cancel), .too_short(too_short),
        .stance_x(stance_x), .live_power(live_power), .trail_bus(trail_bus), .trail_valid(trail_valid));

    wire throw_valid, reject;
    wire signed [15:0] throw_vy, throw_vx;
    wire signed [3:0]  throw_spin;
    wire [15:0] throw_x0;
    wire [7:0]  throw_mph10;
    wire [1:0]  reject_msg;
    wire [2:0]  aim_level;
    wire        aim_right;
    gesture_features u_feat (
        .clk(clk), .rst(rst), .start(swipe_done), .wp(wp), .n_samples(n_samples), .stance_x(stance_x),
        .rd_addr(feat_addr), .rd_data(ring_data), .busy(feat_busy), .throw_valid(throw_valid),
        .throw_vy(throw_vy), .throw_vx(throw_vx), .throw_spin(throw_spin), .throw_x0(throw_x0),
        .throw_mph10(throw_mph10), .reject(reject), .reject_msg(reject_msg), .aim_level(aim_level),
        .aim_right(aim_right));

    wire in_lab = (game_state == `GS_PRACTICE_SWIPE);
    wire [11:0] lab_addr;
    wire [1:0]  lab_px;
    swipe_lab_plot u_plot (
        .clk(clk), .rst(rst), .start(in_lab && (throw_valid || reject)), .wp(wp), .n_samples(n_samples),
        .rd_addr(plot_addr), .rd_data(ring_data), .busy(plot_busy), .px_addr(lab_addr), .px_data(lab_px));

    // =================== B: ball, camera ======================================
    wire [3:0]  pin_rd_idx;
    wire [15:0] pin_rd_x, pin_rd_y;
    wire signed [15:0] pin_rd_vx, pin_rd_vy;
    wire        pin_rd_solid, impulse_valid, scan_done, contact_pulse;
    wire [3:0]  impulse_pin;
    wire signed [15:0] impulse_vx, impulse_vy, ball_vx, ball_vy;
    wire [15:0] ball_x, ball_y, ball_angle, contact_px, contact_py;
    wire [`BP_W-1:0] ball_phase;
    wire signed [3:0] ball_spin;
    ball_physics u_ball (
        .clk(clk), .rst(rst), .tick_phys(tick_phys), .game_state(game_state), .settings(settings),
        .stance_x(stance_x), .throw_valid(throw_valid), .throw_vy(throw_vy), .throw_vx(throw_vx),
        .throw_spin(throw_spin), .throw_x0(throw_x0), .pin_rd_idx(pin_rd_idx), .pin_rd_x(pin_rd_x),
        .pin_rd_y(pin_rd_y), .pin_rd_vx(pin_rd_vx), .pin_rd_vy(pin_rd_vy), .pin_rd_solid(pin_rd_solid),
        .impulse_valid(impulse_valid), .impulse_pin(impulse_pin), .impulse_vx(impulse_vx),
        .impulse_vy(impulse_vy), .scan_done(scan_done), .ball_x(ball_x), .ball_y(ball_y),
        .ball_vx(ball_vx), .ball_vy(ball_vy), .ball_phase(ball_phase), .ball_spin(ball_spin),
        .ball_angle(ball_angle), .contact_pulse(contact_pulse), .contact_px(contact_px),
        .contact_py(contact_py));

    wire signed [10:0] cam_y;
    camera u_cam (.clk(clk), .rst(rst), .tick_frame(tick_frame), .paused(paused), .game_state(game_state),
                  .ball_y(ball_y), .ball_vy(ball_vy), .cam_y(cam_y));

    wire throw_go = throw_valid && (game_state == `GS_THROW);
    wire [5:0] trace_row;
    wire [3:0] trace_data;
    ball_trace u_trace (.clk(clk), .rst(rst), .tick_frame(tick_frame), .clear(throw_go),
                        .ball_phase(ball_phase), .ball_x(ball_x), .ball_y(ball_y),
                        .rd_row(trace_row), .rd_data(trace_data));

    // =================== C: pins ===============================================
    wire        rack_go, rack_busy, force_settle, settle_done, split_flag;
    wire [1:0]  rack_cmd;
    wire [9:0]  rack_mask, standing, pin_busy, rake_y, standing_before;
    wire [239:0] pin_vis;
    wire [3:0]  pins_down;
    pin_physics u_pins (
        .clk(clk), .rst(rst), .tick_phys(tick_phys), .scan_done(scan_done),
        .impulse_valid(impulse_valid), .impulse_pin(impulse_pin), .impulse_vx(impulse_vx),
        .impulse_vy(impulse_vy), .rack_go(rack_go), .rack_cmd(rack_cmd), .rack_mask(rack_mask),
        .force_settle(force_settle), .pin_rd_idx(pin_rd_idx), .pin_rd_x(pin_rd_x), .pin_rd_y(pin_rd_y),
        .pin_rd_vx(pin_rd_vx), .pin_rd_vy(pin_rd_vy), .pin_rd_solid(pin_rd_solid), .pin_vis(pin_vis),
        .standing(standing), .busy(pin_busy), .rack_busy(rack_busy), .rake_y(rake_y));

    pin_settle u_settle (
        .clk(clk), .rst(rst), .tick_phys(tick_phys), .throw_go(throw_go), .ball_phase(ball_phase),
        .ball_y(ball_y), .standing(standing), .busy(pin_busy), .force_settle(force_settle),
        .settle_done(settle_done), .pins_down_this_ball(pins_down), .split_flag(split_flag),
        .standing_before(standing_before));

    // =================== D: save image, persistence, flash =====================
    wire [6:0] ra_flash, ra_pers, ra_score, ra_game, ra_mlo, ra_mhi, ra_turn;
    wire [7:0] rd_flash, rd_pers, rd_score, rd_game, rd_mlo, rd_mhi, rd_turn;
    wire       we_flash, we_pers;
    wire [6:0] wa_flash, wa_pers;
    wire [7:0] wd_flash, wd_pers;
    save_image u_img (
        .clk(clk), .we_flash(we_flash), .wa_flash(wa_flash), .wd_flash(wd_flash),
        .we_game(we_pers), .wa_game(wa_pers), .wd_game(wd_pers),
        .ra0(ra_flash), .ra1(ra_pers), .ra2(ra_score), .ra3(ra_game), .ra4(ra_mlo), .ra5(ra_mhi), .ra6(ra_turn),
        .rd0(rd_flash), .rd1(rd_pers), .rd2(rd_score), .rd3(rd_game), .rd4(rd_mlo), .rd5(rd_mhi), .rd6(rd_turn));

    // commands into persist_ctrl
    wire c_roll, roll_p, c_hdr, hdr_valid, hdr_player, c_clear, c_strike, c_spare;
    wire [4:0] roll_idx; wire [3:0] roll_val, hdr_frame;
    wire c_settings, c_insert, ins_quick, c_gameend, gend_full, c_def_game, c_def_flash;
    wire [8:0] ins_score, gend_score; wire [14:0] ins_name;
    wire persist_busy;
    persist_ctrl u_persist (
        .clk(clk), .rst(rst), .c_roll(c_roll), .roll_p(roll_p), .roll_idx(roll_idx), .roll_val(roll_val),
        .c_hdr(c_hdr), .hdr_valid(hdr_valid), .hdr_kind(t_kind), .hdr_player(hdr_player),
        .hdr_frame(hdr_frame), .c_clear(c_clear), .c_strike(c_strike), .c_spare(c_spare),
        .c_gameend(c_gameend), .c_insert(c_insert), .ins_quick(ins_quick), .ins_score(ins_score),
        .ins_name(ins_name), .c_settings(c_settings), .set_value(settings_raw),
        .c_defaults(c_def_game | c_def_flash), .gend_full(gend_full), .gend_score(gend_score),
        .we(we_pers), .wa(wa_pers), .wd(wd_pers), .ra(ra_pers), .rd(rd_pers), .busy(persist_busy));

    wire save_req_t, save_req_g, load_done, flash_ok, saving, save_error, spi_sck, spi_mosi;
    flash_ctrl u_flash (
        .clk(clk), .rst(rst), .save_req(save_req_t | save_req_g), .persist_busy(persist_busy),
        .ra(ra_flash), .rd(rd_flash), .we(we_flash), .wa(wa_flash), .wd(wd_flash),
        .c_defaults(c_def_flash), .load_done(load_done), .flash_ok(flash_ok), .saving(saving),
        .save_error(save_error), .cs_n(QspiCSn), .sck(spi_sck), .mosi(spi_mosi), .miso(QspiDB[1]));
    assign QspiDB[0] = spi_mosi;
    assign QspiDB[1] = 1'bz;         // MISO from the flash
    assign QspiDB[2] = 1'b1;         // WP#  high: not write protected by the pin
    assign QspiDB[3] = 1'b1;         // HOLD# high
    // The flash clock pin (CCLK) is only reachable through STARTUPE2 after
    // configuration. The simulation model connects spi_sck directly instead.
`ifndef SIM
    STARTUPE2 #(.PROG_USR("FALSE"), .SIM_CCLK_FREQ(0.0)) u_startup (
        .CFGCLK(), .CFGMCLK(), .EOS(), .PREQ(), .CLK(1'b0), .GSR(1'b0), .GTS(1'b0),
        .KEYCLEARB(1'b1), .PACK(1'b0), .USRCCLKO(spi_sck), .USRCCLKTS(1'b0),
        .USRDONEO(1'b1), .USRDONETS(1'b1));
`endif

    // =================== D: scoring =============================================
    wire [3:0]  start_frame;
    wire        score_start, score_done;
    wire [4:0]  card_addr; wire [27:0] card_word; wire [9:0] ok0, ok1; wire [8:0] game0, game1;
    score_engine u_score (
        .clk(clk), .rst(rst), .start(score_start), .start_frame(start_frame), .ra(ra_score), .rd(rd_score),
        .card_addr(card_addr), .card_word(card_word), .ok0(ok0), .ok1(ok1), .game0(game0), .game1(game1),
        .done(score_done));

    // =================== D: game FSM + turn FSM ================================
    wire go_new, go_resume, abort, t_active, t_game_over, want_replay, skip, card_show;
    wire [9:0]  leave_mask;
    wire [2:0]  hover, leave_idx;
    wire        chip_two, has_save, tab_quick, name_player;
    wire [1:0]  erase_step, name_pos, newhi;
    wire [14:0] name;
    game_fsm u_game (
        .clk(clk), .rst(rst), .tick_game(tick_game), .load_done(load_done), .cursor_x(cursor_x),
        .cursor_y(cursor_y), .mouse_move(delta_valid), .l_press(l_press), .r_press(r_press),
        .m_press(m_press), .wheel(wheel), .btn_press(btn_press), .btn_repeat(btn_repeat),
        .btn_long(btn_long), .sw_lefty(lefty_sw), .tstate(tstate), .t_active(t_active),
        .t_game_over(t_game_over), .t_kind(t_kind), .go_new(go_new), .go_resume(go_resume),
        .kind_out(kind_out), .leave_mask(leave_mask), .abort(abort), .game0(game0), .game1(game1),
        .ra(ra_game), .rd(rd_game), .persist_busy(persist_busy), .c_settings(c_settings),
        .c_insert(c_insert), .ins_quick(ins_quick), .ins_score(ins_score), .ins_name(ins_name),
        .c_gameend(c_gameend), .gend_full(gend_full), .gend_score(gend_score), .c_defaults(c_def_game),
        .save_req(save_req_g), .game_state(game_state), .settings(settings), .settings_raw(settings_raw),
        .hover(hover), .chip_two(chip_two), .has_save(has_save), .leave_idx(leave_idx),
        .tab_quick(tab_quick), .erase_step(erase_step), .name(name), .name_pos(name_pos),
        .name_player(name_player), .newhi(newhi), .card_show(card_show), .want_replay(want_replay),
        .skip(skip));

    wire player, card_auto, banner, ghost, replay_start, replay_done;
    wire [3:0] frame, popup_id, popup_n;
    wire [1:0] ball_no;
    wire [7:0] spare_made, spare_tries;
    turn_fsm u_turn (
        .clk(clk), .rst(rst), .tick_game(tick_game), .go_new(go_new), .go_resume(go_resume),
        .kind_in(kind_out), .leave_mask(leave_mask), .abort(abort), .grabbing(grabbing),
        .throw_valid(throw_valid), .swipe_fail(reject | swipe_cancel | too_short),
        .ball_phase(ball_phase), .ball_y(ball_y), .settle_done(settle_done), .pins_down(pins_down),
        .split_flag(split_flag), .standing(standing), .standing_before(standing_before),
        .rack_busy(rack_busy), .skip(skip), .want_replay(want_replay), .replay_done(replay_done),
        .ra(ra_turn), .rd(rd_turn), .persist_busy(persist_busy), .tstate(tstate), .kind(t_kind),
        .active(t_active), .game_over(t_game_over), .rack_go(rack_go), .rack_cmd(rack_cmd),
        .rack_mask(rack_mask), .c_roll(c_roll), .roll_p(roll_p), .roll_idx(roll_idx), .roll_val(roll_val),
        .c_hdr(c_hdr), .hdr_valid(hdr_valid), .hdr_player(hdr_player), .hdr_frame(hdr_frame),
        .c_clear(c_clear), .c_strike(c_strike), .c_spare(c_spare), .score_start(score_start),
        .save_req(save_req_t), .replay_start(replay_start), .player(player), .frame(frame),
        .ball_no(ball_no), .start_frame(start_frame), .popup_id(popup_id), .popup_n(popup_n),
        .card_auto(card_auto), .banner(banner), .ghost(ghost), .spare_made(spare_made),
        .spare_tries(spare_tries));

    // =================== renderers ============================================
    wire in_play = (game_state >= `GS_AIM && game_state <= `GS_SWEEP) || game_state == `GS_REPLAY;
    wire ball_visible_live = in_play && (ball_phase != `BP_PIT);

    // ---- D: instant replay (middle click / btnD in RESULT). While it plays,
    //      the renderers draw the recorded ball, camera and pins.
    wire        rp_active, rp_vis;
    wire [15:0] rp_bx, rp_by;
    wire [5:0]  rp_ang;
    wire signed [10:0] rp_cam;
    wire [239:0] rp_pins;
    replay_buffer u_replay (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .game_state(game_state), .start(replay_start),
        .ball_vis_in(ball_visible_live), .ball_x_in(ball_x), .ball_y_in(ball_y), .angle_in(ball_angle[15:10]),
        .cam_in(cam_y), .pins_in(pin_vis), .active(rp_active), .done(replay_done), .ball_vis(rp_vis),
        .ball_x(rp_bx), .ball_y(rp_by), .angle(rp_ang), .cam(rp_cam), .pins(rp_pins));
    wire               ball_visible = rp_active ? rp_vis  : ball_visible_live;
    wire [15:0]        v_ball_x     = rp_active ? rp_bx   : ball_x;
    wire [15:0]        v_ball_y     = rp_active ? rp_by   : ball_y;
    wire [5:0]         v_angle      = rp_active ? rp_ang  : ball_angle[15:10];
    wire signed [10:0] v_cam        = rp_active ? rp_cam  : cam_y;
    wire [239:0]       v_pins       = rp_active ? rp_pins : pin_vis;

    wire [15:0] lane_c, ball_c, pin_c, a_c, cur_c, menu_c, hud_c, sc_c;
    wire        lane_en, ball_en, pin_en, a_en, cur_en, menu_en, hud_en, sc_en;
    wire [`TX_W-1:0] a_t, menu_t, hud_t, sc_t;
    wire [5:0]  led_a;

    lane_render u_lane (
        .px_x(px_x), .px_y(px_y), .cam_y(v_cam), .settings(settings), .minimap_on(minimap && in_play),
        .ball_x(v_ball_x), .ball_y(v_ball_y), .ball_visible(ball_visible),
        .trace_row(trace_row), .trace_data(trace_data),
        .pins_standing(standing), .blink(frame_cnt[3]), .color(lane_c), .en(lane_en));

    ball_render u_ballr (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .px_x(px_x), .px_y(px_y), .cam_y(v_cam),
        .ball_x(v_ball_x), .ball_y(v_ball_y), .ball_vx(ball_vx), .ball_vy(ball_vy), .visible(ball_visible),
        .ball_lb(settings[`SET_LB_HI:`SET_LB_LO]), .angle(v_angle), .debug(debug && !rp_active),
        .contact_pulse(contact_pulse), .contact_px(contact_px), .contact_py(contact_py),
        .color(ball_c), .en(ball_en));

    pin_render u_pinr (
        .px_x(px_x), .px_y(px_y), .cam_y(v_cam), .pin_vis(v_pins), .rake_y(rake_y),
        .wobble_phase(frame_cnt[2]), .debug(debug), .color(pin_c), .en(pin_en));

    gesture_render u_ar (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .px_x(px_x), .px_y(px_y), .game_state(game_state),
        .lefty(settings[`SET_LEFTY]), .cursor_x(cursor_x), .cursor_y(cursor_y), .grabbing(grabbing),
        .trail_bus(trail_bus), .trail_valid(trail_valid), .stance_x(stance_x), .cam_y(cam_y),
        .live_power(live_power), .throw_valid(throw_valid), .throw_spin(throw_spin),
        .throw_mph10(throw_mph10), .aim_level(aim_level), .aim_right(aim_right), .reject(reject),
        .reject_msg(reject_msg), .cancel(swipe_cancel | too_short), .n_samples(n_samples),
        .lab_addr(lab_addr), .lab_px(lab_px), .color(a_c), .en(a_en), .txt(a_t),
        .cur_color(cur_c), .cur_en(cur_en), .led_a(led_a));

    menu_render u_menu (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .px_x(px_x), .px_y(px_y), .game_state(game_state),
        .settings(settings), .hover(hover), .chip_two(chip_two), .has_save(has_save),
        .leave_idx(leave_idx), .tab_quick(tab_quick), .erase_step(erase_step), .name(name),
        .name_pos(name_pos), .name_player(name_player), .newhi(newhi), .two_players(t_kind[`PK_TWO]),
        .game0(game0), .game1(game1), .flash_ok(flash_ok), .ra_lo(ra_mlo), .ra_hi(ra_mhi),
        .rd_lo(rd_mlo), .rd_hi(rd_mhi), .color(menu_c), .en(menu_en), .txt(menu_t));

    hud_render u_hud (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .px_x(px_x), .px_y(px_y), .game_state(game_state),
        .settings(settings), .kind(t_kind), .player(player), .frame(frame), .ball_no(ball_no),
        .score(player ? game1 : game0), .pins_standing(standing), .popup_id(popup_id),
        .popup_n(popup_n), .banner(banner), .ghost(ghost), .grabbing(grabbing), .paused(paused),
        .saving(saving), .leave_idx(leave_idx), .spare_made(spare_made), .spare_tries(spare_tries),
        .stance_x(stance_x), .color(hud_c), .en(hud_en), .txt(hud_t));

    scorecard_render u_card (
        .px_x(px_x), .px_y(px_y), .show(in_play && !t_kind[`PK_SPARE] && (card_show || card_auto)),
        .player(player), .two(t_kind[`PK_TWO]), .card_addr(card_addr), .card_word(card_word),
        .game0(game0), .game1(game1), .color(sc_c), .en(sc_en), .txt(sc_t));

    compositor u_comp (
        .clk(clk), .rst(rst), .tick_frame(tick_frame), .px_x(px_x), .px_y(px_y), .game_state(game_state),
        .settings(settings), .cur_en(cur_en), .cur_c(cur_c), .sc_en(sc_en), .sc_c(sc_c), .sc_t(sc_t),
        .hud_en(hud_en), .hud_c(hud_c), .hud_t(hud_t), .menu_en(menu_en), .menu_c(menu_c),
        .menu_t(menu_t), .a_en(a_en), .a_c(a_c), .a_t(a_t), .ball_en(ball_en), .ball_c(ball_c),
        .pin_en(pin_en && in_play), .pin_c(pin_c), .lane_en(lane_en && in_play), .lane_c(lane_c),
        .oled_data(oled_data));

    // =================== LEDs, 7-seg ===========================================
    assign led[9:0]   = in_play ? standing : (load_done ? 10'd0 : {10{frame_cnt[4]}});
    assign led[15:10] = led_a;

    wire [23:0] seg_glyphs;
    wire [3:0]  seg_dps;
    seg7_ctrl u_segc (
        .clk(clk), .rst(rst), .tick_game(tick_game), .game_state(game_state), .hover(hover),
        .paused(paused), .throw_valid(throw_valid), .mph10(throw_mph10),
        .score(game_state == `GS_GAMEOVER ? game0 : (player ? game1 : game0)),
        .glyphs(seg_glyphs), .dps(seg_dps));
    seg7_driver u_seg (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .glyphs(seg_glyphs), .dps(seg_dps), .blink(4'b0000),
        .blink_phase(1'b0), .seg(seg), .dp(dp), .an(an));
endmodule
