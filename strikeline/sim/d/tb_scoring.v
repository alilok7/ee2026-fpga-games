`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// tb_scoring.v : ten-pin scoring + the save image + persist_ctrl
//-----------------------------------------------------------------------------
// Owner : Student D
// Rolls are written exactly as in the game (persist_ctrl ROLL commands into
// the save image), then score_engine scores them. 12 known games, the
// scorecard marks of the classic example, the top-5 insert order and the
// best-game update.
//=============================================================================
module tb_scoring;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;

    // persist_ctrl command inputs
    reg c_roll = 0, roll_p = 0; reg [4:0] roll_idx = 0; reg [3:0] roll_val = 0;
    reg c_clear = 0, c_defaults = 0, c_insert = 0, ins_quick = 0, c_gameend = 0, gend_full = 0;
    reg [8:0] ins_score = 0, gend_score = 0; reg [14:0] ins_name = 0;
    wire we; wire [6:0] wa, ra_p, ra_s; wire [7:0] wd, rd_p, rd_s, rd_t;
    reg  [6:0] ra_t = 0;
    wire busy;

    persist_ctrl u_p (
        .clk(clk), .rst(rst), .c_roll(c_roll), .roll_p(roll_p), .roll_idx(roll_idx), .roll_val(roll_val),
        .c_hdr(1'b0), .hdr_valid(1'b0), .hdr_kind(3'd0), .hdr_player(1'b0), .hdr_frame(4'd0),
        .c_clear(c_clear), .c_strike(1'b0), .c_spare(1'b0), .c_gameend(c_gameend), .c_insert(c_insert),
        .ins_quick(ins_quick), .ins_score(ins_score), .ins_name(ins_name), .c_settings(1'b0),
        .set_value(16'd0), .c_defaults(c_defaults), .gend_full(gend_full), .gend_score(gend_score),
        .we(we), .wa(wa), .wd(wd), .ra(ra_p), .rd(rd_p), .busy(busy));
    save_image u_img (
        .clk(clk), .we_flash(1'b0), .wa_flash(7'd0), .wd_flash(8'd0), .we_game(we), .wa_game(wa),
        .wd_game(wd), .ra0(ra_p), .ra1(ra_s), .ra2(ra_t), .ra3(7'd0), .ra4(7'd0), .ra5(7'd0), .ra6(7'd0),
        .rd0(rd_p), .rd1(rd_s), .rd2(rd_t), .rd3(), .rd4(), .rd5(), .rd6());

    reg  sc_start = 0;
    reg  [3:0] start_frame = 0;
    wire [27:0] cw; wire [9:0] ok0, ok1; wire [8:0] g0, g1, pv0, pv1;
    wire sc_done;
    score_engine u_s (.clk(clk), .rst(rst), .start(sc_start), .start_frame(start_frame), .ra(ra_s),
        .rd(rd_s), .card_addr(5'd0), .card_word(cw), .ok0(ok0), .ok1(ok1),
        .game0(g0), .game1(g1), .prov0(pv0), .prov1(pv1), .done(sc_done));

    integer errors = 0;
    task check(input cond, input [8*48-1:0] msg);
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask

    task wait_idle; begin @(posedge clk); while (busy) @(posedge clk); @(posedge clk); end endtask

    // play a game: list of rolls in a 21-entry array
    integer rolls [0:20];
    integer nr;
    task play(input integer count, input integer sf);
        integer i;
        begin
            start_frame = sf;
            @(posedge clk) c_clear <= 1; @(posedge clk) c_clear <= 0;
            wait_idle;
            for (i = 0; i < count; i = i + 1) begin
                @(posedge clk); c_roll <= 1; roll_p <= 0; roll_idx <= i; roll_val <= rolls[i];
                @(posedge clk) c_roll <= 0;
                wait_idle;
            end
            @(posedge clk) sc_start <= 1; @(posedge clk) sc_start <= 0;
            @(posedge sc_done); @(posedge clk);
        end
    endtask
    task fill(input integer v, input integer count);
        integer i;
        begin for (i = 0; i < count; i = i + 1) rolls[nr + i] = v; nr = nr + count; end
    endtask
    // the scorecard word of player 1, frame f: {known, total, mark0, mark1, mark2}
    function [5:0] mark(input integer f, input integer b);
        mark = (b == 0) ? u_s.fr_mem[f][17:12] : (b == 1) ? u_s.fr_mem[f][11:6] : u_s.fr_mem[f][5:0];
    endfunction
    function [8:0] total(input integer f);
        total = u_s.fr_mem[f][26:18];
    endfunction

    initial begin
        repeat (3) @(posedge clk); rst <= 0;
        @(posedge clk) c_defaults <= 1; @(posedge clk) c_defaults <= 0; wait_idle;

        nr = 0; fill(10, 12); play(12, 0);
        check(g0 == 300 && ok0 == 10'h3FF, "perfect game = 300");
        check(pv0 == 300, "provisional = official when the game is complete (300)");
        check(mark(0,1) == 56 && mark(9,0) == 56 && mark(9,2) == 56, "strike marks X");

        nr = 0; fill(10, 11); fill(9, 1); play(12, 0);
        check(g0 == 299, "11 strikes + 9 = 299");

        nr = 0; fill(5, 21); play(21, 0);
        check(g0 == 150, "all 5/ spares = 150");
        check(mark(0,1) == 15, "spare mark /");

        nr = 0; fill(0, 20); play(20, 0);
        check(g0 == 0 && ok0 == 10'h3FF, "gutter game = 0");
        check(mark(3,0) == 13 && mark(3,1) == 13, "gutter marks -");

        nr = 0; fill(9, 1); fill(0, 1); fill(9, 1); fill(0, 1); fill(9, 1); fill(0, 1);
        fill(9, 1); fill(0, 1); fill(9, 1); fill(0, 1); fill(9, 1); fill(0, 1); fill(9, 1); fill(0, 1);
        fill(9, 1); fill(0, 1); fill(9, 1); fill(0, 1); fill(9, 1); fill(0, 1); play(20, 0);
        check(g0 == 90, "all 9- = 90");

        nr = 0; for (nr = 0; nr < 19; nr = nr + 2) begin rolls[nr] = 9; rolls[nr+1] = 1; end
        rolls[20] = 9; play(21, 0);
        check(g0 == 190, "all 9/ with a 9 bonus = 190");

        nr = 0; fill(10, 1); fill(0, 18); play(19, 0);
        check(g0 == 10, "strike then zeros = 10");

        nr = 0; fill(10, 1); rolls[1] = 3; rolls[2] = 4; nr = 3; fill(0, 16); play(19, 0);
        check(g0 == 24, "X then 3-4 = 24");

        nr = 0; fill(0, 18); rolls[18] = 7; rolls[19] = 3; rolls[20] = 10; play(21, 0);
        check(g0 == 20, "10th frame 7/X = 20");
        check(mark(9,0) == 23 && mark(9,1) == 15 && mark(9,2) == 56, "10th marks 7 / X");

        nr = 0; fill(0, 18); fill(10, 3); play(21, 0);
        check(g0 == 30, "10th frame XXX = 30");

        // classic example: X 7/ 9- X -8 8/ -6 X X X81 = 167
        rolls[0]=10; rolls[1]=7; rolls[2]=3; rolls[3]=9; rolls[4]=0; rolls[5]=10; rolls[6]=0; rolls[7]=8;
        rolls[8]=8; rolls[9]=2; rolls[10]=0; rolls[11]=6; rolls[12]=10; rolls[13]=10; rolls[14]=10;
        rolls[15]=8; rolls[16]=1; play(17, 0);
        check(g0 == 167, "classic example = 167");
        check(pv0 == 167, "provisional = 167 for the finished classic game");
        check(total(1) == 39 && total(3) == 66 && total(7) == 120, "classic running totals 39/66/120");
        check(mark(1,0) == 23 && mark(1,1) == 15 && mark(2,0) == 25 && mark(2,1) == 13, "marks 7 / 9 -");

        // unfinished game: a strike waits for its bonus balls
        rolls[0] = 10; rolls[1] = 10; play(2, 0);
        check(ok0 == 10'h000 && g0 == 0, "strike total unknown until 2 bonus balls");
        check(pv0 == 30, "provisional after X X = 30 (20 + 10), official still 0");
        rolls[0] = 7; rolls[1] = 3; play(2, 0);
        check(g0 == 0 && pv0 == 10, "provisional after a spare = 10, official 0");
        rolls[0] = 7; rolls[1] = 3; rolls[2] = 5; play(3, 0);
        check(g0 == 15 && pv0 == 20, "7/ then 5: official 15, provisional 20");
        rolls[0] = 10; rolls[1] = 4; play(2, 0);
        check(g0 == 0 && pv0 == 18, "X then 4: provisional 18 (14 + 4)");

        // Quick game (frames 8-10): X X XXX = 90
        nr = 0; fill(10, 5); play(5, 7);
        check(g0 == 90 && ok0 == 10'b11_1000_0000, "quick game frames 8-10, 5 strikes = 90");
        check(mark(0,0) == 0 && mark(0,1) == 0, "frames before 8 stay blank");

        // ---- top-5 insert order: 150, 200, 120, 250, 90, 180 -> 250 200 180 150 120
        begin : ins
            integer sc [0:5]; integer i;
            sc[0]=150; sc[1]=200; sc[2]=120; sc[3]=250; sc[4]=90; sc[5]=180;
            for (i = 0; i < 6; i = i + 1) begin
                @(posedge clk); c_insert <= 1; ins_quick <= 0; ins_score <= sc[i]; ins_name <= i;
                @(posedge clk) c_insert <= 0; wait_idle;
            end
        end
        begin : rd_top
            integer e, v; reg ok;
            ok = 1;
            for (e = 0; e < 5; e = e + 1) begin
                ra_t = `IM_TOPF + 5*e; #1 v = rd_t;
                ra_t = `IM_TOPF + 5*e + 1; #1 v = v + 256 * (rd_t & 1);
                if (!(rd_t & 8'h80)) ok = 0;
                $display("      top[%0d] = %0d", e, v);
                if (e == 0 && v != 250) ok = 0;
                if (e == 1 && v != 200) ok = 0;
                if (e == 2 && v != 180) ok = 0;
                if (e == 3 && v != 150) ok = 0;
                if (e == 4 && v != 120) ok = 0;
            end
            check(ok, "top-5 insert keeps the table sorted, 90 dropped");
        end

        // ---- best game
        @(posedge clk) c_gameend <= 1; gend_full <= 1; gend_score <= 9'd277;
        @(posedge clk) c_gameend <= 0; wait_idle;
        @(posedge clk) c_gameend <= 1; gend_full <= 1; gend_score <= 9'd201;
        @(posedge clk) c_gameend <= 0; wait_idle;
        ra_t = `IM_BEST; #1 nr = rd_t; ra_t = `IM_BEST + 1; #1 nr = nr + 256 * rd_t;
        check(nr == 277, "best game keeps the maximum (277)");
        ra_t = `IM_GAMES; #1;
        check(rd_t == 2, "games played counter = 2");

        if (errors == 0) $display("PASS tb_scoring: all checks");
        else             $display("FAIL tb_scoring: %0d errors", errors);
        $finish;
    end
endmodule
