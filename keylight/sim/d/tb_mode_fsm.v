`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// tb_mode_fsm.v : D's mode FSM follows the demo path and the global rules
//   TITLE -C-> MENU -D,D-> cursor 2 -U,U-> cursor 0 -C-> SONGSEL
//   -D-> song 1, -R-> HARD, -C-> PLAY -res_valid-> RESULTS -R-> PLAY (retry)
//   -L-> SONGSEL -L-> MENU; long-L from Free Play -> MENU; MY SONG only
//   selectable when rec_exists; cursor wraps around.
//=============================================================================
module tb_mode_fsm;
    reg clk = 0, rst = 1, rec = 0, resv = 0;
    reg [4:0] bp = 0, bl = 0, br = 0;
    wire [3:0] mode;
    wire [2:0] menu_idx, song_id;
    wire [1:0] diff;
    wire learn_sel, sfx_v;
    wire [15:0] settings;
    wire [3:0] sfx_id;
    mode_fsm dut (.clk(clk), .rst(rst), .btn_press(bp), .btn_long(bl), .btn_repeat(br),
        .rec_exists(rec), .res_valid(resv), .mode(mode), .menu_idx(menu_idx),
        .song_id(song_id), .difficulty(diff), .learn_sel(learn_sel), .settings(settings),
        .sfx_valid(sfx_v), .sfx_id(sfx_id));
    always #5 clk = ~clk;

    integer errors = 0;
    task press; input integer b;   // b = bit index {U4,D3,L2,R1,C0}
        begin @(posedge clk) bp <= (5'd1 << b); @(posedge clk) bp <= 0; repeat (2) @(posedge clk); end
    endtask
    task check; input cond; input [8*40-1:0] msg;
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s (mode %0d)", msg, mode); errors = errors + 1; end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); rst = 0; @(posedge clk);
        check(mode == `KL_MODE_TITLE, "starts on the title screen");
        check(settings == `KL_SETTINGS_DEFAULT, "settings start at defaults");
        press(0); check(mode == `KL_MODE_MENU, "C on title -> menu");
        press(3); press(3); check(menu_idx == 2, "down twice -> Free Play item");
        press(4); press(4); press(4); check(menu_idx == 4, "up wraps to the last item");
        press(3); check(menu_idx == 0, "down wraps to the first item");
        press(0); check(mode == `KL_MODE_SONGSEL && !learn_sel, "Play -> song select");
        press(3); press(1);
        check(song_id == 1 && diff == `KL_DIFF_HARD, "song 1, difficulty Normal->Hard");
        press(1); check(diff == `KL_DIFF_EASY, "difficulty wraps Hard->Easy");
        press(1);
        press(3); press(3); press(3); check(song_id == 0, "4 ROM songs wrap (no MY SONG)");
        rec = 1; press(4); check(song_id == 4, "MY SONG appears when a recording exists");
        rec = 0; repeat (2) @(posedge clk); check(song_id == 0, "MY SONG removed -> back to song 0");
        press(0); check(mode == `KL_MODE_PLAY, "C -> Play");
        @(posedge clk) resv <= 1; @(posedge clk) resv <= 0; @(posedge clk);
        check(mode == `KL_MODE_RESULTS, "song end -> results");
        press(1); check(mode == `KL_MODE_PLAY, "R on results -> retry");
        press(2); check(mode == `KL_MODE_SONGSEL, "L in Play -> song select");
        press(2); check(mode == `KL_MODE_MENU, "L -> menu");
        press(3); press(3); press(0); check(mode == `KL_MODE_FREE, "menu item 2 -> Free Play");
        @(posedge clk) bl <= 5'b00100; @(posedge clk) bl <= 0; @(posedge clk);
        check(mode == `KL_MODE_MENU, "long L anywhere -> menu");
        press(4); press(0); check(mode == `KL_MODE_SONGSEL && learn_sel, "Learn -> song select");
        press(0); check(mode == `KL_MODE_LEARN, "C -> Learn mode");
        if (errors == 0) $display("PASS tb_mode_fsm: all checks");
        else             $display("FAIL tb_mode_fsm: %0d errors", errors);
        $finish;
    end
endmodule
