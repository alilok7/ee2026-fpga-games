`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// input_conditioner.v : every switch and button enters the design here
//-----------------------------------------------------------------------------
// Owner   : Student B
// Purpose : 1. 2-flop synchroniser on all 21 inputs (metastability, L1).
//           2. Switches: 5 ms stable-count debounce. A strike is a change
//              in EITHER direction, so a player never has to reset a switch.
//           3. Buttons: 10 ms debounce, then press / long / repeat events.
//           4. Soft reset: U and D held together for 2 s (re-armed only after
//              both are released, so holding them does not loop resets).
//           Switches use a shorter debounce than buttons because a rhythm
//           game needs fast repeated strikes; slide switches also bounce for
//           less time than the push-buttons.
// Ports
//   sw[15:0]       raw switches. sw[15:8] = C4..C5, sw[7:3] = C#4 D#4 F#4 G#4
//                  A#4, sw[2] octave, sw[1] mute, sw[0] pause
//   btn[4:0]       raw buttons {U, D, L, R, C}
//   key_strike     13-bit chromatic 1-cycle pulses (bit 0 = C4 .. 12 = C5)
//   key_level      13-bit chromatic debounced levels
//   ctl_level[2:0] debounced {octave, mute, pause} = sw[2:0]
//   btn_level / btn_press / btn_long / btn_repeat   {U, D, L, R, C}
//   soft_reset_req 1-cycle pulse to reset_gen
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
    output wire [12:0] key_strike,
    output wire [12:0] key_level,
    output wire [2:0]  ctl_level,
    output wire [4:0]  btn_level,
    output wire [4:0]  btn_press,
    output wire [4:0]  btn_long,
    output wire [4:0]  btn_repeat,
    output reg         soft_reset_req
);
    // ---- 1. two-flop synchroniser (never reset: it just follows the pins) --
    reg [20:0] sync1, sync2;
    always @(posedge clk) begin
        sync1 <= {btn, sw};
        sync2 <= sync1;
    end

    // ---- 2. debounce every switch ------------------------------------------
    wire [15:0] sw_lvl, sw_tgl;
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : g_sw
            debounce #(.N_MS(SW_MS), .W(4)) u_db (
                .clk(clk), .rst(rst), .tick_1ms(tick_1ms), .din(sync2[i]),
                .level(sw_lvl[i]), .toggled(sw_tgl[i]));
        end
    endgenerate

    // Physical switch -> chromatic key number (white keys on sw[15:8] left to
    // right, black keys on sw[7:3]). Written out so it is easy to check
    // against the board labels.
    assign key_strike = {sw_tgl[8], sw_tgl[9], sw_tgl[3], sw_tgl[10], sw_tgl[4],
                         sw_tgl[11], sw_tgl[5], sw_tgl[12], sw_tgl[13], sw_tgl[6],
                         sw_tgl[14], sw_tgl[7], sw_tgl[15]};
    assign key_level  = {sw_lvl[8], sw_lvl[9], sw_lvl[3], sw_lvl[10], sw_lvl[4],
                         sw_lvl[11], sw_lvl[5], sw_lvl[12], sw_lvl[13], sw_lvl[6],
                         sw_lvl[14], sw_lvl[7], sw_lvl[15]};
    assign ctl_level  = sw_lvl[2:0];

    // ---- 3. buttons: debounce + events -------------------------------------
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

    // ---- 4. soft reset: U + D held for COMBO_MS ----------------------------
    reg [10:0] combo_ms;
    reg        armed;
    wire both = btn_level[`KL_BTN_U] & btn_level[`KL_BTN_D];
    always @(posedge clk) begin
        soft_reset_req <= 1'b0;
        if (rst) begin
            combo_ms <= 11'd0;
            armed    <= 1'b0;                    // must release before re-arm
        end else begin
            if (!btn_level[`KL_BTN_U] && !btn_level[`KL_BTN_D]) armed <= 1'b1;
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
