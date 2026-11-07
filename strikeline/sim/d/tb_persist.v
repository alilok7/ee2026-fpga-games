`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// tb_persist.v : persist_ctrl + save_image, every command, hand-worked answers
//-----------------------------------------------------------------------------
// The expected values are worked out by hand (docs/08_MODULE_NOTES.md), e.g.
// the top-5 insert: 200, 180, 120 then 150 -> 200, 180, 150, 120.
//=============================================================================
module tb_persist;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;
    reg c_roll = 0, roll_p = 0, c_hdr = 0, hdr_valid = 0, hdr_player = 0, c_clear = 0;
    reg c_strike = 0, c_spare = 0, c_gameend = 0, c_insert = 0, ins_quick = 0, c_settings = 0;
    reg c_defaults = 0, gend_full = 0;
    reg [4:0] roll_idx = 0; reg [3:0] roll_val = 0, hdr_frame = 0; reg [2:0] hdr_kind = 0;
    reg [8:0] ins_score = 0, gend_score = 0; reg [14:0] ins_name = 0; reg [15:0] set_value = 0;
    wire we, busy; wire [6:0] wa, ra; wire [7:0] wd, rd;

    persist_ctrl dut (
        .clk(clk), .rst(rst), .c_roll(c_roll), .roll_p(roll_p), .roll_idx(roll_idx), .roll_val(roll_val),
        .c_hdr(c_hdr), .hdr_valid(hdr_valid), .hdr_kind(hdr_kind), .hdr_player(hdr_player), .hdr_frame(hdr_frame),
        .c_clear(c_clear), .c_strike(c_strike), .c_spare(c_spare), .c_gameend(c_gameend), .c_insert(c_insert),
        .ins_quick(ins_quick), .ins_score(ins_score), .ins_name(ins_name), .c_settings(c_settings),
        .set_value(set_value), .c_defaults(c_defaults), .gend_full(gend_full), .gend_score(gend_score),
        .we(we), .wa(wa), .wd(wd), .ra(ra), .rd(rd), .busy(busy));
    save_image img (.clk(clk), .we_flash(1'b0), .wa_flash(7'd0), .wd_flash(8'd0),
                    .we_game(we), .wa_game(wa), .wd_game(wd),
                    .ra0(7'd0), .ra1(ra), .ra2(7'd0), .ra3(7'd0), .ra4(7'd0), .ra5(7'd0), .ra6(7'd0),
                    .rd0(), .rd1(rd), .rd2(), .rd3(), .rd4(), .rd5(), .rd6());

    integer errors = 0;
    task check(input cond, input [8*64-1:0] msg);
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask
    task wait_idle;
        begin @(posedge clk); while (busy) @(posedge clk); @(posedge clk); end
    endtask
    function [7:0] m(input [6:0] a); m = img.mem[a]; endfunction
    function [8:0] w16(input [6:0] a); w16 = {img.mem[a + 1], img.mem[a]}; endfunction
    // entry e of a table: score and name
    function [8:0] e_score(input [6:0] t, input [2:0] e);
        e_score = {img.mem[t + 5 * e + 1][0], img.mem[t + 5 * e]};
    endfunction
    function e_valid(input [6:0] t, input [2:0] e); e_valid = img.mem[t + 5 * e + 1][7]; endfunction
    function [14:0] e_name(input [6:0] t, input [2:0] e);
        e_name = {img.mem[t + 5 * e + 2][4:0], img.mem[t + 5 * e + 3][4:0], img.mem[t + 5 * e + 4][4:0]};
    endfunction
    function [14:0] nm(input [4:0] a, input [4:0] b, input [4:0] c); nm = {a, b, c}; endfunction

    task insert(input q, input [8:0] s, input [14:0] n);
        begin
            @(posedge clk) begin c_insert <= 1; ins_quick <= q; ins_score <= s; ins_name <= n; end
            @(posedge clk) c_insert <= 0;
            wait_idle;
        end
    endtask
    task gameend(input full, input [8:0] s);
        begin
            @(posedge clk) begin c_gameend <= 1; gend_full <= full; gend_score <= s; end
            @(posedge clk) c_gameend <= 0;
            wait_idle;
        end
    endtask

    integer i, bad;
    reg busy_same_clock;
    initial begin
        repeat (3) @(posedge clk);
        rst <= 0;
        @(posedge clk);
        // ---- 1. DEFAULTS: factory image ----
        @(posedge clk) c_defaults <= 1;
        #1 busy_same_clock = busy;                     // busy must already be high
        @(posedge clk) c_defaults <= 0;
        wait_idle;
        check(busy_same_clock, "busy goes high on the same clock as the command");
        bad = 0;
        for (i = 0; i < 128; i = i + 1) begin
            if (i == 0 && m(i) != 8'h53) bad = bad + 1;
            else if (i == 1 && m(i) != 8'h4C) bad = bad + 1;
            else if (i == 2 && m(i) != 8'h01) bad = bad + 1;
            else if (i == 5 && m(i) != 8'h92) bad = bad + 1;          // SET_DEFAULT = 0x0192
            else if (i == 6 && m(i) != 8'h01) bad = bad + 1;
            else if (i >= 70 && i < 112 && m(i) != 8'h0F) bad = bad + 1;
            else if (!(i <= 2 || i == 5 || i == 6 || (i >= 70 && i < 112)) && m(i) != 8'h00) bad = bad + 1;
        end
        check(bad == 0, "DEFAULTS: 'S','L', v1, settings 0x0192, rolls = 15, rest 0");
        // ---- 2. ROLL ----
        @(posedge clk) begin c_roll <= 1; roll_p <= 0; roll_idx <= 3; roll_val <= 7; end
        @(posedge clk) c_roll <= 0;
        wait_idle;
        check(m(`IM_ROLLS0 + 3) == 7 && m(`IM_NROLL0) == 4, "ROLL p1 idx 3 = 7, nroll0 = 4");
        @(posedge clk) begin c_roll <= 1; roll_p <= 1; roll_idx <= 0; roll_val <= 10; end
        @(posedge clk) c_roll <= 0;
        wait_idle;
        check(m(`IM_ROLLS1) == 10 && m(`IM_NROLL1) == 1, "ROLL p2 idx 0 = 10, nroll1 = 1");
        // ---- 3. HEADER ----
        @(posedge clk) begin c_hdr <= 1; hdr_valid <= 1; hdr_kind <= 3; hdr_player <= 1; hdr_frame <= 9; end
        @(posedge clk) c_hdr <= 0;
        wait_idle;
        check(m(`IM_GVALID) == 1 && m(`IM_GKIND) == 3 && m(`IM_GPLAYER) == 1 && m(`IM_GFRAME) == 9,
              "HEADER valid, kind 3, player 2, frame 10");
        // ---- 4. CLEAR ----
        @(posedge clk) c_clear <= 1;
        @(posedge clk) c_clear <= 0;
        wait_idle;
        bad = 0;
        for (i = 70; i < 112; i = i + 1) if (m(i) != 8'h0F) bad = bad + 1;
        check(bad == 0 && m(`IM_NROLL0) == 0 && m(`IM_NROLL1) == 0 && m(`IM_GVALID) == 0,
              "CLEAR: rolls = 15, counts 0, no saved game");
        // ---- 5. STRIKE with a carry, SPARE ----
        img.mem[`IM_STRK] = 8'hFF; img.mem[`IM_STRK + 1] = 8'h00;
        @(posedge clk) c_strike <= 1;
        @(posedge clk) c_strike <= 0;
        wait_idle;
        check(m(`IM_STRK) == 8'h00 && m(`IM_STRK + 1) == 8'h01, "STRIKE: 0x00FF + 1 = 0x0100 (carry)");
        @(posedge clk) c_spare <= 1;
        @(posedge clk) c_spare <= 0;
        wait_idle;
        check(m(`IM_SPAR) == 1 && m(`IM_SPAR + 1) == 0, "SPARE: 0 + 1 = 1");
        // ---- 6. GAMEEND and BEST ----
        gameend(1, 9'd250);
        check(m(`IM_GAMES) == 1 && w16(`IM_BEST) == 250, "GAMEEND Full 250: games 1, best 250");
        gameend(1, 9'd100);
        check(m(`IM_GAMES) == 2 && w16(`IM_BEST) == 250, "GAMEEND Full 100: games 2, best stays 250");
        gameend(0, 9'd290);
        check(m(`IM_GAMES) == 3 && w16(`IM_BEST) == 250, "GAMEEND Quick 290: games 3, best (Full only) 250");
        gameend(1, 9'd300);
        check(w16(`IM_BEST) == 300, "GAMEEND Full 300: best 300 (uses score bit 8)");
        // ---- 7. INSERT into the Full table ----
        insert(0, 9'd200, nm(0, 1, 2));          // ABC
        insert(0, 9'd180, nm(3, 4, 5));          // DEF
        insert(0, 9'd120, nm(6, 7, 8));          // GHI
        insert(0, 9'd150, nm(9, 10, 11));        // JKL goes between 180 and 120
        check(e_score(`IM_TOPF, 0) == 200 && e_score(`IM_TOPF, 1) == 180 && e_score(`IM_TOPF, 2) == 150 &&
              e_score(`IM_TOPF, 3) == 120 && !e_valid(`IM_TOPF, 4),
              "INSERT 200,180,120,150 -> 200,180,150,120,empty");
        check(e_name(`IM_TOPF, 2) == nm(9, 10, 11) && e_name(`IM_TOPF, 3) == nm(6, 7, 8),
              "names moved with their scores (JKL, GHI)");
        insert(0, 9'd300, nm(25, 25, 25));       // new best: top
        check(e_score(`IM_TOPF, 0) == 300 && e_score(`IM_TOPF, 4) == 120 && e_valid(`IM_TOPF, 4),
              "INSERT 300 -> top; table now full (300..120)");
        insert(0, 9'd50, nm(1, 1, 1));           // does not qualify
        check(e_score(`IM_TOPF, 4) == 120 && e_name(`IM_TOPF, 4) == nm(6, 7, 8), "INSERT 50 into a full table: ignored");
        // table is 300, 200, 180, 150, 120: 130 beats only place 5, 120 drops out
        insert(0, 9'd130, nm(2, 2, 2));
        check(e_score(`IM_TOPF, 3) == 150 && e_score(`IM_TOPF, 4) == 130 && e_name(`IM_TOPF, 4) == nm(2, 2, 2),
              "INSERT 130 into 300,200,180,150,120 -> place 5, 120 drops out");
        insert(0, 9'd130, nm(3, 3, 3));          // equal to place 5: must BEAT it
        check(e_name(`IM_TOPF, 4) == nm(2, 2, 2), "INSERT 130 again (a tie with place 5): not inserted");
        insert(0, 9'd190, nm(4, 4, 4));          // 300,200,190,180,150
        check(e_score(`IM_TOPF, 2) == 190 && e_score(`IM_TOPF, 3) == 180 && e_score(`IM_TOPF, 4) == 150,
              "INSERT 190 -> place 3; 180, 150 move down; 130 drops out");
        // ---- 8. the Quick table is separate ----
        insert(1, 9'd90, nm(4, 4, 4));
        check(e_score(`IM_TOPQ, 0) == 90 && e_valid(`IM_TOPQ, 0) && !e_valid(`IM_TOPQ, 1) &&
              e_score(`IM_TOPF, 0) == 300, "INSERT Quick 90: Quick table only");
        // ---- 9. SETTINGS ----
        @(posedge clk) begin c_settings <= 1; set_value <= 16'hBEEF; end
        @(posedge clk) c_settings <= 0;
        wait_idle;
        check(m(`IM_SET_LO) == 8'hEF && m(`IM_SET_HI) == 8'hBE, "SETTINGS 0xBEEF");
        // ---- 10. four commands on the same clock: none lost ----
        @(posedge clk) begin c_strike <= 1; c_spare <= 1; c_settings <= 1; set_value <= 16'h1234;
                             c_roll <= 1; roll_p <= 0; roll_idx <= 5; roll_val <= 9; end
        @(posedge clk) begin c_strike <= 0; c_spare <= 0; c_settings <= 0; c_roll <= 0; end
        wait_idle;
        check(m(`IM_STRK) == 8'h01 && m(`IM_SPAR) == 2 && m(`IM_SET_LO) == 8'h34 && m(`IM_ROLLS0 + 5) == 9,
              "4 commands in one clock: all done (pending flags)");
        // ---- 11. a command while another job runs ----
        @(posedge clk) c_clear <= 1;
        @(posedge clk) c_clear <= 0;
        repeat (10) @(posedge clk);
        @(posedge clk) begin c_settings <= 1; set_value <= 16'h5A5A; end
        @(posedge clk) c_settings <= 0;
        wait_idle;
        check(m(`IM_SET_LO) == 8'h5A && m(`IM_ROLLS0 + 5) == 8'h0F, "SETTINGS sent during CLEAR: both done");
        // ---- 12. a command on the clock its own job finishes: runs again ----
        @(posedge clk) c_spare <= 1;
        @(posedge clk) c_spare <= 0;
        while (!(dut.state == dut.S_SPAR && dut.step == 3)) @(posedge clk);
        c_spare <= 1;                            // arrives exactly as the flag is cleared
        @(posedge clk) c_spare <= 0;
        wait_idle;
        check(m(`IM_SPAR) == 4, "SPARE arriving as SPARE finishes is not lost (2 -> 4)");
        if (errors == 0) $display("PASS tb_persist: all checks");
        else             $display("FAIL tb_persist: %0d errors", errors);
        $finish;
    end
    initial begin #2_000_000; $display("FAIL tb_persist: timeout"); $finish; end
endmodule
