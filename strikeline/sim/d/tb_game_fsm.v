`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// tb_game_fsm.v : every path through game_fsm, with a stub turn_fsm and the
//                 real persist_ctrl + save_image (so scores really get saved)
//-----------------------------------------------------------------------------
// Walks the screens with the BUTTONS (the second way to do everything) and
// some with the MOUSE: title, menu, quick game, game over, top-5 check,
// initials (incl. stepping back a letter), high scores, settings (incl. the
// v3.5 set_dirty bug, fixed), erase saves (2 clicks), a 2-player Full game
// with two sets of initials, pause + click to leave, RESUME, help, zoom,
// replay / skip, hold btnL to leave.
//=============================================================================
module tb_game_fsm;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1, load_done = 0, mouse_move = 0, l_press = 0, r_press = 0, r_level = 0, m_press = 0;
    reg [6:0] cursor_x = 0; reg [5:0] cursor_y = 0;
    reg signed [3:0] wheel = 0;
    reg [4:0] btn_press = 0, btn_long = 0;
    reg paused = 0; reg [3:0] sw_play = 4'b0000; reg sw_lefty = 0;
    reg [4:0] tstate = `GS_AIM; reg t_game_over = 0; reg [2:0] t_kind = 0;
    reg [8:0] game0 = 0, game1 = 0;
    reg tb_def = 0;                                   // "flash_ctrl" asks for defaults at boot

    wire nudge_l, nudge_r, go_new, go_resume, abort, c_settings, c_insert, ins_quick, c_gameend, gend_full;
    wire c_defaults, save_req, chip_two, has_save, tab_quick, name_player, card_show, aim_zoom, want_replay, skip;
    wire [2:0] kind_out, hover, leave_idx; wire [9:0] leave_mask; wire [6:0] ra; wire [7:0] rd;
    wire [8:0] ins_score, gend_score; wire [14:0] ins_name, name; wire [4:0] game_state;
    wire [15:0] settings, settings_raw; wire [1:0] erase_step, name_pos, newhi;
    wire persist_busy;

    game_fsm dut (
        .clk(clk), .rst(rst), .tick_game(1'b0), .load_done(load_done), .cursor_x(cursor_x), .cursor_y(cursor_y),
        .mouse_move(mouse_move), .l_press(l_press), .r_press(r_press), .r_level(r_level), .m_press(m_press),
        .wheel(wheel), .btn_press(btn_press), .btn_repeat(5'd0), .btn_long(btn_long), .sw_lefty(sw_lefty),
        .paused(paused), .sw_play(sw_play), .nudge_l(nudge_l), .nudge_r(nudge_r), .tstate(tstate), .t_active(1'b0),
        .t_game_over(t_game_over), .t_kind(t_kind), .go_new(go_new), .go_resume(go_resume), .kind_out(kind_out),
        .leave_mask(leave_mask), .abort(abort), .game0(game0), .game1(game1), .ra(ra), .rd(rd),
        .persist_busy(persist_busy), .c_settings(c_settings), .c_insert(c_insert), .ins_quick(ins_quick),
        .ins_score(ins_score), .ins_name(ins_name), .c_gameend(c_gameend), .gend_full(gend_full),
        .gend_score(gend_score), .c_defaults(c_defaults), .save_req(save_req), .game_state(game_state),
        .settings(settings), .settings_raw(settings_raw), .hover(hover), .chip_two(chip_two), .has_save(has_save),
        .leave_idx(leave_idx), .tab_quick(tab_quick), .erase_step(erase_step), .name(name), .name_pos(name_pos),
        .name_player(name_player), .newhi(newhi), .card_show(card_show), .aim_zoom(aim_zoom),
        .want_replay(want_replay), .skip(skip));

    // ---- the real persist_ctrl + save image ----
    wire pwe; wire [6:0] pwa, pra; wire [7:0] pwd, prd;
    persist_ctrl u_p (.clk(clk), .rst(rst), .c_roll(1'b0), .roll_p(1'b0), .roll_idx(5'd0), .roll_val(4'd0),
        .c_hdr(1'b0), .hdr_valid(1'b0), .hdr_kind(3'd0), .hdr_player(1'b0), .hdr_frame(4'd0), .c_clear(1'b0),
        .c_strike(1'b0), .c_spare(1'b0), .c_gameend(c_gameend), .c_insert(c_insert), .ins_quick(ins_quick),
        .ins_score(ins_score), .ins_name(ins_name), .c_settings(c_settings), .set_value(settings_raw),
        .c_defaults(c_defaults | tb_def), .gend_full(gend_full), .gend_score(gend_score),
        .we(pwe), .wa(pwa), .wd(pwd), .ra(pra), .rd(prd), .busy(persist_busy));
    save_image u_img (.clk(clk), .we_flash(1'b0), .wa_flash(7'd0), .wd_flash(8'd0), .we_game(pwe), .wa_game(pwa),
        .wd_game(pwd), .ra0(7'd0), .ra1(pra), .ra2(7'd0), .ra3(ra), .ra4(7'd0), .ra5(7'd0), .ra6(7'd0),
        .rd0(), .rd1(prd), .rd2(), .rd3(rd), .rd4(), .rd5(), .rd6());

    // ---- counters for 1-clock pulses ----
    integer n_new = 0, n_res = 0, n_abort = 0, n_set = 0, n_ins = 0, n_gend = 0, n_def = 0, n_save = 0, n_rep = 0, n_skip = 0;
    always @(posedge clk) begin
        if (go_new) n_new = n_new + 1;         if (go_resume) n_res = n_res + 1;
        if (abort) n_abort = n_abort + 1;      if (c_settings) n_set = n_set + 1;
        if (c_insert) n_ins = n_ins + 1;       if (c_gameend) n_gend = n_gend + 1;
        if (c_defaults) n_def = n_def + 1;     if (save_req) n_save = n_save + 1;
        if (want_replay) n_rep = n_rep + 1;    if (skip) n_skip = n_skip + 1;
    end

    integer errors = 0;
    task check(input cond, input [8*100-1:0] msg);
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask
    // a button press (1 clock), then let things settle
    task press(input integer b);
        begin
            @(posedge clk) btn_press[b] <= 1'b1;
            @(posedge clk) btn_press[b] <= 1'b0;
            repeat (6) @(posedge clk);
            while (persist_busy) @(posedge clk);
            repeat (4) @(posedge clk);
        end
    endtask
    task press_n(input integer b, input integer times);
        integer i; begin for (i = 0; i < times; i = i + 1) press(b); end
    endtask
    task mouse_to(input [6:0] x, input [5:0] y);
        begin
            @(posedge clk) begin cursor_x <= x; cursor_y <= y; mouse_move <= 1'b1; end
            @(posedge clk) mouse_move <= 1'b0;
            repeat (4) @(posedge clk);
        end
    endtask
    task lclick;
        begin
            @(posedge clk) l_press <= 1'b1;
            @(posedge clk) l_press <= 1'b0;
            repeat (6) @(posedge clk);
            while (persist_busy) @(posedge clk);
            repeat (4) @(posedge clk);
        end
    endtask
    task rclick;
        begin @(posedge clk) r_press <= 1'b1; @(posedge clk) r_press <= 1'b0; repeat (6) @(posedge clk); end
    endtask
    task game_over(input [8:0] s0, input [8:0] s1);
        begin
            game0 <= s0; game1 <= s1;
            @(posedge clk) t_game_over <= 1'b1;
            @(posedge clk) t_game_over <= 0;
            repeat (60) @(posedge clk);
            while (persist_busy) @(posedge clk);
            repeat (10) @(posedge clk);
        end
    endtask
    function [8:0] e_score(input [6:0] t, input [2:0] e); e_score = {u_img.mem[t + 5 * e + 1][0], u_img.mem[t + 5 * e]}; endfunction
    function [14:0] e_name(input [6:0] t, input [2:0] e);
        e_name = {u_img.mem[t + 5 * e + 2][4:0], u_img.mem[t + 5 * e + 3][4:0], u_img.mem[t + 5 * e + 4][4:0]};
    endfunction
    // stub turn_fsm: the kind comes from game_fsm when a game starts
    always @(posedge clk) if (go_new) t_kind <= kind_out;

    localparam U = `BTN_U, D = `BTN_D, L = `BTN_L, R = `BTN_R, C = `BTN_C;
    integer k;
    initial begin
        repeat (3) @(posedge clk);
        rst <= 0;
        @(posedge clk) tb_def <= 1;                     // flash: blank -> factory image
        @(posedge clk) tb_def <= 0;
        repeat (5) @(posedge clk);
        while (persist_busy) @(posedge clk);
        check(game_state == `GS_TITLE && dut.mode == dut.M_BOOT, "boot: waits for load_done (title shown)");
        // ---- boot -> title ----
        load_done <= 1;
        repeat (10) @(posedge clk);
        check(dut.mode == 4'd0 && game_state == `GS_TITLE, "load_done: settings read, TITLE (mode code 0)");
        check(settings_raw == `SET_DEFAULT, "settings read from the image = factory 0x0192");
        sw_play <= 4'b1010; sw_lefty <= 1; #1;
        check(settings[`SET_OIL] && !settings[`SET_THEME] && settings[`SET_LB_HI:`SET_LB_LO] == 2'd2 && settings[`SET_LEFTY],
              "switches: long oil (sw14), 16 lb (sw12), lefty (sw15) go into settings");
        sw_play <= 4'b0000; sw_lefty <= 0;
        // ---- title -> menu -> quick game ----
        press(C);
        check(game_state == `GS_MENU && hover == 3'd2, "btnC on the title: MENU, QUICK GAME highlighted");
        check(!has_save, "no saved game: RESUME is greyed out");
        press(C);
        check(n_new == 1 && kind_out == 3'b000 && dut.mode == dut.M_PLAY && game_state == `GS_AIM,
              "btnC: go_new, Quick 1P (kind 000), PLAY, game_state = turn_fsm's (AIM)");
        // ---- in the game ----
        r_level <= 1; repeat (3) @(posedge clk);
        check(aim_zoom, "hold right button while aiming: zoom");
        r_level <= 0; repeat (3) @(posedge clk);
        check(!aim_zoom, "let go: zoom off");
        press(L);
        check(dut.mode == dut.M_PLAY && n_abort == 0, "btnL tap while aiming = nudge, not quit");
        tstate <= `GS_RESULT; repeat (2) @(posedge clk);
        @(posedge clk) m_press <= 1; @(posedge clk) m_press <= 0;
        lclick;
        check(n_rep == 1 && n_skip == 1, "RESULT: middle click = replay, click = skip");
        tstate <= `GS_AIM;
        // ---- game over 150 -> top 5 -> initials ----
        game_over(9'd150, 9'd0);
        check(n_gend == 1 && dut.mode == dut.M_OVER && newhi == 2'b01 && game_state == `GS_GAMEOVER,
              "game over 150: GAMEEND sent, made the (empty) top 5, GAME OVER");
        check(u_img.mem[`IM_GAMES] == 1, "persist_ctrl counted the game");
        press(C);
        check(game_state == `GS_NAME && name_pos == 0 && name == 0, "btnC: initials entry, letter 1 = A");
        press_n(U, 2);                                    // A -> C
        press(C);                                         // letter 2
        press(D);                                         // A -> Z (wraps)
        press(C);                                         // letter 3
        press(L);                                         // back to letter 2
        check(name_pos == 1, "btnL steps back to the previous letter");
        press(C);                                         // letter 3 again
        press(U);                                         // A -> B
        press(C);                                         // confirm
        check(n_ins == 1 && ins_name == {5'd2, 5'd25, 5'd1} && ins_score == 150 && ins_quick,
              "3rd letter: INSERT 'CZB' 150 into the Quick table");
        check(game_state == `GS_SCORES && tab_quick, "then HIGH SCORES on the QUICK tab");
        check(e_score(`IM_TOPQ, 0) == 150 && e_name(`IM_TOPQ, 0) == {5'd2, 5'd25, 5'd1}, "image: Quick place 1 = CZB 150");
        press(U);
        check(!tab_quick, "btnU on HIGH SCORES: FULL tab");
        press(L);
        check(game_state == `GS_MENU && hover == 3'd4, "btnL: back to MENU, HIGH SCORES highlighted");
        // ---- settings: the set_dirty fix ----
        press(D);                                         // hover 5 = SETTINGS
        press(C);
        check(game_state == `GS_SETTINGS && hover == 3'd1, "SETTINGS, row 1 (SPIN) highlighted");
        press_n(D, 5);                                    // row 6 = BRIGHT
        press(C);                                         // brightness 3 -> 0
        check(settings_raw[`SET_BRI_HI:`SET_BRI_LO] == 2'd0, "btnC on BRIGHT: brightness 3 -> 0");
        press_n(U, 4);                                    // row 2 = BALL (on a switch)
        press(C);                                         // click a read-only row
        k = n_set;
        press(L);
        check(n_set == k + 1, "leave SETTINGS: settings saved even after clicking a switch row (v3.5 bug fixed)");
        check(u_img.mem[`IM_SET_LO] == settings_raw[7:0] && u_img.mem[`IM_SET_HI] == settings_raw[15:8],
              "image holds the new settings");
        check(game_state == `GS_MENU && hover == 3'd5, "back in MENU, SETTINGS highlighted");
        press(C);                                         // SETTINGS again, no change
        k = n_set;
        press(L);
        check(n_set == k, "leave SETTINGS without a change: nothing saved");
        // ---- erase saves: 2 clicks ----
        press(C);
        press_n(D, 6);                                    // row 7 = ERASE
        press(C);
        check(erase_step == 2'd1 && n_def == 0, "ERASE click 1: 'SURE?', nothing erased yet");
        press(C);
        check(erase_step == 2'd2 && n_def == 1 && settings_raw == `SET_DEFAULT, "ERASE click 2: defaults sent, settings reset");
        check(!u_img.mem[`IM_TOPQ + 1][7], "image: Quick top 5 is empty again");
        press(L);
        // ---- 2-player Full game: two sets of initials ----
        press(R);
        check(chip_two, "btnR in MENU: 1P/2P chip -> 2P");
        press_n(U, 2);                                    // hover 3 = FULL
        press(C);
        check(n_new == 2 && kind_out == 3'b011, "FULL GAME 2P: kind 011");
        game_over(9'd200, 9'd100);
        check(newhi == 2'b11 && n_gend == 3, "both players made the top 5; one GAMEEND each");
        press(C);
        check(game_state == `GS_NAME && name_player == 0, "initials for P1 first");
        press_n(C, 3);                                    // AAA
        check(game_state == `GS_NAME && name_player == 1 && name_pos == 0, "then P2's initials");
        press(D); press_n(C, 3);                          // ZAA
        check(n_ins == 3 && game_state == `GS_SCORES && !tab_quick, "two INSERTs, then HIGH SCORES on the FULL tab");
        check(e_score(`IM_TOPF, 0) == 200 && e_score(`IM_TOPF, 1) == 100 && e_name(`IM_TOPF, 1) == {5'd25, 5'd0, 5'd0},
              "image: Full table 200 AAA, 100 ZAA");
        press(L);
        // ---- pause + click leaves the game ----
        press(R);                                         // back to 1P
        press_n(U, 1);                                    // hover 2 = QUICK
        press(C);
        paused <= 1;
        press(C);
        check(n_abort == 1 && game_state == `GS_MENU, "paused (sw0) + btnC: abort, back to MENU");
        paused <= 0;
        // ---- RESUME (a saved game in the image) ----
        u_img.mem[`IM_GVALID] = 8'd1;
        repeat (5) @(posedge clk);
        check(has_save, "a saved game in the image: RESUME available");
        press_n(U, 3);                                    // hover 1
        press(C);
        check(n_res == 1 && dut.mode == dut.M_PLAY, "RESUME: go_resume, PLAY");
        @(posedge clk) btn_long[L] <= 1; @(posedge clk) btn_long[L] <= 0; repeat (3) @(posedge clk);
        check(n_abort == 2 && game_state == `GS_MENU, "hold btnL in a game: abort, MENU");
        // ---- the mouse: hover follows the pointer, click chooses ----
        mouse_to(7'd20, 6'd34);                           // row 4
        check(hover == 3'd4, "pointer on row 4: HIGH SCORES highlighted");
        lclick;
        check(game_state == `GS_SCORES, "click: HIGH SCORES");
        mouse_to(7'd70, 6'd3); lclick;
        check(tab_quick, "click on the tab: QUICK");
        rclick;
        check(game_state == `GS_MENU, "right click: back");
        mouse_to(7'd20, 6'd50);                           // row 6
        lclick;
        check(game_state == `GS_HELP, "click HELP");
        lclick;
        check(game_state == `GS_MENU && hover == 3'd6, "click on HELP: back to MENU");
        mouse_to(7'd85, 6'd20); lclick;                   // the chip on row 2
        check(chip_two && game_state == `GS_MENU, "click on the 1P/2P chip toggles it (no game started)");
        press(L);
        check(game_state == `GS_TITLE, "btnL in MENU: back to TITLE");
        check(leave_mask == 0 && leave_idx == 3'd1, "unused practice outputs are constant");
        if (errors == 0) $display("PASS tb_game_fsm: all checks");
        else             $display("FAIL tb_game_fsm: %0d errors", errors);
        $finish;
    end
    initial begin #20_000_000; $display("FAIL tb_game_fsm: timeout"); $finish; end
endmodule
