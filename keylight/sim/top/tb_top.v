`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// tb_top.v : whole-chip test of My_Top_Module, including the real
//            Oled_Display, to PROVE the video pipeline timing
//-----------------------------------------------------------------------------
// 1. Wait for the OLED's power-up sequence to finish (~140 ms of real time).
// 2. Long-press D on the title screen -> colour-bar self test.
// 3. For EVERY pixel of one whole frame, at the exact edge where
//    Oled_Display latches pixel_data, check it equals the colour bar for
//    that pixel_index. This proves pixel_index -> pixel_xy -> renderer ->
//    mux_video settles in time (docs/INTERFACES.md, "Pixel timing").
// 4. Back to the title, then C -> menu: the menu frame contains white text
//    and the 7-seg shows "PLAY".
// The 1 ms tick is shortened (MS_DIV = 1000) so button timing is quick;
// the OLED still runs at its real 6.25 MHz.
//=============================================================================
module tb_top;
    reg clk = 0;
    reg [15:0] sw = 16'h0000;
    reg [4:0] btns = 5'b0;                       // {U, D, L, R, C}
    wire btnU = btns[4], btnD = btns[3], btnL = btns[2], btnR = btns[1], btnC = btns[0];
    wire [15:0] led;
    wire [6:0] seg;
    wire dp;
    wire [3:0] an;
    wire [7:0] JC;
    wire [3:0] JA;

    My_Top_Module dut (.clk(clk), .sw(sw), .btnU(btnU), .btnD(btnD), .btnL(btnL),
        .btnR(btnR), .btnC(btnC), .led(led), .seg(seg), .dp(dp), .an(an), .JC(JC), .JA(JA));
    defparam dut.u_time.MS_DIV       = 1000;
    defparam dut.u_reset.HOLD_CYCLES = 200;

    always #5 clk = ~clk;
    localparam MS = 1000;                                // clocks per (fast) ms

    function [15:0] bar; input integer x;
        case (x / 12)
            0: bar = 16'hF800; 1: bar = 16'hFD20; 2: bar = 16'hFFE0; 3: bar = 16'h07E0;
            4: bar = 16'h07FF; 5: bar = 16'h2B3F; 6: bar = 16'hA1FF; default: bar = 16'hFB56;
        endcase
    endfunction

    integer errors = 0, checked = 0, bad = 0, white = 0;
    reg checking_bars = 0, counting_white = 0;
    always @(negedge dut.clk6p25m) begin
        if (dut.u_oled.sample_pixel && dut.u_oled.state != 5'b10001) begin   // not the very first
            if (checking_bars) begin
                checked = checked + 1;
                if (dut.oled_data !== bar(dut.pixel_index % 96)) begin
                    bad = bad + 1;
                    if (bad < 4) $display("     mismatch idx %0d: %h vs %h",
                                          dut.pixel_index, dut.oled_data, bar(dut.pixel_index % 96));
                end
            end
            if (counting_white && dut.oled_data == 16'hFFFF) white = white + 1;
        end
    end

    task check; input cond; input [8*56-1:0] msg;
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask
    // (a task's inout argument is only copied back when the task ends, so
    //  buttons are driven through the btns vector by index instead)
    task hold; input integer b; input integer ms_n;
        begin btns[b] = 1'b1; repeat (ms_n * MS) @(posedge clk); btns[b] = 1'b0;
              repeat (30 * MS) @(posedge clk); end
    endtask
    task next_frame; begin @(posedge dut.oled_sending); end endtask

    initial begin
        wait (dut.oled_sending == 1'b1);
        $display("     OLED started streaming at %0t ns", $time);
        check(dut.mode == `KL_MODE_TITLE, "power-on lands on the title screen");

        hold(3, 1100);
        check(dut.mode == `KL_MODE_TEST, "long D on title -> colour-bar self test");

        next_frame; next_frame;
        checking_bars = 1; next_frame; checking_bars = 0;
        check(checked >= 6143 && bad == 0, "every pixel of a frame latched with the right colour");
        $display("     checked %0d pixels, %0d wrong", checked, bad);

        hold(0, 40);
        check(dut.mode == `KL_MODE_TITLE, "C leaves the self test");
        hold(0, 40);
        check(dut.mode == `KL_MODE_MENU, "C on title -> menu");
        next_frame; counting_white = 1; next_frame; counting_white = 0;
        check(white > 50, "menu frame contains white text pixels");
        check(dut.seg_glyphs == {6'd25, 6'd21, 6'd10, 6'd34}, "7-seg request shows PLAY");

        sw[1] = 1; repeat (30 * MS) @(posedge clk);
        check(led[1] == 1'b1, "mute switch lights led[1]");

        if (errors == 0) $display("PASS tb_top: all checks");
        else             $display("FAIL tb_top: %0d errors", errors);
        $finish;
    end
endmodule
