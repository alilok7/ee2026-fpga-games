`timescale 1ns / 1ps
// crc16.v - works out the CRC-16 after one more byte (poly 0x1021)
// Student D

// one bit at a time, like long division by the polynomial
module crc_step (
    input  wire [15:0] c_in,
    input  wire        d,
    output wire [15:0] c_out
);
    wire fb = c_in[15] ^ d;
    assign c_out = {c_in[14:0], 1'b0} ^ ({16{fb}} & 16'h1021);
endmodule

// chain 8 of them to do a whole byte
module crc16 (
    input  wire [15:0] crc_in,
    input  wire [7:0]  data,
    output wire [15:0] crc_out
);
    wire [15:0] c1, c2, c3, c4, c5, c6, c7;

    crc_step s7 (.c_in(crc_in), .d(data[7]), .c_out(c1));
    crc_step s6 (.c_in(c1),     .d(data[6]), .c_out(c2));
    crc_step s5 (.c_in(c2),     .d(data[5]), .c_out(c3));
    crc_step s4 (.c_in(c3),     .d(data[4]), .c_out(c4));
    crc_step s3 (.c_in(c4),     .d(data[3]), .c_out(c5));
    crc_step s2 (.c_in(c5),     .d(data[2]), .c_out(c6));
    crc_step s1 (.c_in(c6),     .d(data[1]), .c_out(c7));
    crc_step s0 (.c_in(c7),     .d(data[0]), .c_out(crc_out));
endmodule
