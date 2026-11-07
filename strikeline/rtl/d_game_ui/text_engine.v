`timescale 1ns / 1ps
// text_engine.v : the ONE place where characters are turned into pixels
// Owner: Student A
`include "strike_defs.vh"

module text_engine (
    input  wire [`TX_W-1:0] req,
    output wire        on,
    output wire        in_cell,
    output wire [15:0] fg,
    output wire [15:0] bg,
    output wire        bg_en
);
    reg [4:0] font7 [0:511];
    reg [2:0] font5 [0:511];
    initial begin
        $readmemh("font5x7.mem", font7);
        $readmemh("font3x5.mem", font5);
    end

    wire [5:0] str_ch;
    string_rom u_str (.addr(req[`TX_VAL]), .ch(str_ch));
    reg [5:0] glyph;
    always @(*) begin
        if (req[`TX_LIT]) begin
            glyph = req[7:2];
        end else begin
            glyph = str_ch;
        end
    end
    wire [2:0] fx = req[`TX_FX];
    wire [2:0] fy = req[`TX_FY];

    wire [4:0] r7 = font7[{glyph, fy}];
    wire [2:0] r5 = font5[{glyph, fy}];
    reg bit7;
    always @(*) begin
        if ((fx <= 3'd4)) begin
            bit7 = r7[3'd4 - fx];
        end else begin
            bit7 = 1'b0;
        end
    end
    reg bit5;
    always @(*) begin
        if ((fx <= 3'd2)) begin
            bit5 = r5[3'd2 - fx];
        end else begin
            bit5 = 1'b0;
        end
    end

    assign in_cell = req[`TX_VALID];
    assign on    = req[`TX_VALID] && (req[`TX_FONT] ? bit5 : bit7);
    assign fg    = req[`TX_FG];
    assign bg    = req[`TX_BG];
    assign bg_en = req[`TX_BGEN];
endmodule
