`timescale 1ns/1ps
`include "strike_defs.vh"
module tb_ui;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1,paused=0,slowmo=0,frame_done=0;
    wire ms,game,sample,phys,frame,oled;
    timebase #(.MS_DIV(4),.PHYS_DIV(3),.SMP_DIV(5)) tb(clk,rst,paused,slowmo,frame_done,ms,game,sample,phys,frame,oled);
    reg tick=0;
    reg [15:0] sw=0;
    reg [4:0] btn=0;
    wire [15:0] sw_level;
    wire [4:0] btn_level,bp,bl,br;
    wire soft_req;
    input_conditioner #(.SW_MS(2),.BTN_MS(2),.COMBO_MS(3)) inputs(clk,rst,tick,sw,btn,sw_level,btn_level,bp,bl,br,soft_req);
    reg [`GS_W-1:0] gs=`GS_TITLE;
    reg [2:0] hover=0;
    reg valid=0,player=0,two=0,spare=0;
    reg [7:0] mph=172,made=3,tries=5;
    reg [8:0] score0=123,score1=250;
    wire [23:0] glyphs;
    wire [3:0] dps;
    seg7_ctrl ctrl(clk,rst,game,gs,hover,paused,valid,mph,score0,score1,player,two,spare,made,tries,glyphs,dps);
    reg [23:0] shown={6'd1,6'd2,6'd3,6'd4};
    reg [3:0] blink=0;
    reg phase=0;
    wire [6:0] seg;
    wire dp;
    wire [3:0] an;
    seg7_driver display(clk,rst,tick,shown,4'b0101,blink,phase,seg,dp,an);
    integer i,mc,gc,sc,pc;
    task step;
        begin @(posedge clk); #1; end
    endtask
    task check(input ok,input [511:0] message);
        if(ok !== 1'b1) begin $display("FAIL %0s",message); $stop; end
    endtask
    task pulse;
        begin @(negedge clk); tick=1; step; @(negedge clk); tick=0; step; end
    endtask
    initial begin
        step; step; @(negedge clk); rst=0;
        mc=0;gc=0;sc=0;pc=0;
        for(i=0;i<60;i=i+1) begin
            step;
            check(ms==(i%4==3),"1ms divider");
            check(phys==(i%3==2),"physics divider");
            check(sample==(i%5==4),"sample divider");
            check(game==ms,"game tick");
        end
        @(negedge clk); paused=1; frame_done=1;
        step; check(frame,"frame missing while paused");
        @(negedge clk); frame_done=0;
        for(i=0;i<60;i=i+1) begin step; check(!game && !phys && !sample && !frame,"paused tick"); end
        @(negedge clk); paused=0;slowmo=1;
        for(i=0;i<60;i=i+1) begin step; mc=mc+ms;gc=gc+game;sc=sc+sample;pc=pc+phys; end
        check(mc==15 && (gc==3 || gc==4) && sc==12 && pc==5,"slow motion rate");
        check(glyphs=={6'd11,6'd24,6'd32,6'd21},"title word");
        @(negedge clk); gs=`GS_AIM;valid=1; step;
        @(negedge clk); valid=0;step;
        check(glyphs=={6'd39,6'd1,6'd7,6'd2} && dps==2,"speed display 17.2");
        @(negedge clk); paused=1;step;
        check(glyphs=={6'd25,6'd10,6'd30,6'd28},"pause word");
        @(negedge clk); paused=0;gs=`GS_GAMEOVER;step;
        check(glyphs=={6'd39,6'd1,6'd2,6'd3},"score display");
        check(an==4'b1110 && seg==~7'h66 && dp==0,"digit zero");
        pulse; check(an==4'b1101 && seg==~7'h4f && dp==1,"digit one");
        pulse; check(an==4'b1011 && seg==~7'h5b && dp==0,"digit two");
        @(negedge clk); blink=4'b0100;phase=1;step;
        check(an==15,"blink blanking");
        @(negedge clk); btn=(1<<`BTN_U)|(1<<`BTN_D);sw=16'hffff;
        repeat(4) step; repeat(8) begin pulse;check(!soft_req,"Up Down wrongly resets"); end
        check(sw_level==16'hffff,"switch generate");
        @(negedge clk);btn=0;
        repeat(4) step; repeat(3) pulse;
        @(negedge clk);btn=(1<<`BTN_L)|(1<<`BTN_R);
        repeat(4) step; pulse; pulse;
        pulse; check(!soft_req,"combo too short");
        pulse; check(!soft_req,"combo too short");
        @(negedge clk); tick=1;step;check(soft_req,"Left Right combo missing");
        @(negedge clk);tick=0;step;check(!soft_req,"soft_req request pulse too long");
        repeat(10) begin pulse;check(!soft_req,"combo re-fired while held"); end
        $display("PASS tb_ui: timebase, display and input wiring");
        $finish;
    end
endmodule
