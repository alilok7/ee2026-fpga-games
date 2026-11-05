`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// tb_gesture.v : swipe_capture + gesture_features against synthetic swipes
//-----------------------------------------------------------------------------
// Owner : Student A
// Time is compressed: one 200 Hz sample = 20 clocks, and MouseCtl's 40 Hz
// packets arrive every 5 samples, exactly the real ratio.
// A swipe is a list of per-packet velocity vectors (counts per 25 ms) with a
// speed and a heading that can turn by a fixed angle per packet (a curve).
//=============================================================================
module tb_gesture;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;

    reg  tick_sample = 0, tick_1ms = 0;
    reg  [`GS_W-1:0] gs = `GS_AIM;
    reg  dv = 0;
    reg  signed [11:0] ddx = 0, ddy = 0;
    reg  lp = 0, lr = 0, rp = 0;
    reg  [7:0] cx = 8'd30;
    reg  [6:0] cy = 7'd50;

    wire [6:0]  rd_addr, wp;
    wire [63:0] rd_data;
    wire [7:0]  n_s;
    wire grabbing, sdone, scancel, sshort, fbusy;
    wire [15:0] stance;
    wire [2:0]  lpow;
    wire [479:0] tbus;
    wire [6:0]  tgt;
    wire [31:0] tval;

    swipe_capture u_cap (
        .clk(clk), .rst(rst), .tick_sample(tick_sample), .tick_1ms(tick_1ms), .game_state(gs),
        .busy(fbusy), .delta_valid(dv), .delta_x(ddx), .delta_y(ddy), .l_press(lp), .l_release(lr),
        .r_press(rp), .nudge_l(1'b0), .nudge_r(1'b0), .cursor_x(cx), .cursor_y(cy), .aim_px(cx[6:0]), .grab_zone(1'b1), .wheel(4'sd0), .target_in(tgt), .rd_addr(rd_addr), .rd_data(rd_data), .wp(wp),
        .n_samples(n_s), .grabbing(grabbing), .swipe_done(sdone), .swipe_cancel(scancel),
        .too_short(sshort), .stance_x(stance), .live_power(lpow), .trail_bus(tbus), .trail_valid(tval));

    wire tv, rej;
    wire signed [15:0] tvy, tvx;
    wire signed [`SPIN_W-1:0] tspin;
    reg  [1:0] sens = 2'd0;
    wire [15:0] tx0;
    wire [7:0]  tmph;
    wire [1:0]  rmsg;
    wire [2:0]  alev;
    wire        aright;
    gesture_features u_feat (
        .clk(clk), .rst(rst), .start(sdone), .wp(wp), .n_samples(n_s), .stance_x(stance),
        .spin_sens(sens), .rd_addr(rd_addr), .rd_data(rd_data), .busy(fbusy), .throw_valid(tv), .throw_vy(tvy),
        .throw_vx(tvx), .throw_spin(tspin), .throw_x0(tx0), .throw_mph10(tmph), .reject(rej),
        .reject_msg(rmsg), .aim_level(alev), .aim_right(aright));

    // 200 Hz sample every 20 clocks
    integer cyc = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        tick_sample <= (cyc % 20 == 19);
    end

    integer errors = 0;
    task check(input cond, input [8*48-1:0] msg);
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask

    // ---- one swipe: npk packets, speed `spd` counts/packet, start heading
    //      h0 (milli-radians, 0 = straight forward, + = right), turn per
    //      packet `dh` (+ = clockwise = to the right)
    reg got_throw, got_reject, got_cancel;
    reg [1:0] last_msg;
    reg signed [`SPIN_W-1:0] last_spin;
    reg signed [15:0] last_vx, last_vy;
    reg [7:0] last_mph;
    always @(posedge clk) begin
        if (tv) $display("      dbg n=%0d area2=%0d L2=%0d turn256=%0d peak=%0d spin=%0d", u_feat.n, u_feat.csum, u_feat.l2, u_feat.dv_quo, u_feat.peak, tspin);
        if (tv)  begin got_throw <= 1; last_spin <= tspin; last_vx <= tvx; last_vy <= tvy; last_mph <= tmph; end
        if (rej) begin got_reject <= 1; last_msg <= rmsg; $display("      reject msg=%0d n=%0d js=%0d je=%0d peak=%0d dfs=%0d", rmsg, u_feat.n, u_feat.js, u_feat.je, u_feat.peak, u_feat.dfs_q); end
        if (scancel) got_cancel <= 1;
    end

    // tremor: packets of +-1..2 counts before and after the real swipe
    integer pre_jit = 0, post_jit = 0;
    task jitter(input integer k);
        integer p, s;
        begin
            for (p = 0; p < k; p = p + 1) begin
                for (s = 0; s < 5; s = s + 1) @(posedge tick_sample);
                @(posedge clk);
                ddx <= (p % 2) ? 12'sd1 : -12'sd1;
                ddy <= (p % 3 == 0) ? 12'sd1 : -12'sd1;
                dv  <= 1;
                @(posedge clk) dv <= 0;
            end
        end
    endtask

    task swipe(input integer npk, input integer spd, input integer h0, input integer dh,
               input integer cancel_it);
        integer p, s;
        real h;
        begin
            got_throw = 0; got_reject = 0; got_cancel = 0;
            @(posedge clk) lp <= 1; @(posedge clk) lp <= 0;
            jitter(pre_jit);
            h = h0 / 1000.0;
            for (p = 0; p < npk; p = p + 1) begin
                for (s = 0; s < 5; s = s + 1) @(posedge tick_sample);
                @(posedge clk);
                ddx <= $rtoi(spd * $sin(h));
                ddy <= -$rtoi(spd * $cos(h));          // forward = -y
                dv  <= 1;
                @(posedge clk) dv <= 0;
                h = h + dh / 1000.0;
                if (cancel_it && p == npk / 2) begin
                    @(posedge clk) rp <= 1; @(posedge clk) rp <= 0;
                end
            end
            jitter(post_jit);
            repeat (3) @(posedge tick_sample);
            @(posedge clk) lr <= 1; @(posedge clk) lr <= 0;
            repeat (3000) @(posedge clk);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst <= 0;
        repeat (50) @(posedge clk);

        // 1. straight forward flick
        swipe(10, 60, 0, 0, 0);
        check(got_throw, "straight swipe -> throw");
        check(last_spin == 0, "straight swipe -> no spin");
        check(last_vx == 0, "straight swipe -> no aim");
        check(last_mph >= 150 && last_mph <= 200, "60 counts/packet -> 15-20 mph");
        $display("      mph10=%0d vy=%0d", last_mph, last_vy);

        // 2. curving left (counter-clockwise): heading turns -0.12 rad/packet
        swipe(10, 60, 0, -120, 0);
        check(got_throw && last_spin > 0, "curve left -> positive spin (hook left)");
        $display("      spin=%0d", last_spin);

        // 3. gentle curve right
        swipe(10, 60, 0, 40, 0);
        check(got_throw && last_spin < 0, "curve right -> negative spin");
        $display("      spin=%0d", last_spin);

        // 4. angled 25 degrees right, straight line
        swipe(10, 60, 436, 0, 0);
        check(got_throw && last_vx > 0 && last_spin == 0, "angled right -> vx > 0, no spin");
        $display("      vx=%0d vy=%0d", last_vx, last_vy);

        // 5. 5 degrees right: inside the dead zone
        swipe(10, 60, 87, 0, 0);
        check(got_throw && last_vx == 0, "5 degree swipe -> dead zone, vx = 0");

        // 6. sideways
        swipe(10, 60, 1300, 0, 0);
        check(got_reject && last_msg == `GM_FORWARD, "sideways -> SWIPE FORWARD");

        // 7. backwards
        swipe(10, 60, 3141, 0, 0);
        check(got_reject && last_msg == `GM_FORWARD, "backwards -> SWIPE FORWARD");

        // 8. very slow
        swipe(10, 4, 0, 0, 0);
        check(got_reject && last_msg == `GM_FASTER, "slow swipe -> SWIPE FASTER");

        // 9. zero-length (press and release)
        got_throw = 0;
        @(posedge clk) lp <= 1; @(posedge clk) lp <= 0;
        @(posedge clk) lr <= 1; @(posedge clk) lr <= 0;
        repeat (500) @(posedge clk);
        check(!got_throw && !grabbing, "zero-length swipe -> nothing thrown");

        // 10. right click cancels
        swipe(10, 60, 0, 0, 1);
        check(got_cancel && !got_throw, "right click -> cancelled");

        // 11. very fast flick saturates at 22 mph
        swipe(6, 250, 0, 0, 0);
        check(got_throw && last_mph == 220, "huge flick -> capped at 22.0 mph");

        // ---- v3: spin from the whole curve ----------------------------
        // 13. more curve -> more spin, and even a gentle curve registers
        begin : t13
            integer s1, s2, s3, s4;
            swipe(10, 60, 0, 10, 0);  s1 = -last_spin;
            swipe(10, 60, 0, 20, 0);  s2 = -last_spin;
            swipe(10, 60, 0, 40, 0);  s3 = -last_spin;
            swipe(10, 60, 0, 60, 0);  s4 = -last_spin;
            $display("      spin for 10/20/40/60 mrad per packet: %0d %0d %0d %0d", s1, s2, s3, s4);
            check(s1 >= 1 && s1 < s2 && s2 < s3 && s3 < s4, "spin grows steadily with the curve (31 levels)");
        end
        // 14. mirror images give equal and opposite spin
        begin : t14
            integer a, b;
            swipe(10, 60, 0, 40, 0);  a = last_spin;
            swipe(10, 60, 0, -40, 0); b = last_spin;
            $display("      +curve %0d  -curve %0d", a, b);
            check(a == -b && a != 0, "mirrored swipes give mirrored spin");
        end
        // 15. hand tremor before and after the swipe does not change it
        begin : t15
            integer a, b;
            swipe(10, 60, 0, -40, 0); a = last_spin;
            pre_jit = 8; post_jit = 8;
            swipe(10, 60, 0, -40, 0); b = last_spin;
            pre_jit = 0; post_jit = 0;
            $display("      clean %0d  with tremor %0d", a, b);
            check(got_throw && (a - b <= 1) && (b - a <= 1), "tremor before / after the swipe is trimmed off");
        end
        // 16. the spin-sensitivity setting
        begin : t16
            integer a, b;
            swipe(10, 60, 0, -20, 0); a = last_spin;
            sens = 2'd1;
            swipe(10, 60, 0, -20, 0); b = last_spin;
            sens = 2'd0;
            $display("      normal %0d  high %0d", a, b);
            check(b > a && a > 0, "HIGH spin sensitivity gives more spin");
        end
        // 17. a straight swipe still gives exactly 0 (dead zone)
        swipe(10, 60, 0, 0, 0);
        check(got_throw && last_spin == 0, "straight swipe after curves -> spin 0");

        // 12. a grab is refused outside AIM
        gs = `GS_ROLL;
        @(posedge clk) lp <= 1; @(posedge clk) lp <= 0;
        repeat (5) @(posedge clk);
        check(!grabbing, "no grab while the ball is rolling");

        if (errors == 0) $display("PASS tb_gesture: all checks");
        else             $display("FAIL tb_gesture: %0d errors", errors);
        $finish;
    end
endmodule
