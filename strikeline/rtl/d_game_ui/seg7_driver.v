`timescale 1ns / 1ps

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
    reg [5:0] glyph;
    always @(*) begin
        case (digit)
            0: glyph = glyphs[5:0];
            1: glyph = glyphs[11:6];
            2: glyph = glyphs[17:12];
            3: glyph = glyphs[23:18];
        endcase
    end

    reg [6:0] pattern;
    always @(*) begin
        case (glyph)
            6'd0:  pattern = 7'h3F;  6'd1:  pattern = 7'h06;  6'd2:  pattern = 7'h5B;
            6'd3:  pattern = 7'h4F;  6'd4:  pattern = 7'h66;  6'd5:  pattern = 7'h6D;
            6'd6:  pattern = 7'h7D;  6'd7:  pattern = 7'h07;  6'd8:  pattern = 7'h7F;
            6'd9:  pattern = 7'h6F;
            6'd10: pattern = 7'h77;
            6'd11: pattern = 7'h7C;
            6'd12: pattern = 7'h39;
            6'd13: pattern = 7'h5E;
            6'd14: pattern = 7'h79;
            6'd15: pattern = 7'h71;
            6'd16: pattern = 7'h3D;
            6'd17: pattern = 7'h76;
            6'd18: pattern = 7'h30;
            6'd19: pattern = 7'h1E;
            6'd20: pattern = 7'h75;
            6'd21: pattern = 7'h38;
            6'd22: pattern = 7'h37;
            6'd23: pattern = 7'h54;
            6'd24: pattern = 7'h3F;
            6'd25: pattern = 7'h73;
            6'd26: pattern = 7'h67;
            6'd27: pattern = 7'h50;
            6'd28: pattern = 7'h6D;
            6'd29: pattern = 7'h78;
            6'd30: pattern = 7'h3E;
            6'd31: pattern = 7'h1C;
            6'd32: pattern = 7'h2A;
            6'd33: pattern = 7'h76;
            6'd34: pattern = 7'h6E;
            6'd35: pattern = 7'h5B;
            6'd37: pattern = 7'h40;
            6'd38: pattern = 7'h08;
            default: pattern = 7'h00;
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
            seg <= ~pattern;
            dp  <= ~dps[digit];
            if ((blink[digit] && blink_phase)) begin
                an <= 4'hF;
            end else begin
                an <= ~(4'b0001 << digit);
            end
        end
    end
endmodule
