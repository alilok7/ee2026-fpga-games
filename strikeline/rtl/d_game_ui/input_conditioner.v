`timescale 1ns / 1ps
`include "strike_defs.vh"

module input_conditioner #(
    parameter SW_MS    = 5,
    parameter BTN_MS   = 10,
    parameter COMBO_MS = 2000,
    parameter SW_W = 4,
    parameter BTN_W = 4,
    parameter COMBO_W = 11
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_1ms,
    input  wire [15:0] sw,
    input  wire [4:0]  btn,
    output wire [15:0] sw_level,
    output wire [4:0]  btn_level,
    output wire [4:0]  btn_press,
    output wire [4:0]  btn_long,
    output wire [4:0]  btn_repeat,
    output reg         soft_reset_req
);

    wire [15:0] sw_tgl_unused;
    wire [4:0] btn_tgl_unused;

    debounce #(.N_MS(SW_MS), .W(SW_W)) sw0 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[0]),
        .level(sw_level[0]), .toggled(sw_tgl_unused[0])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw1 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[1]),
        .level(sw_level[1]), .toggled(sw_tgl_unused[1])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw2 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[2]),
        .level(sw_level[2]), .toggled(sw_tgl_unused[2])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw3 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[3]),
        .level(sw_level[3]), .toggled(sw_tgl_unused[3])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw4 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[4]),
        .level(sw_level[4]), .toggled(sw_tgl_unused[4])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw5 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[5]),
        .level(sw_level[5]), .toggled(sw_tgl_unused[5])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw6 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[6]),
        .level(sw_level[6]), .toggled(sw_tgl_unused[6])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw7 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[7]),
        .level(sw_level[7]), .toggled(sw_tgl_unused[7])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw8 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[8]),
        .level(sw_level[8]), .toggled(sw_tgl_unused[8])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw9 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[9]),
        .level(sw_level[9]), .toggled(sw_tgl_unused[9])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw10 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[10]),
        .level(sw_level[10]), .toggled(sw_tgl_unused[10])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw11 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[11]),
        .level(sw_level[11]), .toggled(sw_tgl_unused[11])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw12 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[12]),
        .level(sw_level[12]), .toggled(sw_tgl_unused[12])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw13 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[13]),
        .level(sw_level[13]), .toggled(sw_tgl_unused[13])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw14 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[14]),
        .level(sw_level[14]), .toggled(sw_tgl_unused[14])
    );
    debounce #(.N_MS(SW_MS), .W(4)) sw15 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sw[15]),
        .level(sw_level[15]), .toggled(sw_tgl_unused[15])
    );
    debounce #(.N_MS(BTN_MS), .W(BTN_W)) button0 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(btn[0]),
        .level(btn_level[0]), .toggled(btn_tgl_unused[0])
    );
    button_events events0 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .level(btn_level[0]),
        .press(btn_press[0]), .long_press(btn_long[0]), .repeat_pulse(btn_repeat[0])
    );
    debounce #(.N_MS(BTN_MS), .W(4)) button1 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(btn[1]),
        .level(btn_level[1]), .toggled(btn_tgl_unused[1])
    );
    button_events events1 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .level(btn_level[1]),
        .press(btn_press[1]), .long_press(btn_long[1]), .repeat_pulse(btn_repeat[1])
    );
    debounce #(.N_MS(BTN_MS), .W(4)) button2 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(btn[2]),
        .level(btn_level[2]), .toggled(btn_tgl_unused[2])
    );
    button_events events2 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .level(btn_level[2]),
        .press(btn_press[2]), .long_press(btn_long[2]), .repeat_pulse(btn_repeat[2])
    );
    debounce #(.N_MS(BTN_MS), .W(4)) button3 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(btn[3]),
        .level(btn_level[3]), .toggled(btn_tgl_unused[3])
    );
    button_events events3 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .level(btn_level[3]),
        .press(btn_press[3]), .long_press(btn_long[3]), .repeat_pulse(btn_repeat[3])
    );
    debounce #(.N_MS(BTN_MS), .W(4)) button4 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(btn[4]),
        .level(btn_level[4]), .toggled(btn_tgl_unused[4])
    );
    button_events events4 (
        .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .level(btn_level[4]),
        .press(btn_press[4]), .long_press(btn_long[4]), .repeat_pulse(btn_repeat[4])
    );

    reg [COMBO_W-1:0] combo_ms;
    reg        armed;
    wire both = btn_level[`BTN_L] & btn_level[`BTN_R];
    always @(posedge clk) begin
        soft_reset_req <= 1'b0;
        if (rst) begin
            combo_ms <= 0;
            armed    <= 1'b0;
        end else begin
            if (!btn_level[`BTN_L] && !btn_level[`BTN_R]) armed <= 1'b1;
            if (!both || !armed) begin
                combo_ms <= 0;
            end else if (tick_1ms) begin
                if (combo_ms == COMBO_MS - 1) begin
                    soft_reset_req <= 1'b1;
                    armed          <= 1'b0;
                    combo_ms       <= 0;
                end else begin
                    combo_ms <= combo_ms + 1'b1;
                end
            end
        end
    end
endmodule
