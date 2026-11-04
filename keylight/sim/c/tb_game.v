`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// tb_game.v : Student C's game engine, end to end, with a model player
//-----------------------------------------------------------------------------
// The testbench reads the same data/songs.mem as the hardware, works out
// every note's hit time itself, and "flips the switch" at exactly the right
// moment. One simulated ms = 200 clocks so a whole song runs in seconds.
// Scenario 1  Twinkle, Normal, perfect play: every note Perfect, score as
//             predicted by the multiplier rules, 100 %, grade S, notes are
//             drawn, the guide LED lights before the first note, and every
//             hit sends the right note to the sound engine.
// Scenario 2  pause mid-song freezes song time; leaving Play mid-song and
//             coming back restarts cleanly.
// Scenario 3  Mary, zero hits: every note Miss, 0 points, 0 %, grade D.
// Scenario 4  stray strikes between notes break the combo but cost nothing.
//=============================================================================
module tb_game;
    localparam TICK = 200;
    reg clk = 0, rst = 1, t1 = 0, tf = 0, paused = 0;
    reg [3:0]  mode = `KL_MODE_MENU;
    reg [2:0]  song = 3'd0;
    reg [12:0] strike = 0;
    wire [8:0]  caddr;
    wire [23:0] cdata;
    wire [15:0] px, led;
    wire ev_v, sfx_v, res_valid;
    wire [6:0] ev_n, acc;
    wire [1:0] ev_l;
    wire [3:0] sfx_i, sdp, sbl;
    wire [23:0] sg;
    wire [9:0] step_ms;
    wire [19:0] score;
    wire [8:0] np, ng, nm, mc;
    wire [2:0] grade;

    chart_reader u_chart (.clk(clk), .song_id(song), .sel_learn(1'b0), .game_addr(caddr),
        .learn_addr(9'd0), .chart_data(cdata), .my_addr(), .my_data(24'd0));
    game_top u_game (.clk(clk), .rst(rst), .tick_1ms(t1), .tick_frame(tf), .mode(mode),
        .difficulty(`KL_DIFF_NORMAL), .settings(`KL_SETTINGS_DEFAULT), .paused(paused),
        .key_strike(strike), .px_x(7'd30), .px_y(6'd40), .px_color(px),
        .chart_addr(caddr), .chart_data(cdata), .ev_valid(ev_v), .ev_note(ev_n), .ev_vel(ev_l),
        .sfx_valid(sfx_v), .sfx_id(sfx_i), .led_req(led), .seg_glyphs(sg), .seg_dp(sdp),
        .seg_blink(sbl), .step_ms(step_ms), .res_valid(res_valid), .res_score(score),
        .res_perfect(np), .res_good(ng), .res_miss(nm), .res_maxcombo(mc), .res_acc(acc),
        .res_grade(grade));

    always #5 clk = ~clk;
    integer cnt = 0, fcnt = 0;
    always @(posedge clk) begin
        cnt <= (cnt == TICK - 1) ? 0 : cnt + 1;
        t1  <= (cnt == TICK - 1);
        tf  <= (cnt == TICK - 1) && (fcnt == 0);
        if (cnt == TICK - 1) fcnt <= (fcnt == 15) ? 0 : fcnt + 1;
    end

    // ---- song model from the same ROM file ----
    reg [23:0] rom [0:2047];
    initial $readmemh("songs.mem", rom);
    integer n_ev, stepms, e, hit_t [0:511], lane_t [0:511], note_t [0:511];
    task load_song; input integer s;
        integer base;
        begin
            base   = s * 512;
            stepms = rom[base][23:14];
            n_ev   = rom[base][13:5];
            for (e = 0; e < n_ev; e = e + 1) begin
                note_t[e] = rom[base + 1 + e][23:17];
                hit_t[e]  = rom[base + 1 + e][16:6] * stepms + stepms * 32;
                case (note_t[e] - 60)
                    0, 1: lane_t[e] = 0;  2, 3: lane_t[e] = 1;  4: lane_t[e] = 2;
                    5, 6: lane_t[e] = 3;  7, 8: lane_t[e] = 4;  9, 10: lane_t[e] = 5;
                    11:   lane_t[e] = 6;  default: lane_t[e] = 7;
                endcase
            end
        end
    endtask
    function integer chrom; input integer l;
        case (l) 0: chrom = 0; 1: chrom = 2; 2: chrom = 4; 3: chrom = 5; 4: chrom = 7;
                 5: chrom = 9; 6: chrom = 11; default: chrom = 12; endcase
    endfunction

    // ---- monitors ----
    integer errors = 0, ev_count = 0, ev_wrong = 0, led_seen = 0, vis_seen = 0;
    integer expect_note_idx = 0;
    reg got_res;
    always @(posedge clk) begin
        if (res_valid) got_res <= 1'b1;
        if (u_game.r_vis != 0) vis_seen = 1;
    end
    task check; input cond; input [8*56-1:0] msg;
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask
    task strike_lane; input integer l;
        begin @(posedge clk) strike <= (13'd1 << chrom(l)); @(posedge clk) strike <= 0; end
    endtask
    task enter_play;
        begin
            mode = `KL_MODE_MENU; repeat (10) @(posedge clk);
            got_res = 0;
            mode = `KL_MODE_PLAY;
        end
    endtask

    integer expect_score, i, combo, t0;
    initial begin
        repeat (5) @(posedge clk); rst = 0;

        // ================= Scenario 1: perfect Twinkle =================
        song = 0; load_song(0);
        enter_play;
        for (e = 0; e < n_ev; e = e + 1) begin
            wait (u_game.song_ms == hit_t[e] - 60);          // LED should be glowing now
            if (e == 0) begin : ledwin
                integer c;
                for (c = 0; c < 2000; c = c + 1) begin
                    @(posedge clk); if (led[15 - lane_t[0]]) led_seen = led_seen + 1;
                end
            end
            wait (u_game.song_ms == hit_t[e] + 5);            // +5 ms debounce lag
            strike_lane(lane_t[e]);
            // the sound engine must receive this note
            fork : evwait
                begin wait (ev_v); if (ev_n != note_t[e]) ev_wrong = ev_wrong + 1;
                      ev_count = ev_count + 1; disable evwait; end
                begin repeat (TICK * 3) @(posedge clk); disable evwait; end
            join
        end
        wait (got_res);
        expect_score = 0;
        for (i = 1; i <= n_ev; i = i + 1)
            expect_score = expect_score + 100 * ((i >= 50) ? 4 : (i >= 30) ? 3 : (i >= 10) ? 2 : 1);
        check(np == n_ev && ng == 0 && nm == 0, "perfect play: every note judged Perfect");
        check(score == expect_score, "score matches the multiplier rules");
        check(mc == n_ev, "max combo = number of notes");
        check(acc == 100 && grade == `KL_GRADE_S, "accuracy 100 % and grade S");
        check(ev_count == n_ev && ev_wrong == 0, "each hit sends its note to the sound engine");
        check(led_seen > 0, "guide LED glows before the first note");
        check(vis_seen, "falling notes appear in the render snapshot");
        $display("     Twinkle: %0d notes, score %0d P %0d G %0d M %0d max %0d acc %0d", n_ev, score, np, ng, nm, mc, acc);

        // ================= Scenario 2: pause and abort =================
        enter_play;
        wait (u_game.song_ms == 3000);
        paused = 1; t0 = u_game.song_ms;
        repeat (TICK * 300) @(posedge clk);
        check(u_game.song_ms == t0, "pause freezes song time");
        paused = 0;
        repeat (TICK * 100) @(posedge clk);
        check(u_game.song_ms > t0, "unpause resumes song time");
        mode = `KL_MODE_MENU; repeat (10) @(posedge clk);
        check(u_game.song_ms == 0 && u_game.u_table.s_valid == 0, "leaving Play clears the engine");
        mode = `KL_MODE_PLAY;
        repeat (TICK * 50) @(posedge clk);
        check(u_game.song_ms > 0 && u_game.song_ms < 100, "re-entering Play restarts the song");

        // ================= Scenario 3: Mary with zero hits =================
        song = 1; load_song(1);
        enter_play;
        wait (got_res);
        $display("     Mary: %0d notes P %0d G %0d M %0d", n_ev, np, ng, nm);
        check(nm == n_ev && np == 0 && ng == 0, "zero hits: every note is a Miss");
        check(score == 0 && acc == 0 && grade == `KL_GRADE_D, "zero hits: 0 points, 0 %, grade D");

        // ================= Scenario 4: stray strikes =================
        song = 1; load_song(1);
        enter_play;
        for (e = 0; e < 12; e = e + 1) begin
            wait (u_game.song_ms == hit_t[e] + 5);
            strike_lane(lane_t[e]);
        end
        repeat (TICK * 2) @(posedge clk);
        check(u_game.combo == 12 && u_game.mult == 2, "12 hits -> combo 12, multiplier x2");
        t0 = u_game.score;
        // strike lane 7 (no C5 in Mary) -> stray
        strike_lane(7);
        repeat (TICK * 2) @(posedge clk);
        check(u_game.combo == 0 && u_game.score == t0, "stray strike: combo reset, no points lost");

        // ================= Scenario 5: judgement windows (Normal: 40 / 100 ms) =====
        song = 1; load_song(1);
        enter_play;
        wait (u_game.song_ms == hit_t[0] + 5 + 70);  strike_lane(lane_t[0]);   // 70 ms late
        wait (u_game.song_ms == hit_t[1] + 5 - 70);  strike_lane(lane_t[1]);   // 70 ms early
        wait (u_game.song_ms == hit_t[2] + 5 + 35);  strike_lane(lane_t[2]);   // 35 ms late
        wait (u_game.song_ms == hit_t[3] + 5 + 130); strike_lane(lane_t[3]);   // too late
        repeat (TICK * 3) @(posedge clk);
        check(u_game.n_good == 2 && u_game.n_perfect == 1, "+-70 ms -> Good, +35 ms -> Perfect");
        check(u_game.n_miss == 1 && u_game.combo == 0, "+130 ms -> Miss (and the strike is a stray)");

        if (errors == 0) $display("PASS tb_game: all checks");
        else             $display("FAIL tb_game: %0d errors", errors);
        $finish;
    end

    initial begin                                    // watchdog
        #(64'd400_000_000_0);
        $display("FAIL tb_game: timeout");
        $finish;
    end
endmodule
