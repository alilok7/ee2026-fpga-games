`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// seg7_driver.v - drives the 4-digit 7-segment display
//-----------------------------------------------------------------------------
// Owner   : Student D
// Same idea as the Lab 4 7-segment task: only ONE digit is on at a time.
// Every 1 ms we move to the next digit, so each digit is refreshed every
// 4 ms (250 Hz) and our eyes see all four at once.
// Inputs
//   glyphs   4 digits x 6 bits, {digit3 (leftmost), digit2, digit1, digit0}.
//            Each 6-bit code is a character: 0-9, 10.. letters, 37 '-'.
//   dps      decimal point for each digit, 1 = on
//   blink    1 = hide this digit while blink_phase is 1 (tied to 0 in the
//            top module at the moment)
// Outputs (Basys3: all active LOW)
//   seg = {g,f,e,d,c,b,a}, dp, an
//=============================================================================
module seg7_driver (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_1ms,
    input  wire [23:0] glyphs,
    input  wire [3:0]  dps,
    input  wire [3:0]  blink,
    input  wire        blink_phase,
    output reg  [6:0]  seg,
    output reg         dp,
    output reg  [3:0]  an
);
    // ---- 1. which digit is on (0 = rightmost) -----------------------------
    reg [1:0] digit;
    always @(posedge clk) begin
        if (rst == 1)
            digit <= 0;
        else if (tick_1ms == 1)
            digit <= digit + 1;
    end

    // ---- 2. pick the code, decimal point and anode for that digit ---------
    reg [5:0] code;
    reg       dot;
    reg [3:0] an_next;
    always @(*) begin
        case (digit)
            2'd0: begin code = glyphs[5:0];   dot = dps[0]; an_next = 4'b1110; end
            2'd1: begin code = glyphs[11:6];  dot = dps[1]; an_next = 4'b1101; end
            2'd2: begin code = glyphs[17:12]; dot = dps[2]; an_next = 4'b1011; end
            default: begin code = glyphs[23:18]; dot = dps[3]; an_next = 4'b0111; end
        endcase
        if (blink[digit] == 1 && blink_phase == 1)
            an_next = 4'b1111;                      // digit hidden
    end

    // ---- 3. character code -> segments (active HIGH here, {g,f,e,d,c,b,a})
    reg [6:0] pattern;
    always @(*) begin
        case (code)
            6'd0:  pattern = 7'b0111111;   // 0
            6'd1:  pattern = 7'b0000110;   // 1
            6'd2:  pattern = 7'b1011011;   // 2
            6'd3:  pattern = 7'b1001111;   // 3
            6'd4:  pattern = 7'b1100110;   // 4
            6'd5:  pattern = 7'b1101101;   // 5
            6'd6:  pattern = 7'b1111101;   // 6
            6'd7:  pattern = 7'b0000111;   // 7
            6'd8:  pattern = 7'b1111111;   // 8
            6'd9:  pattern = 7'b1101111;   // 9
            6'd10: pattern = 7'b1110111;   // A
            6'd11: pattern = 7'b1111100;   // b
            6'd12: pattern = 7'b0111001;   // C
            6'd13: pattern = 7'b1011110;   // d
            6'd14: pattern = 7'b1111001;   // E
            6'd15: pattern = 7'b1110001;   // F
            6'd16: pattern = 7'b0111101;   // G
            6'd17: pattern = 7'b1110110;   // H
            6'd18: pattern = 7'b0110000;   // I
            6'd19: pattern = 7'b0011110;   // J
            6'd20: pattern = 7'b1110101;   // K (close enough)
            6'd21: pattern = 7'b0111000;   // L
            6'd22: pattern = 7'b0110111;   // M (close enough)
            6'd23: pattern = 7'b1010100;   // n
            6'd24: pattern = 7'b0111111;   // O
            6'd25: pattern = 7'b1110011;   // P
            6'd26: pattern = 7'b1100111;   // q
            6'd27: pattern = 7'b1010000;   // r
            6'd28: pattern = 7'b1101101;   // S
            6'd29: pattern = 7'b1111000;   // t
            6'd30: pattern = 7'b0111110;   // U
            6'd31: pattern = 7'b0011100;   // v
            6'd32: pattern = 7'b0101010;   // W (close enough)
            6'd33: pattern = 7'b1110110;   // X (same as H)
            6'd34: pattern = 7'b1101110;   // y
            6'd35: pattern = 7'b1011011;   // Z
            6'd37: pattern = 7'b1000000;   // -
            6'd38: pattern = 7'b0001000;   // _
            default: pattern = 7'b0000000; // blank
        endcase
    end

    // ---- 4. output registers (invert: the board is active low) -------------
    always @(posedge clk) begin
        if (rst == 1) begin
            seg <= 7'b1111111;
            dp  <= 1;
            an  <= 4'b1111;
        end
        else begin
            seg <= ~pattern;
            dp  <= ~dot;
            an  <= an_next;
        end
    end
endmodule
