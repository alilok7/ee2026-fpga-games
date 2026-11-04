`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// tb_screens.v : screenshots of the real OLED output (for review and the report)
//-----------------------------------------------------------------------------
// Owners : all (integration). Each screen is one OLED frame captured exactly
// as Oled_Display samples it (pixel_data at every sample_pixel), written to
// sim/run/tb_screens/screen_<name>.txt as 6144 hex RGB565 values.
// tools/screens_to_png.py turns them into PNG files (x4 scale).
//=============================================================================
module tb_screens;
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

    reg [11:0] mx = 12'd2048, my = 12'd2048;
    reg        mleft = 0, mright = 0, mmid = 0, mev = 0;
    always @(*) begin
        force u_top.m_xpos = mx; force u_top.m_ypos = my; force u_top.m_zpos = 4'd0;
        force u_top.m_left = mleft; force u_top.m_right = mright; force u_top.m_middle = mmid;
        force u_top.m_new_event = mev;
    end
    task packet(input integer dx, input integer dy);
        begin
            mx = 12'd2048 + dx; my = 12'd2048 + dy;
            @(posedge clk) mev = 1; @(posedge clk) mev = 0;
            repeat (20) @(posedge clk);
            mx = 12'd2048; my = 12'd2048;
            repeat (24978) @(posedge clk);
        end
    endtask
    task move_to(input integer x, input integer y);
        begin packet((x - u_top.cursor_x) * 4 + 2, (y - u_top.cursor_y) * 4 + 2); end
    endtask
    task click; begin mleft = 1; packet(0, 0); mleft = 0; packet(0, 0); end endtask
    task rclick; begin mright = 1; packet(0, 0); mright = 0; packet(0, 0); end endtask
    task throw_ball(input integer speed, input integer curve);
        integer p;
        begin
            mleft = 1; packet(0, 0);
            for (p = 0; p < 8; p = p + 1) packet(curve * p / 4, -speed);
            mleft = 0; packet(0, 0);
        end
    endtask
    task wait_state(input [4:0] s, input integer max_ms);
        integer t;
        begin t = 0; while (u_top.game_state != s && t < max_ms * 1000) begin @(posedge clk); t = t + 1; end end
    endtask

    // capture one frame: the colour of every pixel index, taken half way
    // through the time that index is held (well after the compositor captured it)
    integer fd, n;
    reg [15:0] fb [0:6143];
    task shot(input [8*16-1:0] name);
        reg [8*64-1:0] fname;
        begin
            @(negedge u_top.oled_sending);
            @(posedge u_top.oled_sending);
            while (u_top.oled_sending) begin
                @(posedge u_top.clk6p25m);
                if (u_top.u_oled.frame_counter[3:0] == 4'd8) fb[u_top.pixel_index] = u_top.oled_data;
            end
            $sformat(fname, "screen_%0s.txt", name);
            fd = $fopen(fname, "w");
            for (n = 0; n < 6144; n = n + 1) $fwrite(fd, "%04h%c", fb[n], 8'd10);
            $fclose(fd);
            $display("PASS screenshot %0s", name);
        end
    endtask

    // In simulation the OLED still runs at its real 60 Hz while the game runs
    // ~65x faster, so a capture (up to 2 frames) would see seconds of play.
    // freeze() stops the physics, the swipe timeout and the popup timer while
    // a frame is captured; the camera is placed where the player would see it.
    task freeze(input integer cam);
        begin
            force u_top.tick_phys = 1'b0;
            force u_top.u_swipe.hold_samples = 10'd0;
            force u_top.u_turn.ms = 12'd200;
            if (cam > -100) force u_top.u_cam.cam_y = cam;
            if (cam > -100 && cam < 690) force u_top.u_cam.cam_fp = cam - 26;   // first person: 40 in behind the ball
        end
    endtask
    task thaw;
        begin
            release u_top.tick_phys; release u_top.u_swipe.hold_samples;
            release u_top.u_turn.ms; release u_top.u_cam.cam_y; release u_top.u_cam.cam_fp;
        end
    endtask

    initial begin
        force u_top.u_comp.fade = 4'd8;              // no fade-in in screenshots
        wait (u_top.load_done);
        wait (u_top.u_game.mode == 4'd0);
        repeat (200000) @(posedge clk);
        shot("title");
        click;  move_to(30, 20);  repeat (100000) @(posedge clk);
        shot("menu");
        move_to(30, 52); click;  repeat (100000) @(posedge clk);   // SETTINGS
        move_to(30, 28); click;  repeat (100000) @(posedge clk);   // ball weight -> 16 lb
        shot("settings");
        rclick; move_to(30, 44); click; repeat (100000) @(posedge clk); // HIGH SCORES
        shot("scores");
        rclick; move_to(30, 60); click; repeat (100000) @(posedge clk); // HELP
        shot("help");
        click; move_to(30, 36); click; repeat (100000) @(posedge clk);  // PRACTICE
        move_to(30, 36); repeat (100000) @(posedge clk);
        shot("practice");
        rclick; move_to(30, 20); click;                                 // QUICK GAME
        wait_state(`GS_AIM, 4000); move_to(40, 40); repeat (100000) @(posedge clk);
        freeze(-1000); shot("aim"); thaw;
        // a hook swipe: curving to the left
        mleft = 1; packet(0, 0); packet(0, -60); packet(-4, -60); packet(-10, -60);
        freeze(-1000); shot("swipe"); thaw;
        packet(-16, -60); packet(-24, -60); mleft = 0; packet(0, 0);
        wait_state(`GS_ROLL, 200); repeat (600 * 1500) @(posedge clk);
        freeze((u_top.ball_y >> 6) - 14); shot("roll"); thaw;
        wait_state(`GS_PINACTION, 6000); repeat (120 * 1500) @(posedge clk);
        freeze(700); shot("pins"); thaw;
        wait_state(`GS_RESULT, 8000); repeat (2000) @(posedge clk);
        freeze(700); shot("result"); thaw;
        wait_state(`GS_AIM, 8000); repeat (2000) @(posedge clk);
        force u_top.u_game.card_show = 1'b1;
        freeze(-1000); shot("card"); thaw;
        release u_top.u_game.card_show;
        sw[1] = 1; sw[2] = 1; repeat (20000) @(posedge clk);
        mleft = 1; packet(0, 0); packet(0, -70); packet(0, -70); packet(0, -70); packet(0, -70); mleft = 0; packet(0, 0);
        wait_state(`GS_PINACTION, 6000); repeat (40 * 1500) @(posedge clk);
        freeze(700); shot("debug"); thaw;
        // Swipe Lab: leave the game (hold btnL), PRACTICE -> SWIPE LAB, one curved swipe
        sw[1] = 0; sw[2] = 0;
        btnL = 1; repeat (1100000) @(posedge clk); btnL = 0;
        wait_state(`GS_MENU, 500); move_to(30, 36); click;         // PRACTICE
        repeat (50000) @(posedge clk); move_to(30, 20); click;     // SWIPE LAB
        wait_state(`GS_PRACTICE_SWIPE, 500);
        mleft = 1; packet(0, 0); packet(0, -60); packet(-6, -60); packet(-14, -60); packet(-24, -55);
        packet(-34, -50); mleft = 0; packet(0, 0); repeat (20000) @(posedge clk);
        freeze(-1000); shot("lab"); thaw;
        $display("PASS tb_screens: done");
        $finish;
    end
    initial begin #2_000_000_000; #1_000_000_000; $display("FAIL tb_screens: timeout"); $finish; end
endmodule
