`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// tb_physics.v : B (ball) + C (pins, settle, split) together
//-----------------------------------------------------------------------------
// Owners : Students B and C
// One physics tick = 1500 clocks here (real: 97 656), still far more than
// B's scan + C's pair iterator need, so the schedule is the real one.
// Checks: ball phase FSM, gutter, hook distance, ball-pin momentum, pin
//         action + settle result, a ball that touches no pins, Spare
//         Challenge leaves, split detection, pins never stuck overlapping.
//=============================================================================
module tb_physics;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;

    integer cyc = 0;
    reg tick_phys = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        tick_phys <= (cyc % 1500 == 1499);
    end

    reg [`GS_W-1:0]  gs = `GS_AIM;
    reg [`SET_W-1:0] settings = `SET_DEFAULT;
    reg        tv = 0;
    reg signed [15:0] tvy = 0, tvx = 0;
    reg signed [3:0]  tspin = 0;
    reg [15:0] tx0 = `W_LANE_CX;
    reg        rack_go = 0;
    reg [1:0]  rack_cmd = `RK_FULL;
    reg [9:0]  rack_mask = 10'h3FF;

    wire [3:0]  ridx;
    wire [15:0] rx, ry;
    wire signed [15:0] rvx, rvy;
    wire        rsolid, rup, iv, sdone;
    wire [3:0]  ipin;
    wire signed [15:0] ivx, ivy, bvx, bvy;
    wire [15:0] bx, by;
    wire [2:0]  bph;
    wire signed [3:0] bspin;
    wire [15:0] bang, cpx, cpy;
    wire        cpulse;

    ball_physics u_ball (
        .clk(clk), .rst(rst), .tick_phys(tick_phys), .game_state(gs), .settings(settings),
        .stance_x(tx0), .throw_valid(tv), .throw_vy(tvy), .throw_vx(tvx), .throw_spin(tspin),
        .throw_x0(tx0), .pin_rd_idx(ridx), .pin_rd_x(rx), .pin_rd_y(ry), .pin_rd_vx(rvx),
        .pin_rd_vy(rvy), .pin_rd_solid(rsolid), .pin_rd_upright(rup), .impulse_valid(iv), .impulse_pin(ipin),
        .impulse_vx(ivx), .impulse_vy(ivy), .scan_done(sdone), .ball_x(bx), .ball_y(by),
        .ball_vx(bvx), .ball_vy(bvy), .ball_phase(bph), .ball_spin(bspin), .ball_angle(bang),
        .contact_pulse(cpulse), .contact_px(cpx), .contact_py(cpy));

    wire [239:0] vis;
    wire [9:0]   standing, pbusy, sbefore;
    wire         rbusy, force_s, settled, split;
    wire [9:0]   rake;
    wire [3:0]   ndown;

    pin_physics u_pins (
        .clk(clk), .rst(rst), .tick_phys(tick_phys), .scan_done(sdone), .impulse_valid(iv),
        .impulse_pin(ipin), .impulse_vx(ivx), .impulse_vy(ivy), .rack_go(rack_go),
        .rack_cmd(rack_cmd), .rack_mask(rack_mask), .force_settle(force_s), .pin_rd_idx(ridx),
        .pin_rd_x(rx), .pin_rd_y(ry), .pin_rd_vx(rvx), .pin_rd_vy(rvy), .pin_rd_solid(rsolid), .pin_rd_upright(rup),
        .pin_vis(vis), .standing(standing), .busy(pbusy), .rack_busy(rbusy), .rake_y(rake));

    pin_settle u_settle (
        .clk(clk), .rst(rst), .tick_phys(tick_phys), .throw_go(tv), .ball_phase(bph),
        .ball_y(by), .standing(standing), .busy(pbusy), .force_settle(force_s),
        .settle_done(settled), .pins_down_this_ball(ndown), .split_flag(split),
        .standing_before(sbefore));

    integer errors = 0;
    task check(input cond, input [8*56-1:0] msg);
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask

    // ---- watchers -----------------------------------------------------------
    reg seen_gutter, seen_hook, seen_roll, seen_skid;
    integer forced = 0;                          // settles that needed the 4 s timeout
    // ---- pin-pin momentum: every collision C computes (state S_PN) -------
    // equal masses, so vx_i + vx_j and vy_i + vy_j must not change, unless a
    // pin was only made to wobble (its base absorbs the push by design)
    integer pp_hits = 0, pp_bad = 0, sbx, sby, sax, say;
    always @(posedge clk) if (u_pins.st == 5'd22) begin          // S_PN
        @(posedge clk);                                          // nA/nB are now registered
        sbx = $signed(u_pins.rA[54:35]) + $signed(u_pins.rB[54:35]);
        sby = $signed(u_pins.rA[34:15]) + $signed(u_pins.rB[34:15]);
        sax = $signed(u_pins.nA[54:35]) + $signed(u_pins.nB[54:35]);
        say = $signed(u_pins.nA[34:15]) + $signed(u_pins.nB[34:15]);
        if (u_pins.nA[14:12] != `PS_WOBBLING && u_pins.nB[14:12] != `PS_WOBBLING) begin
            pp_hits = pp_hits + 1;
            if (sax - sbx > 2 || sbx - sax > 2 || say - sby > 2 || sby - say > 2) pp_bad = pp_bad + 1;
        end
    end
    always @(posedge clk) if (force_s) forced = forced + 1;
    reg [15:0] x_at_oil, x_at_deck;
    reg        oil_done, deck_done;
    always @(posedge clk) begin
        if (bph == `BP_GUTTER) seen_gutter <= 1;
        if (bph == `BP_HOOK)   seen_hook   <= 1;
        if (bph == `BP_ROLL)   seen_roll   <= 1;
        if (bph == `BP_SKID)   seen_skid   <= 1;
        if (!oil_done && by >= `W_OIL_S) begin oil_done <= 1; x_at_oil <= bx; end
        if (!deck_done && by >= 16'd45760) begin deck_done <= 1; x_at_deck <= bx; end  // 715 in
    end

    // ---- momentum at the first ball-pin impulse ------------------------------
    // ball mass 16 lb, pin 3.5 lb: 16 * dv_ball + 3.5 * dv_pin should be ~0
    reg        mom_done;
    reg signed [15:0] bvx0, bvy0, pre_vx, pre_vy;
    real mom_err, mom_ref;
    always @(posedge clk) begin
        if (!iv) begin bvx0 <= bvx; bvy0 <= bvy; end
    end
    always @(posedge clk) begin
        if (iv && !mom_done) begin
            mom_done <= 1;
            pre_vx = bvx0; pre_vy = bvy0;               // ball velocity before the hit
            repeat (4) @(posedge clk);                  // ball deflection lands 2 clocks later
            mom_err = 16.0 * (bvy - pre_vy) + 3.5 * ivy;
            mom_ref = 3.5 * ivy;
            $display("      impulse pin %0d dvp=(%0d,%0d)  ball dv=(%0d,%0d)", ipin, ivx, ivy,
                     bvx - pre_vx, bvy - pre_vy);
            check(mom_err < 0.06 * mom_ref && mom_err > -0.06 * mom_ref,
                  "ball-pin impulse conserves momentum (6 %)");
        end
    end

    // ---- overlap watchdog: two pins on the deck closer than 4.0 in (they
    //      should be pushed apart). Sampled every 16 ticks (it is slow in xsim).
    integer overlap_ticks = 0, worst_overlap = 0;
    integer a, b2, tcount = 0;
    integer ddx, ddy;
    reg any_ovl;
    always @(posedge clk) if (tick_phys) begin
        tcount = tcount + 1;
        if (tcount % 16 == 0) begin
            any_ovl = 0;
            for (a = 0; a < 10; a = a + 1)
                for (b2 = a + 1; b2 < 10; b2 = b2 + 1) begin
                    ddx = u_pins.rec[a][98:83]; ddx = ddx - u_pins.rec[b2][98:83];
                    ddy = u_pins.rec[a][76:61]; ddy = ddy - u_pins.rec[b2][76:61];
                    if (u_pins.rec[a][14:12] != `PS_OFF && u_pins.rec[b2][14:12] != `PS_OFF &&
                        ddx * ddx + ddy * ddy < 65536)          // (4.0 in * 64)^2
                        any_ovl = 1;
                end
            overlap_ticks = any_ovl ? overlap_ticks + 16 : 0;
            if (overlap_ticks > worst_overlap) worst_overlap = overlap_ticks;
        end
    end

    // ---- one throw ------------------------------------------------------------
    reg [3:0] res_down;
    reg [9:0] res_stand;
    reg       res_split;
    task throw(input real mph, input real vx_mph, input integer x0_in10, input integer spin);
        begin
            seen_gutter = 0; seen_hook = 0; seen_roll = 0; seen_skid = 0;
            oil_done = 1; deck_done = 1;               // re-armed after the release
            gs = `GS_AIM;
            tx0 = x0_in10 * 64 / 10;
            repeat (20) @(posedge clk);
            @(posedge clk) gs <= `GS_THROW;
            @(posedge clk);
            tvy  <= $rtoi(mph * 17.6 / 1024.0 * 4096.0);
            tvx  <= $rtoi(vx_mph * 17.6 / 1024.0 * 4096.0);
            tspin <= spin;
            tv <= 1;
            @(posedge clk) tv <= 0;
            @(posedge clk) gs <= `GS_ROLL;
            repeat (3) @(posedge clk);
            oil_done = 0; deck_done = 0;               // ball is back at the foul line now
            @(posedge settled);
            res_down = ndown; res_stand = standing; res_split = split;
            $display("      down=%0d standing=%b split=%0d x_oil=%0d x_deck=%0d (in/64)",
                     res_down, res_stand, res_split, x_at_oil, x_at_deck);
            repeat (10) @(posedge clk);
        end
    endtask

    task rack(input [1:0] c, input [9:0] m);
        begin
            @(posedge clk); rack_cmd <= c; rack_mask <= m; rack_go <= 1;
            @(posedge clk) rack_go <= 0;
            @(negedge rbusy);
            repeat (5) @(posedge clk);
        end
    endtask

    initial begin
        settings[`SET_LB_HI:`SET_LB_LO] = 2'd2;             // 16 lb
        mom_done = 1;
        repeat (5) @(posedge clk);
        rst <= 0;
        repeat (20) @(posedge clk);

        // 1. straight 17 mph ball at the head pin, with the momentum check
        mom_done = 0;
        throw(17.0, 0.0, 300, 0);
        check(seen_skid && !seen_gutter, "straight ball: SKID, no gutter");
        check(res_down >= 5, "straight ball at the head pin knocks >= 5 pins");
        check(res_down == 10 - (res_stand[0]+res_stand[1]+res_stand[2]+res_stand[3]+res_stand[4]+
              res_stand[5]+res_stand[6]+res_stand[7]+res_stand[8]+res_stand[9]),
              "pins_down_this_ball matches the standing mask");

        // 2. sweep the fallen pins (ball 2 keeps the leave)
        rack(`RK_SWEEP, 10'h000);
        check(standing == res_stand, "sweep keeps exactly the standing pins");

        // 3. gutter ball on the left
        rack(`RK_FULL, 10'h3FF);
        throw(15.0, -0.3, 140, 0);
        check(seen_gutter, "angled ball falls into the gutter");
        check(res_down == 0 && standing == 10'h3FF, "gutter ball touches no pins");

        // 4. gutter on the right
        throw(15.0, 0.3, 460, 0);
        check(seen_gutter && res_down == 0, "right gutter ball, 0 pins");

        // 5. hook: start right of centre, spin +4 (hook left)
        throw(16.0, 0.0, 420, 4);
        check(seen_hook && seen_roll, "spin ball goes SKID -> HOOK -> ROLL");
        $display("      hook moved %0d boards after the oil line", ($signed({1'b0,x_at_oil}) - $signed({1'b0,x_at_deck})) / 64);
        check(($signed({1'b0,x_at_oil}) - $signed({1'b0,x_at_deck})) >= 8*64 &&
              ($signed({1'b0,x_at_oil}) - $signed({1'b0,x_at_deck})) <= 14*64,
              "medium hook (spin 4) moves 8-14 boards on the dry lane");
        check(($signed({1'b0,x_at_oil}) - 2688) < 2*64 && ($signed({1'b0,x_at_oil}) - 2688) > -2*64,
              "in the oil the ball barely hooks (< 2 boards)");

        // 6. long oil hooks less
        rack(`RK_FULL, 10'h3FF);
        settings[`SET_OIL] = 1'b1;
        throw(16.0, 0.0, 420, 4);
        check(($signed({1'b0,x_at_oil}) - $signed({1'b0,x_at_deck})) < 8*64, "long oil: the same throw hooks less");
        settings[`SET_OIL] = 1'b0;

        // 7. ball that touches no pins (leave = 10 pin, ball down the middle-left)
        rack(`RK_LEAVE, 10'b10_0000_0000);
        check(standing == 10'b10_0000_0000, "LEAVE rack sets exactly pin 10");
        throw(16.0, 0.0, 250, 0);
        check(res_down == 0 && standing == 10'b10_0000_0000, "ball that misses every pin: 0 down, settles");

        // 8. 7-10 split leave, ball straight at the 7 pin
        rack(`RK_LEAVE, 10'b10_0100_0000);
        throw(16.0, 0.0, 120, 0);
        check(standing[6] == 0, "ball at the 7 pin knocks it down");
        check(standing[9] == 1, "...and cannot reach the 10 pin");

        // 9. split detection: rack 4-6 and 7-10 leaves directly
        rack(`RK_LEAVE, 10'b00_0010_1000);
        throw(15.0, 0.0, 300, 0);          // straight through the gap between 4 and 6
        check(res_down == 0 && res_split, "4-6 leave with pin 1 down is a split");
        rack(`RK_LEAVE, 10'b00_0001_1000);   // 4-5: adjacent
        throw(15.0, 0.0, 120, 0);           // left of everything... may hit 4
        check(!(res_stand == 10'b00_0001_1000 && res_split), "4-5 is not a split");

        // 10. full rack, slightly off-centre pocket ball with hook, then pins never lock
        rack(`RK_FULL, 10'h3FF);
        throw(17.0, 0.0, 360, 3);
        check(res_down >= 6, "pocket hook ball carries >= 6 pins");
        check(forced == 0, "every throw settled when the pins stopped (no 4 s timeout)");
        $display("      pin-pin collisions checked: %0d, momentum errors: %0d", pp_hits, pp_bad);
        check(pp_hits > 20 && pp_bad == 0, "pin-pin collisions conserve momentum");
        $display("      timeouts used: %0d", forced);
        check(worst_overlap < 2048, "pins never stay overlapping for 2 s");
        $display("      worst overlap run %0d ticks", worst_overlap);

        if (errors == 0) $display("PASS tb_physics: all checks");
        else             $display("FAIL tb_physics: %0d errors", errors);
        $finish;
    end
endmodule
