`timescale 1ns / 1ps
//=============================================================================
// tb_save_image.v : the 128-byte image - both write ports, all 7 read ports
//=============================================================================
module tb_save_image;
    reg clk = 0;
    always #5 clk = ~clk;
    reg       wef = 0, weg = 0;
    reg [6:0] waf = 0, wag = 0;
    reg [7:0] wdf = 0, wdg = 0;
    reg [6:0] ra [0:6];
    wire [7:0] rd0, rd1, rd2, rd3, rd4, rd5, rd6;
    save_image dut (.clk(clk), .we_flash(wef), .wa_flash(waf), .wd_flash(wdf),
                    .we_game(weg), .wa_game(wag), .wd_game(wdg),
                    .ra0(ra[0]), .ra1(ra[1]), .ra2(ra[2]), .ra3(ra[3]), .ra4(ra[4]), .ra5(ra[5]), .ra6(ra[6]),
                    .rd0(rd0), .rd1(rd1), .rd2(rd2), .rd3(rd3), .rd4(rd4), .rd5(rd5), .rd6(rd6));

    integer errors = 0;
    task check(input cond, input [8*64-1:0] msg);
        begin
            if (cond) $display("PASS %0s", msg);
            else begin $display("FAIL %0s", msg); errors = errors + 1; end
        end
    endtask

    integer i, bad;
    initial begin
        for (i = 0; i < 7; i = i + 1) ra[i] = 0;
        #1 check(rd0 == 0 && rd6 == 0, "starts all zero");
        // flash port writes 3 bytes, game port writes 2 others
        @(posedge clk) begin wef <= 1; waf <= 7'd5; wdf <= 8'h11; end
        @(posedge clk) begin waf <= 7'd6; wdf <= 8'h22; end
        @(posedge clk) begin waf <= 7'd127; wdf <= 8'h33; end
        @(posedge clk) begin wef <= 0; weg <= 1; wag <= 7'd0; wdg <= 8'h44; end
        @(posedge clk) begin wag <= 7'd66; wdg <= 8'h55; end
        // both at once on the same address: the flash port must win
        @(posedge clk) begin wef <= 1; waf <= 7'd10; wdf <= 8'hAA; wag <= 7'd10; wdg <= 8'hBB; end
        @(posedge clk) begin wef <= 0; weg <= 0; end
        #1;
        // every read port sees every byte
        bad = 0;
        ra[0] = 5; ra[1] = 6; ra[2] = 127; ra[3] = 0; ra[4] = 66; ra[5] = 10; ra[6] = 5; #1;
        if (rd0 != 8'h11 || rd1 != 8'h22 || rd2 != 8'h33 || rd3 != 8'h44 || rd4 != 8'h55 || rd5 != 8'hAA || rd6 != 8'h11)
            bad = bad + 1;
        ra[0] = 10; ra[1] = 10; ra[2] = 10; ra[3] = 10; ra[4] = 10; ra[5] = 10; ra[6] = 10; #1;
        if (rd0 != 8'hAA || rd1 != 8'hAA || rd2 != 8'hAA || rd3 != 8'hAA || rd4 != 8'hAA || rd5 != 8'hAA || rd6 != 8'hAA)
            bad = bad + 1;
        check(bad == 0, "7 read ports read the right bytes (flash and game writes)");
        check(dut.mem[10] == 8'hAA, "flash write wins when both write the same clock");
        check(dut.mem[1] == 8'h00, "untouched byte still 0");
        if (errors == 0) $display("PASS tb_save_image: all checks");
        else             $display("FAIL tb_save_image: %0d errors", errors);
        $finish;
    end
endmodule
