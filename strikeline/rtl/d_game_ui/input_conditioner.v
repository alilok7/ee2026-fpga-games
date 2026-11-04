`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// input_conditioner.v : every switch and push-button enters the design here
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : 1. 2-flop synchroniser on all inputs (metastability, L1).
//           2. Switches: 5 ms stable-count debounce -> clean levels.
//           3. Buttons: 10 ms debounce, then press / long / repeat events
//              (button_events.v) for the menus.
//           4. Soft reset: btnU and btnD held together for 2 s. It re-arms
//              only after both are released, so holding them does not loop.
// Ports
//   sw_level    debounced switches (sw[0] pause, [1] minimap, [2] debug,
//               [3] slow motion, [15] left-handed)
//   btn_*       {U, D, L, R, C}, index with `BTN_x
//=============================================================================
module input_conditioner #(
    parameter SW_MS    = 5,
    parameter BTN_MS   = 10,
    parameter COMBO_MS = 2000
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
    // ---- 1. two-flop synchroniser (not reset: it just follows the pins) ----
    reg [20:0] sync1, sync2;
    always @(posedge clk) begin
        sync1 <= {btn, sw};
        sync2 <= sync1;
    end

    // ---- 2. switches -------------------------------------------------------
    wire [15:0] sw_tgl_unused;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_sw
            debounce #(.N_MS(SW_MS), .W(4)) u_db (
                .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sync2[i]),
                .level(sw_level[i]), .toggled(sw_tgl_unused[i]));
        end
    endgenerate

    // ---- 3. buttons --------------------------------------------------------
    wire [4:0] btn_tgl_unused;
    generate
        for (i = 0; i < 5; i = i + 1) begin : g_btn
            debounce #(.N_MS(BTN_MS), .W(4)) u_db (
                .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sync2[16 + i]),
                .level(btn_level[i]), .toggled(btn_tgl_unused[i]));
            button_events u_ev (
                .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .level(btn_level[i]),
                .press(btn_press[i]), .long_press(btn_long[i]),
                .repeat_pulse(btn_repeat[i]));
        end
    endgenerate

    // ---- 4. soft reset combo ----------------------------------------------
    reg [10:0] combo_ms;
    reg        armed;
    wire both = btn_level[`BTN_U] & btn_level[`BTN_D];
    always @(posedge clk) begin
        soft_reset_req <= 1'b0;
        if (rst) begin
            combo_ms <= 11'd0;
            armed    <= 1'b0;
        end else begin
            if (!btn_level[`BTN_U] && !btn_level[`BTN_D]) armed <= 1'b1;
            if (!both || !armed) begin
                combo_ms <= 11'd0;
            end else if (tick_1ms) begin
                if (combo_ms == COMBO_MS - 1) begin
                    soft_reset_req <= 1'b1;
                    armed          <= 1'b0;
                    combo_ms       <= 11'd0;
                end else begin
                    combo_ms <= combo_ms + 11'd1;
                end
            end
        end
    end
endmodule
