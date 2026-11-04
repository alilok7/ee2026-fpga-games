`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// ui_status.v : D's requests for the 7-segment display and LEDs
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : For every mode D owns, decide what the 7-seg shows (a short
//           word naming the screen / selection, or the grade + accuracy on
//           Results) and what the LEDs do (a chase light on the title).
//           Play and Free Play replace these requests with C's / B's in
//           the IO mux.
//=============================================================================
module ui_status (
    input  wire                  clk,
    input  wire                  rst,
    input  wire                  tick_frame,
    input  wire [`KL_MODE_W-1:0] mode,
    input  wire [2:0]            menu_idx,
    input  wire [1:0]            difficulty,
    input  wire [2:0]            res_grade,
    input  wire [11:0]           res_acc_bcd,
    output reg  [23:0]           seg_glyphs,
    output wire [3:0]            seg_dp,
    output wire [3:0]            seg_blink,
    output reg  [15:0]           led_req
);
    // glyph code of a capital letter: 'A' -> 10 ... 'Z' -> 35
    function [5:0] L;
        input [7:0] ascii;
        L = ascii - 8'd55;
    endfunction
    localparam [5:0] B = `KL_G_BLANK;

    reg [7:0] anim;
    always @(posedge clk)
        if (rst) anim <= 8'd0; else if (tick_frame) anim <= anim + 8'd1;

    // grade letter for the 7-seg
    reg [5:0] gl;
    always @(*) begin
        case (res_grade)
            `KL_GRADE_S: gl = L("S");
            `KL_GRADE_A: gl = L("A");
            `KL_GRADE_B: gl = L("B");
            `KL_GRADE_C: gl = L("C");
            default:     gl = L("D");
        endcase
    end

    always @(*) begin
        seg_glyphs = {B, B, B, B};
        led_req    = 16'h0000;
        case (mode)
            `KL_MODE_TITLE: begin
                seg_glyphs = {L("H"), L("E"), L("L"), 6'd0};          // "HEL0"
                led_req[15 - anim[5:3]] = 1'b1;                        // chase over the keys
            end
            `KL_MODE_MENU:
                case (menu_idx)
                    3'd0: seg_glyphs = {L("P"), L("L"), L("A"), L("Y")};
                    3'd1: seg_glyphs = {L("L"), L("E"), L("R"), L("N")};
                    3'd2: seg_glyphs = {L("F"), L("R"), L("E"), L("E")};
                    3'd3: seg_glyphs = {L("H"), L("I"), B, B};
                    default: seg_glyphs = {L("S"), L("E"), L("T"), B};
                endcase
            `KL_MODE_SONGSEL:
                case (difficulty)
                    `KL_DIFF_EASY: seg_glyphs = {L("E"), L("A"), L("S"), L("Y")};
                    `KL_DIFF_HARD: seg_glyphs = {L("H"), L("A"), L("R"), L("D")};
                    default:       seg_glyphs = {L("N"), L("O"), L("R"), L("M")};
                endcase
            `KL_MODE_RESULTS:
                seg_glyphs = {gl, {2'b00, res_acc_bcd[11:8]}, {2'b00, res_acc_bcd[7:4]},
                              {2'b00, res_acc_bcd[3:0]}};
            `KL_MODE_LEARN:    seg_glyphs = {L("L"), L("E"), L("R"), L("N")};
            `KL_MODE_SCORES:   seg_glyphs = {L("H"), L("I"), B, B};
            `KL_MODE_SETTINGS: seg_glyphs = {L("S"), L("E"), L("T"), B};
            `KL_MODE_TEST:     seg_glyphs = {L("T"), L("E"), L("S"), L("T")};
            default:           seg_glyphs = {B, B, B, B};
        endcase
    end
    assign seg_dp    = 4'b0000;
    assign seg_blink = 4'b0000;
endmodule
