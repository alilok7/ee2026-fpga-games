`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// tb_flash.v : flash_ctrl + persist_ctrl + save_image against flash_model
//-----------------------------------------------------------------------------
// Owner : Student D
// "Reprogramming the FPGA" = reset the design AND scramble the image RAM.
// The settings word is used as the payload that must survive.
//=============================================================================
module tb_flash;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst = 1;

    reg  save_req = 0, c_set = 0;
    reg  [15:0] set_v = 0;
    wire pbusy, cdef;
    wire pwe, fwe; wire [6:0] pwa, fwa, pra, fra; wire [7:0] pwd, fwd, prd, frd, trd;
    reg  [6:0] tra = 0;
    wire load_done, flash_ok, saving, save_err, cs_n, sck, mosi, miso;
    reg  present = 1;

    persist_ctrl u_p (
        .clk(clk), .rst(rst), .c_roll(1'b0), .roll_p(1'b0), .roll_idx(5'd0), .roll_val(4'd0),
        .c_hdr(1'b0), .hdr_valid(1'b0), .hdr_kind(3'd0), .hdr_player(1'b0), .hdr_frame(4'd0),
        .c_clear(1'b0), .c_strike(1'b0), .c_spare(1'b0), .c_gameend(1'b0), .c_insert(1'b0),
        .ins_quick(1'b0), .ins_score(9'd0), .ins_name(15'd0), .c_settings(c_set), .set_value(set_v),
        .c_defaults(cdef), .gend_full(1'b0), .gend_score(9'd0),
        .we(pwe), .wa(pwa), .wd(pwd), .ra(pra), .rd(prd), .busy(pbusy));
    save_image u_img (
        .clk(clk), .we_flash(fwe), .wa_flash(fwa), .wd_flash(fwd), .we_game(pwe), .wa_game(pwa),
        .wd_game(pwd), .ra0(fra), .ra1(pra), .ra2(tra), .ra3(7'd0), .ra4(7'd0), .ra5(7'd0), .ra6(7'd0),
        .rd0(frd), .rd1(prd), .rd2(trd), .rd3(), .rd4(), .rd5(), .rd6());
    flash_ctrl #(.POLL_TIMEOUT(32'd200000)) u_f (
        .clk(clk), .rst(rst), .save_req(save_req), .persist_busy(pbusy), .ra(fra), .rd(frd),
        .we(fwe), .wa(fwa), .wd(fwd), .c_defaults(cdef), .load_done(load_done), .flash_ok(flash_ok),
        .saving(saving), .save_error(save_err), .cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(miso));
    flash_model u_m (.clk(clk), .cs_n(cs_n), .sck(sck), .mosi(mosi), .miso(miso), .present(present));

    integer errors = 0;
    task check(input cond, input [8*56-1:0] msg);
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask

    function [15:0] img_set; input dummy;
        begin img_set = {u_img.mem[`IM_SET_HI], u_img.mem[`IM_SET_LO]}; end
    endfunction

    // "reprogram": reset + garbage in the image RAM, then wait for the boot load
    task reprogram;
        integer i;
        begin
            rst <= 1;
            repeat (5) @(posedge clk);
            for (i = 0; i < 128; i = i + 1) u_img.mem[i] = 8'hA5;
            rst <= 0;
            @(posedge load_done);
            repeat (20) @(posedge clk);
            while (pbusy) @(posedge clk);
        end
    endtask

    task set_and_save(input [15:0] v);
        begin
            @(posedge clk) c_set <= 1; set_v <= v; @(posedge clk) c_set <= 0;
            @(posedge clk) save_req <= 1; @(posedge clk) save_req <= 0;
            @(posedge saving);
        end
    endtask

    initial begin
        repeat (5) @(posedge clk);
        rst <= 0;
        @(posedge load_done);
        repeat (300) @(posedge clk);
        check(flash_ok, "RDID answered: flash present, not protected");
        check(img_set(0) == `SET_DEFAULT && u_img.mem[0] == 8'h53, "blank flash -> factory defaults");

        // 1. first save -> slot A, sequence 1
        set_and_save(16'h1234);
        @(negedge saving);
        check(!save_err, "save 1 verified");
        check(u_m.sa[0] == 8'h53 && u_m.sa[3] == 8'd1 && u_m.sa[5] == 8'h34, "slot A holds the image, seq 1");

        // 2. reprogram -> restored
        reprogram;
        check(img_set(0) == 16'h1234, "after reprogramming: settings restored from A");

        // 3. second save goes to the OTHER slot
        set_and_save(16'h5678);
        @(negedge saving);
        check(u_m.sb[3] == 8'd2 && u_m.sa[3] == 8'd1, "save 2 -> slot B (seq 2), A untouched");
        reprogram;
        check(img_set(0) == 16'h5678, "newest slot (B) wins");

        // 4. power loss during the erase of the next save (target A)
        set_and_save(16'h9ABC);
        wait (u_m.pending_kind == 1);
        repeat (100) @(posedge clk);
        u_m.power_cut;
        reprogram;
        check(img_set(0) == 16'h5678, "power cut while erasing A: B (last good) loaded");

        // 5. power loss during the page program (target A again)
        set_and_save(16'hDEF0);
        wait (u_m.pending_kind == 2);
        repeat (50) @(posedge clk);
        u_m.power_cut;
        reprogram;
        check(img_set(0) == 16'h5678, "power cut while programming A: B still loaded");

        // 6. a full save after that works and wins
        set_and_save(16'h0F0F);
        @(negedge saving);
        check(!save_err, "save after the power cuts verified");
        reprogram;
        check(img_set(0) == 16'h0F0F, "complete save (seq 3 in A) wins over B");

        // 7. no flash on the bus: defaults, saving disabled, no hang
        present = 0;
        reprogram;
        check(!flash_ok && img_set(0) == `SET_DEFAULT, "no flash: defaults, saves disabled");
        @(posedge clk) save_req <= 1; @(posedge clk) save_req <= 0;
        repeat (2000) @(posedge clk);
        check(!saving, "save request without flash is ignored");

        if (errors == 0) $display("PASS tb_flash: all checks");
        else             $display("FAIL tb_flash: %0d errors", errors);
        $finish;
    end
    initial begin #50_000_000; $display("FAIL tb_flash: timeout"); $finish; end
endmodule
