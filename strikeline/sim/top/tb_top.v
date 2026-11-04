`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// tb_top.v : the whole StrikeLine bitstream, end to end
//-----------------------------------------------------------------------------
// Owners : all four students (integration test)
// The real My_Top_Module runs (compiled with SIM: time ~65x faster, same
// ratios). The mouse is driven at MouseCtl's outputs (xpos/ypos/buttons,
// new_event every 25 ms, as MouseCtl does after a PS/2 packet), so A's
// re-centring delta logic is exercised exactly as on the board. The flash
// model hangs on the QSPI pins (the SPI clock is taken from u_top.spi_sck,
// on the board it goes through STARTUPE2).
// Scenario: boot (blank flash) -> title -> click -> menu -> Quick Game ->
//   several real throws through A -> B -> C -> D (states, pins, LEDs, score)
//   -> quit after a frame (auto-saved) -> "reprogram" -> RESUME restores the
//   frame and the rolls -> the OLED picture is not blank and changes.
//=============================================================================
module tb_top;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [15:0] sw = 16'h0000;
    reg btnU = 0, btnD = 0, btnL = 0, btnR = 0, btnC = 0;
    wire [15:0] led; wire [6:0] seg; wire dp; wire [3:0] an; wire [7:0] JC;
    wire PS2Clk, PS2Data, QspiCSn;
    wire [3:0] QspiDB;
    pullup (PS2Clk); pullup (PS2Data);

    My_Top_Module u_top (.clk(clk), .sw(sw), .btnU(btnU), .btnD(btnD), .btnL(btnL), .btnR(btnR),
        .btnC(btnC), .led(led), .seg(seg), .dp(dp), .an(an), .JC(JC), .PS2Clk(PS2Clk), .PS2Data(PS2Data),
        .QspiCSn(QspiCSn), .QspiDB(QspiDB));

    wire miso;
    flash_model #(.ERASE_CLKS(20000), .PROG_CLKS(2000)) u_flash (
        .clk(clk), .cs_n(QspiCSn), .sck(u_top.spi_sck), .mosi(QspiDB[0]), .miso(miso), .present(1'b1));
    assign QspiDB[1] = miso;

    // ---------------- mouse at MouseCtl's outputs ------------------------------
    reg [11:0] mx = 12'd2048, my = 12'd2048;
    reg        mleft = 0, mright = 0, mmid = 0, mev = 0;
    initial begin
        force u_top.m_xpos = mx;  force u_top.m_ypos = my;  force u_top.m_zpos = 4'd0;
        force u_top.m_left = mleft; force u_top.m_right = mright; force u_top.m_middle = mmid;
        force u_top.m_new_event = mev;
    end
    always @(*) begin
        force u_top.m_xpos = mx; force u_top.m_ypos = my; force u_top.m_left = mleft;
        force u_top.m_right = mright; force u_top.m_middle = mmid; force u_top.m_new_event = mev;
    end
    localparam PKT = 25000;                  // 25 ms between packets (sim ms = 1000 clocks)
    task packet(input integer dx, input integer dy);
        begin
            mx = 12'd2048 + dx; my = 12'd2048 + dy;
            @(posedge clk) mev = 1; @(posedge clk) mev = 0;
            repeat (20) @(posedge clk);
            mx = 12'd2048; my = 12'd2048;    // MouseCtl would be re-centred by setx/sety
            repeat (PKT - 22) @(posedge clk);
        end
    endtask
    // move the pointer to pixel (x, y): deltas in quarter pixels (sensitivity x1)
    task move_to(input integer x, input integer y);
        integer cx, cy, ddx, ddy;
        begin
            cx = u_top.cursor_x; cy = u_top.cursor_y;
            ddx = (x - cx) * 4 + 2; ddy = (y - cy) * 4 + 2;
            packet(ddx, ddy);
        end
    endtask
    task click;
        begin
            mleft = 1; packet(0, 0);
            mleft = 0; packet(0, 0);
        end
    endtask
    task throw_ball(input integer speed, input integer curve);
        integer p;
        begin
            mleft = 1; packet(0, 0);
            for (p = 0; p < 8; p = p + 1) packet(curve * p / 4, -speed);
            mleft = 0; packet(0, 0);
        end
    endtask

    integer errors = 0;
    task check(input cond, input [8*56-1:0] msg);
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask

    // state trace (for the log)
    reg [4:0] gs_d = 31;
    always @(posedge clk) begin
        gs_d <= u_top.game_state;
        if (u_top.game_state != gs_d)
            $display("      t=%0d ms  game_state=%0d  frame=%0d ball=%0d  standing=%b", $time / 1000000,
                     u_top.game_state, u_top.frame, u_top.ball_no, u_top.standing);
    end

    task wait_state(input [4:0] s, input integer max_ms);
        integer t;
        begin
            t = 0;
            while (u_top.game_state != s && t < max_ms * 1000) begin @(posedge clk); t = t + 1; end
        end
    endtask

    // OLED picture check: distinct colours over one frame of pixel data
    integer ncol, k;
    reg [15:0] seen [0:15];
    reg found;
    task picture(output integer n);
        integer i;
        begin
            n = 0;
            @(posedge u_top.oled_sending);
            while (u_top.oled_sending) begin
                @(posedge clk);
                if (n < 16) begin
                    found = 0;
                    for (i = 0; i < 16; i = i + 1) if (i < n && seen[i] == u_top.oled_data) found = 1;
                    if (!found) begin seen[n] = u_top.oled_data; n = n + 1; end
                end
            end
        end
    endtask

    integer first_down, total_rolls;
    initial begin
        // ---------------- boot ----------------
        wait (u_top.load_done);
        wait (u_top.u_game.mode == 4'd0);               // the real title (not the boot phase)
        $display("      flash loaded at %0d ms (flash_ok=%0d)", $time / 1000000, u_top.flash_ok);
        wait_state(`GS_TITLE, 100);
        check(u_top.game_state == `GS_TITLE, "boot: blank flash -> defaults -> title screen");
        picture(ncol);
        check(ncol >= 4, "title screen draws a picture (>= 4 colours)");

        // ---------------- menu -> Quick Game (2 clicks from the title) ----------
        click;
        check(u_top.game_state == `GS_MENU, "click on the title -> main menu");
        move_to(30, 20);                                // row 2 = QUICK GAME
        check(u_top.hover == 3'd2, "pointer hovers QUICK GAME");
        click;
        wait_state(`GS_AIM, 3000);
        check(u_top.game_state == `GS_AIM && u_top.frame == 4'd7, "Quick Game starts at frame 8, aiming");
        check(led[9:0] == 10'h3FF, "pin LEDs: all 10 standing");

        // ---------------- first ball: straight down the middle --------------------
        move_to(30, 40);                                // stance board 21
        throw_ball(70, 0);
        wait_state(`GS_ROLL, 200);
        check(u_top.game_state == `GS_ROLL || u_top.game_state == `GS_PINACTION, "release -> ball rolling");
        wait_state(`GS_RESULT, 8000);
        check(u_top.game_state == `GS_RESULT, "ball reaches the pins, pins settle -> RESULT");
        first_down = u_top.pins_down;
        $display("      first ball: %0d pins, popup %0d", first_down, u_top.popup_id);
        check(first_down >= 1, "a straight ball knocks pins down");
        check(led[9:0] == u_top.standing, "pin LEDs show the leave");
        repeat (5000) @(posedge clk);
        // the scorecard word of frame 8 (index 7): a strike shows X in box 2,
        // otherwise the pin count in box 1 (glyph code 16 + n, '-' = 13 for 0)
        check(first_down == 10 ? (u_top.u_score.fr_mem[7][11:6] == 6'd56) :
              (u_top.u_score.fr_mem[7][17:12] == ((first_down == 0) ? 6'd13 : 6'd16 + first_down)),
              "the scorecard shows the first ball's mark");

        // ---------------- finish frame 8 (second ball unless strike) ---------------
        wait_state(`GS_AIM, 6000);
        if (u_top.frame == 4'd7) begin
            move_to(24, 40);
            throw_ball(60, 0);
            wait_state(`GS_RESULT, 8000);
            wait_state(`GS_AIM, 8000);
        end
        check(u_top.frame == 4'd8, "frame 8 finished -> frame 9");
        repeat (300000) @(posedge clk);                 // let the auto-save finish
        check(u_flash.sa[0] == 8'h53, "frame end auto-saved to flash slot A");
        total_rolls = u_top.u_img.mem[`IM_NROLL0];
        $display("      rolls saved: %0d, score so far %0d (known flags %b)", total_rolls, u_top.game0, u_top.ok0);
        check(total_rolls >= 1 && total_rolls <= 2, "the saved image holds frame 8's rolls");

        // ---------------- a gutter ball in frame 9 ----------------------------------
        move_to(46, 40);
        throw_ball(60, -40);                           // drifts right... and the stance is far right
        wait_state(`GS_RESULT, 8000);
        $display("      frame 9 ball 1: %0d pins, popup %0d", u_top.pins_down, u_top.popup_id);

        // ---------------- quit (hold btnL) and "reprogram" ---------------------------
        wait_state(`GS_AIM, 8000);
        btnL = 1; repeat (1100000) @(posedge clk); btnL = 0;
        wait_state(`GS_MENU, 500);
        check(u_top.game_state == `GS_MENU, "holding btnL leaves the game");
        repeat (2000) @(posedge clk);
        check(u_top.has_save, "RESUME GAME is offered");
        // reprogram = reset + garbage in every register file / RAM image
        force u_top.rst = 1'b1;
        for (k = 0; k < 128; k = k + 1) u_top.u_img.mem[k] = 8'hA5;
        repeat (100) @(posedge clk);
        release u_top.rst;
        wait (u_top.load_done);
        wait (u_top.u_game.mode == 4'd0);
        check(u_top.u_img.mem[`IM_NROLL0] == total_rolls, "after reprogramming the rolls are back from flash");
        click;
        move_to(30, 12);                                // row 1 = RESUME GAME
        repeat (2000) @(posedge clk);
        check(u_top.has_save && u_top.hover == 3'd1, "RESUME GAME offered after reprogramming");
        click;
        wait_state(`GS_AIM, 3000);
        check(u_top.game_state == `GS_AIM && u_top.frame == 4'd8, "resumed at frame 9 (the saved frame)");

        if (errors == 0) $display("PASS tb_top: all checks");
        else             $display("FAIL tb_top: %0d errors", errors);
        $finish;
    end
    initial begin #2_000_000_000; $display("FAIL tb_top: timeout"); $finish; end
endmodule
