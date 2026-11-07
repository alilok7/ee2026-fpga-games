`timescale 1ns/1ps
module tb_controls;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, tick=0, din=0;
    wire level,toggled;
    debounce #(.N_MS(3)) db(clk,rst,tick,din,level,toggled);
    reg held=0;
    wire press,long_press,rep;
    button_events #(.LONG_MS(7),.REP_DELAY(3),.REP_PERIOD(2)) ev(clk,rst,tick,held,press,long_press,rep);
    reg soft_req=0;
    wire reset,por;
    reset_gen #(.HOLD_CYCLES(4)) rg(clk,soft_req,reset,por);
    reg start=0;
    reg [7:0] num=0,den=1;
    wire [7:0] quo;
    wire done,busy;
    div_seq #(.W(8)) div(clk,rst,start,num,den,quo,done,busy);
    integer i,j,k,elapsed;
    task step;
        begin @(posedge clk); #1; end
    endtask
    task ms;
        begin @(negedge clk); tick=1; step; @(negedge clk); tick=0; step; end
    endtask
    task check(input ok,input [511:0] message);
        if (ok !== 1'b1) begin $display("FAIL %0s",message); $stop; end
    endtask
    initial begin
        step; step; step;
        check(reset && por,"power reset too short");
        step; check(!reset && !por,"power reset too long");
        @(negedge clk); soft_req=1; step;
        check(reset && !por,"soft_req reset changed POR");
        @(negedge clk); soft_req=0;
        repeat(3) begin step; check(reset,"soft_req reset too short"); end
        step; check(!reset && !por,"soft_req reset too long");
        @(negedge clk); rst=0; din=0;
        repeat(6) step;
        @(negedge clk); din=1;
        repeat(10) step;
        check(!level,"debounce counted clocks");
        ms; check(!level,"debounce accepted first tick");
        ms; check(!level,"debounce accepted second tick");
        @(negedge clk); tick=1; step;
        check(level && toggled,"debounce missing change pulse");
        @(negedge clk); tick=0; step; check(!toggled,"debounce pulse longer than clock");
        @(negedge clk); din=0;
        repeat(3) step; ms; ms;
        @(negedge clk); din=1;
        repeat(3) step;
        @(negedge clk); din=0;
        repeat(3) step; ms; ms; check(level,"bounce did not restart timer");
        ms; check(!level,"falling debounce failed");
        @(negedge clk); held=1; step; check(press,"press missing");
        step; check(!press,"press repeated");
        for(i=1;i<=80;i=i+1) begin
            @(negedge clk); tick=1; step;
            check(rep == (i>=3 && (i-3)%2==0),"repeat timing");
            check(long_press == (i==7),"long press timing");
            @(negedge clk); tick=0; step;
            check(!rep && !long_press,"event pulse too long");
        end
        @(negedge clk); held=0; step;
        ms; check(!rep && !long_press,"event after release");
        for(i=0;i<256;i=i+1) begin
            for(j=0;j<256;j=j+1) begin
                @(negedge clk); num=i; den=j; start=1;
                step; check(busy,"divider did not start");
                @(negedge clk); start=0;
                for(k=1;k<=8;k=k+1) begin
                    step;
                    check(done==(k==8),"divider latency");
                end
                check(quo == ((j==0)?255:i/j),"divider quotient");
                check(!busy,"divider still busy");
                step; check(!done,"divider done pulse too long");
            end
        end
        @(negedge clk); rst=1; din=1; tick=0;
        repeat(3) begin
            step;
            check(!level && !toggled, "debounce reset used raw input");
        end
        @(negedge clk); rst=0; tick=1;
        repeat(3) begin
            step;
            check(!toggled, "startup reported a switch event");
        end
        check(level, "startup did not seed synchronized high input");
        repeat(10) begin
            step;
            check(level && !toggled, "held startup switch produced an event");
        end
        $display("PASS tb_controls: debounce, events, reset and all 65536 8-bit divisions");
        $finish;
    end
    initial begin #20000000; begin $display("FAIL timeout"); $stop; end end
endmodule
