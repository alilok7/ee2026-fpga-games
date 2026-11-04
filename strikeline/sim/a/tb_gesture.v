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
    reg  [6:0] cx = 7'd30;
    reg  [5:0] cy = 6'd50;

    wire [5:0]  rd_addr, wp;
    wire [63:0] rd_data;
    wire [6:0]  n_s;
    wire grabbing, sdone, scancel, sshort, fbusy;
    wire [15:0] stance;
    wire [2:0]  lpow;
    wire [415:0] tbus;
    wire [31:0] tval;

    swipe_capture u_cap (
        .clk(clk), .rst(rst), .tick_sample(tick_sample), .tick_1ms(tick_1ms), .game_state(gs),
        .busy(fbusy), .delta_valid(dv), .delta_x(ddx), .delta_y(ddy), .l_press(lp), .l_release(lr),
        .r_press(rp), .cursor_x(cx), .cursor_y(cy), .rd_addr(rd_addr), .rd_data(rd_data), .wp(wp),
        .n_samples(n_s), .grabbing(grabbing), .swipe_done(sdone), .swipe_cancel(scancel),
        .too_short(sshort), .stance_x(stance), .live_power(lpow), .trail_bus(tbus), .trail_valid(tval));

    wire tv, rej;
    wire signed [15:0] tvy, tvx;
    wire signed [3:0]  tspin;
    wire [15:0] tx0;
    wire [7:0]  tmph;
    wire [1:0]  rmsg;
    wire [2:0]  alev;
    wire        aright;
    gesture_features u_feat (
        .clk(clk), .rst(rst), .start(sdone), .wp(wp), .n_samples(n_s), .stance_x(stance),
        .rd_addr(rd_addr), .rd_data(rd_data), .busy(fbusy), .throw_valid(tv), .throw_vy(tvy),
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
    reg signed [3:0] last_spin;
    reg signed [15:0] last_vx, last_vy;
    reg [7:0] last_mph;
    always @(posedge clk) begin
        if (tv) $display("      dbg n=%0d csum=%0d esum=%0d turn=%0d peak=%0d", u_feat.n, u_feat.csum, u_feat.esum, u_feat.dv_quo, u_feat.peak);
        if (tv)  begin got_throw <= 1; last_spin <= tspin; last_vx <= tvx; last_vy <= tvy; last_mph <= tmph; end
        if (rej) begin got_reject <= 1; last_msg <= rmsg; end
        if (scancel) got_cancel <= 1;
    end

    task swipe(input integer npk, input integer spd, input integer h0, input integer dh,
               input integer cancel_it);
        integer p, s;
        real h;
        begin
            got_throw = 0; got_reject = 0; got_cancel = 0;
            @(posedge clk) lp <= 1; @(posedge clk) lp <= 0;
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
