`timescale 1ns / 1ps
//=============================================================================
// tb_divider_seq.v : C's shift-subtract divider and D's bin2bcd converter
//   Divider: 2000 random cases plus the extremes, compared with "/".
//   bin2bcd: 2000 random 20-bit values compared digit by digit.
//=============================================================================
module tb_divider_seq;
    reg clk = 0, rst = 1, start = 0, bstart = 0;
    reg  [16:0] num;
    reg  [9:0]  den;
    wire [16:0] q;
    wire        done;
    reg  [19:0] bin;
    wire [23:0] bcd;
    wire        bdone;
    divider_seq #(.WN(17), .WD(10)) dut (.clk(clk), .rst(rst), .start(start), .num(num),
                                         .den(den), .quot(q), .done(done));
    bin2bcd #(.W(20), .D(6)) b2b (.clk(clk), .rst(rst), .start(bstart), .bin(bin),
                                  .bcd(bcd), .done(bdone));
    always #5 clk = ~clk;

    integer i, errors = 0, expect_v;
    task divide; input [16:0] n; input [9:0] d;
        begin
            num = n; den = d;
            @(posedge clk) start <= 1; @(posedge clk) start <= 0;
            wait (done); @(posedge clk);
            if (q != n / d) begin
                errors = errors + 1;
                $display("FAIL %0d / %0d = %0d (got %0d)", n, d, n / d, q);
            end
        end
    endtask
    task convert; input [19:0] v;
        begin
            bin = v;
            @(posedge clk) bstart <= 1; @(posedge clk) bstart <= 0;
            wait (bdone); @(posedge clk);
            expect_v = bcd[23:20]*100000 + bcd[19:16]*10000 + bcd[15:12]*1000 +
                       bcd[11:8]*100 + bcd[7:4]*10 + bcd[3:0];
            if (expect_v != v) begin
                errors = errors + 1;
                $display("FAIL bcd(%0d) gave %h", v, bcd);
            end
        end
    endtask

    initial begin
        repeat (3) @(posedge clk); rst = 0;
        divide(17'd102200, 10'd1022);         // 100 %
        divide(17'd0, 10'd7);
        divide(17'd131071, 10'd1);
        divide(17'd66, 10'd1000);
        for (i = 0; i < 2000; i = i + 1) divide($random, ({$random} % 1023) + 1);
        convert(20'd0); convert(20'd999999); convert(20'd1048575 % 1000000);
        for (i = 0; i < 2000; i = i + 1) convert({$random} % 1000000);
        if (errors == 0) $display("PASS tb_divider_seq: divider and bin2bcd correct");
        else             $display("FAIL tb_divider_seq: %0d errors", errors);
        $finish;
    end
endmodule
