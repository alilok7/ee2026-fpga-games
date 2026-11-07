`timescale 1ns/1ps
module tb_datapaths;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1,start=0;
    reg signed [16:0] a=0;
    reg signed [16:0] b=0;
    wire signed [33:0] product;
    wire done;
    gesture_multiply multiply(clk,rst,start,a,b,product,done);
    reg [8:0] value=0;
    wire [11:0] digits;
    seg_bcd9 bcd(value,digits);
`include "bcd_fns.vh"
    reg signed [33:0] expected;
    reg [19:0] expected_bcd;
    integer i,j,k,n;
    task step;
        begin @(posedge clk); #1; end
    endtask
    task check(input ok,input [511:0] message);
        if(ok !== 1'b1) begin $display("FAIL %0s",message);$stop;end
    endtask
    task multiply_case(input signed [16:0] x,input signed [16:0] y);
        begin
            @(negedge clk);a=x;b=y;start=1;expected=x*y;
            step;
            @(negedge clk);start=0;
            for(k=1;k<=17;k=k+1) begin
                step;
                check(done==(k==17),"multiply latency");
            end
            check(product===expected,"signed shift-add product");
            step;check(!done,"multiply done repeated");
        end
    endtask
    initial begin
        step;step;
        @(negedge clk);rst=0;
        multiply_case(-17'sd65536,-17'sd65536);
        multiply_case(-17'sd65536,17'sd65535);
        multiply_case(17'sd65535,-17'sd65536);
        multiply_case(17'sd65535,17'sd65535);
        multiply_case(0,-1);
        multiply_case(-1,-1);
        multiply_case(-1,1);
        for(i=0;i<500;i=i+1) multiply_case($random,$random);
        for(i=0;i<512;i=i+1) begin
            value=i;#1;
            expected_bcd=0;n=i;
            for(j=0;j<3;j=j+1) begin
                expected_bcd[j*4+:4]=n%10;n=n/10;
            end
            check(digits===expected_bcd[11:0],"structural BCD9");
            check(bcd9(value)===expected_bcd[11:0],"compatibility BCD9");
        end
        for(i=0;i<65536;i=i+1) begin
            expected_bcd=0;n=i;
            for(j=0;j<5;j=j+1) begin
                expected_bcd[j*4+:4]=n%10;n=n/10;
            end
            check(bcd16(i)===expected_bcd,"compatibility BCD16");
        end
        $display("PASS tb_datapaths: signed multiplier; all 9-bit and 16-bit BCD values");
        $finish;
    end
endmodule
