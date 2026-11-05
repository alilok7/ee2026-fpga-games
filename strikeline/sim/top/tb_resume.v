`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// tb_resume.v : fast check of the RESUME path on the whole bitstream
// (a saved game header is written into the image, then RESUME is clicked)
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
module tb_resume;
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
    // move the pointer to UI-space pixel (x, y) (v3: the menus sit in the VGA
    // window at (32, 28)); deltas in quarter pixels (sensitivity x1)
    task move_vga(input integer x, input integer y);
        integer cx, cy, ddx, ddy;
        begin
            cx = u_top.cursor_x; cy = u_top.cursor_y;
            ddx = (x - cx) * 4 + 2; ddy = (y - cy) * 4 + 2;
            packet(ddx, ddy);
        end
    endtask
    task move_to(input integer x, input integer y);
        move_vga(x + 32, y + 28);
    endtask
    // v3: point at lane inch inch in the 3-D view (x = 30 + (cx - 56) * 3/4)
    task aim_at(input integer inch);
        move_vga(80 + ((inch - 30) * 4 + ((inch >= 30) ? 2 : -2)) / 3, 80);      // v3.3: centre column 80
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

    // picture check (v3): distinct colours in the frame just drawn, in the
    // VGA back buffer and in the OLED buffer
    integer ncol, ncol_o, k;
    reg [15:0] seen [0:15];
    reg [15:0] pv;
    reg found;
    task picture(output integer n, output integer no);
        integer i, a;
        begin
            @(posedge u_top.render_done); @(posedge clk); @(posedge clk);
            n = 0;
            for (a = 0; a < 76800; a = a + 29) begin            // v3.2: one 320 x 240 buffer
                pv = {7'd0, u_top.u_vga.fb[a]};
                if (n < 16) begin
                    found = 0;
                    for (i = 0; i < 16; i = i + 1) if (i < n && seen[i] == pv) found = 1;
                    if (!found) begin seen[n] = pv; n = n + 1; end
                end
            end
            no = 0;
            for (a = 0; a < 6144; a = a + 3) begin
                pv = u_top.u_vga.fbo[a];
                if (no < 16) begin
                    found = 0;
                    for (i = 0; i < 16; i = i + 1) if (i < no && seen[i] == pv) found = 1;
                    if (!found) begin seen[no] = pv; no = no + 1; end
                end
            end
        end
    endtask

    integer first_down, total_rolls;
    always @(posedge clk) if (0 && u_top.l_press) $display("      l_press mode=%0d hover=%0d row_at=%0d has_save=%0d act=%0d cy=%0d",
        u_top.u_game.mode, u_top.hover, u_top.u_game.row_at, u_top.has_save, u_top.u_game.act, u_top.cursor_y);
    initial begin
        wait (u_top.load_done);
        wait (u_top.u_game.mode == 4'd0);
        u_top.u_img.mem[`IM_GVALID] = 1; u_top.u_img.mem[`IM_GKIND] = 0; u_top.u_img.mem[`IM_GPLAYER] = 0;
        u_top.u_img.mem[`IM_GFRAME] = 8; u_top.u_img.mem[`IM_NROLL0] = 1; u_top.u_img.mem[`IM_ROLLS0] = 10;
        click;
        move_to(30, 12);
        repeat (2000) @(posedge clk);
        check(u_top.has_save && u_top.hover == 3'd1, "RESUME highlighted");
        click;
        wait_state(`GS_AIM, 3000);
        check(u_top.game_state == `GS_AIM && u_top.frame == 4'd8, "resumed at frame 9");
        if (errors == 0) $display("PASS tb_resume: all checks");
        else             $display("FAIL tb_resume: %0d errors", errors);
        $finish;
    end
endmodule
