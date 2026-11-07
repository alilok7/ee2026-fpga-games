`timescale 1ns/1ps
`include "strike_defs.vh"
module tb_startup;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1;
    reg tick=0;
    reg [15:0] sw=16'hffff;
    reg [4:0] btn=5'b11111;
    wire [15:0] clean_sw;
    wire [4:0] clean_btn, press, long_press, repeat_pulse;
    wire soft_request;
    input_conditioner inputs (
        .clk(clk), .rst(rst), .tick_1ms(tick), .sw(sw), .btn(btn),
        .sw_level(clean_sw), .btn_level(clean_btn), .btn_press(press),
        .btn_long(long_press), .btn_repeat(repeat_pulse), .soft_reset_req(soft_request)
    );
    integer i;
    integer presses=0;
    task step;
        begin @(posedge clk); #1; end
    endtask
    task check(input ok,input [511:0] message);
        if(ok !== 1'b1) begin $display("FAIL %0s",message); $stop; end
    endtask
    initial begin
        step;
        @(negedge clk); rst=0; tick=1;
        for(i=0;i<50;i=i+1) begin
            step;
            check(press==0 && long_press==0 && repeat_pulse==0,"held startup button generated event");
            check(!inputs.sw0.toggled && !inputs.button0.toggled,"startup generated toggle");
            if(i>=3) check(clean_sw==16'hffff && clean_btn==5'b11111,"startup baseline wrong");
        end
        @(negedge clk); rst=1;
        repeat(5) step;
        @(negedge clk); rst=0;
        repeat(20) begin
            step;
            check(press==0,"held button pressed again after reset");
            check(!inputs.sw0.toggled,"switch toggled after reset");
        end
        @(negedge clk); sw=0;btn=0;
        repeat(20) begin step;check(press==0,"release generated press");end
        check(clean_sw==0 && clean_btn==0,"release not debounced");
        @(negedge clk);btn=1;
        repeat(30) begin step;if(press[0]) presses=presses+1;end
        check(presses==1,"real press after startup was lost or duplicated");
        $display("PASS tb_startup: no power-up switch/button events; real press still works");
        $finish;
    end
endmodule
