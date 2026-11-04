`timescale 1ns / 1ps
//=============================================================================
// tb_input_conditioner.v : self-checking test for Student B's input path
//-----------------------------------------------------------------------------
// One "ms" tick every 20 clocks keeps the run short; all timing in the DUT is
// counted in ticks, so the behaviour is identical to the real 1 kHz tick.
// Checks: bounce filtering, strike on BOTH flip directions, no strike at
// reset, short glitch ignored, chord of 13 keys, press / long / repeat,
// soft-reset combo fires once and needs a release to re-arm.
//=============================================================================
module tb_input_conditioner;
    reg clk = 0, rst = 1, tick = 0;
    reg [15:0] sw = 16'h8000;            // sw[15] already up at power-on
    reg [4:0]  btn = 5'b0;
    wire [12:0] key_strike, key_level;
    wire [2:0]  ctl;
    wire [4:0]  bl, bp, blong, brep;
    wire        soft;

    input_conditioner dut (.clk(clk), .rst(rst), .tick_1ms(tick), .sw(sw), .btn(btn),
        .key_strike(key_strike), .key_level(key_level), .ctl_level(ctl), .btn_level(bl),
        .btn_press(bp), .btn_long(blong), .btn_repeat(brep), .soft_reset_req(soft));

    always #5 clk = ~clk;
    integer tcnt = 0;
    always @(posedge clk) begin                 // 1 tick = 20 clocks
        tcnt <= (tcnt == 19) ? 0 : tcnt + 1;
        tick <= (tcnt == 19);
    end

    // pulse counters
    integer strikes [0:12];
    integer n_press, n_long, n_rep, n_soft, k, errors = 0;
    task clear_counts;
        begin
            for (k = 0; k < 13; k = k + 1) strikes[k] = 0;
            n_press = 0; n_long = 0; n_rep = 0; n_soft = 0;
        end
    endtask
    always @(posedge clk) begin
        for (k = 0; k < 13; k = k + 1) if (key_strike[k]) strikes[k] = strikes[k] + 1;
        if (bp[0] || bp[4]) n_press = n_press + 1;       // C or U
        if (blong[4]) n_long = n_long + 1;
        if (brep[4])  n_rep  = n_rep + 1;
        if (soft)     n_soft = n_soft + 1;
    end

    task ms; input integer n; begin repeat (n * 20) @(posedge clk); end endtask
    task check; input cond; input [8*48-1:0] msg;
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask

    initial begin
        clear_counts;
        ms(3); rst = 0; ms(20);
        check(strikes[0] == 0, "no strike for a switch already up at reset");

        // bouncy 1 -> 0 flip of sw[15] (C4)
        clear_counts;
        sw[15] = 0; ms(1); sw[15] = 1; ms(1); sw[15] = 0; ms(1); sw[15] = 1; ms(1);
        sw[15] = 0; ms(12);
        check(strikes[0] == 1, "bouncy flip down -> exactly one strike");
        check(key_level[0] == 0, "level follows the switch");

        // clean 0 -> 1 flip back
        clear_counts;
        sw[15] = 1; ms(12);
        check(strikes[0] == 1, "flip up also strikes (both directions)");

        // glitch shorter than the debounce time
        clear_counts;
        sw[14] = 1; ms(3); sw[14] = 0; ms(12);
        check(strikes[2] == 0, "3 ms glitch ignored");

        // black key mapping: sw[7] = C#4 = bit 1
        clear_counts;
        sw[7] = 1; ms(12);
        check(strikes[1] == 1 && strikes[0] == 0, "sw7 maps to C#4 (bit 1)");

        // chord: flip all 13 key switches at once
        clear_counts;
        sw[15:3] = ~sw[15:3]; ms(12);
        begin : chord
            integer ok; ok = 1;
            for (k = 0; k < 13; k = k + 1) if (strikes[k] != 1) ok = 0;
            check(ok, "13-key chord -> one strike per key");
        end

        // short press of C
        clear_counts;
        btn[0] = 1; ms(40); btn[0] = 0; ms(20);
        check(n_press == 1 && n_long == 0, "short press: one press, no long press");

        // hold U for 1500 ms: long press once, repeat from 400 ms every 100 ms
        clear_counts;
        btn[4] = 1; ms(1510); btn[4] = 0; ms(20);
        check(n_press == 1 && n_long == 1, "hold 1.5 s: one press and one long press");
        check(n_rep >= 11 && n_rep <= 12, "auto-repeat at 400 ms then every 100 ms");

        // soft reset combo
        clear_counts;
        btn[4] = 1; btn[3] = 1; ms(2100);
        check(n_soft == 1, "U+D for 2 s -> one soft reset");
        ms(2500);
        check(n_soft == 1, "still held -> no second reset until released");
        btn[4] = 0; btn[3] = 0; ms(30);
        btn[4] = 1; btn[3] = 1; ms(2100);
        check(n_soft == 2, "released and held again -> re-armed");

        if (errors == 0) $display("PASS tb_input_conditioner: all checks");
        else             $display("FAIL tb_input_conditioner: %0d errors", errors);
        $finish;
    end
endmodule
