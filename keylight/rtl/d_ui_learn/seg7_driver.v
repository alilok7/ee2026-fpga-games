`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// seg7_driver.v : 4-digit multiplexed 7-segment display
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : Same multiplexing as the labs: only ONE digit is lit at a time
//           and we move to the next digit every 1 ms, so each digit is
//           refreshed at 250 Hz (inside the manual's 200-500 Hz hint) and
//           persistence of vision shows all four.
//           Producers send 6-bit glyph codes; the glyph table lives only
//           here. Segments and anodes are active LOW on the Basys3.
// Ports
//   glyphs   {digit3 (leftmost), digit2, digit1, digit0} x 6 bits
//   dps      decimal point per digit (used as the sharp sign), 1 = on
//   blink    per digit: 1 = blank this digit while blink_phase is 1
//   seg      {g,f,e,d,c,b,a} active low, dp active low, an active low
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
    reg  [1:0] digit;
    wire [5:0] g = glyphs[6*digit +: 6];

    // Glyph table, segments active HIGH here as {g,f,e,d,c,b,a}.
    reg [6:0] pat;
    always @(*) begin
        case (g)
            6'd0:  pat = 7'h3F;  6'd1:  pat = 7'h06;  6'd2:  pat = 7'h5B;
            6'd3:  pat = 7'h4F;  6'd4:  pat = 7'h66;  6'd5:  pat = 7'h6D;
            6'd6:  pat = 7'h7D;  6'd7:  pat = 7'h07;  6'd8:  pat = 7'h7F;
            6'd9:  pat = 7'h6F;
            6'd10: pat = 7'h77;  // A
            6'd11: pat = 7'h7C;  // b
            6'd12: pat = 7'h39;  // C
            6'd13: pat = 7'h5E;  // d
            6'd14: pat = 7'h79;  // E
            6'd15: pat = 7'h71;  // F
            6'd16: pat = 7'h3D;  // G
            6'd17: pat = 7'h76;  // H
            6'd18: pat = 7'h30;  // I
            6'd19: pat = 7'h1E;  // J
            6'd20: pat = 7'h75;  // K (approximation)
            6'd21: pat = 7'h38;  // L
            6'd22: pat = 7'h37;  // M (approximation)
            6'd23: pat = 7'h54;  // n
            6'd24: pat = 7'h3F;  // O
            6'd25: pat = 7'h73;  // P
            6'd26: pat = 7'h67;  // q
            6'd27: pat = 7'h50;  // r
            6'd28: pat = 7'h6D;  // S
            6'd29: pat = 7'h78;  // t
            6'd30: pat = 7'h3E;  // U
            6'd31: pat = 7'h1C;  // v
            6'd32: pat = 7'h2A;  // W (approximation)
            6'd33: pat = 7'h76;  // X (as H)
            6'd34: pat = 7'h6E;  // y
            6'd35: pat = 7'h5B;  // Z
            6'd37: pat = 7'h40;  // dash
            6'd38: pat = 7'h08;  // underscore
            default: pat = 7'h00;// blank
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            digit <= 2'd0;
            seg   <= 7'h7F;
            dp    <= 1'b1;
            an    <= 4'hF;
        end else begin
            if (tick_1ms) digit <= digit + 2'd1;
            seg <= ~pat;
            dp  <= ~dps[digit];
            an  <= (blink[digit] && blink_phase) ? 4'hF : ~(4'b0001 << digit);
        end
    end
endmodule
