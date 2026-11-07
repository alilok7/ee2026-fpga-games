`timescale 1ns / 1ps
// crc16.v : CRC-16-CCITT of one more byte (polynomial 0x1021, start 0xFFFF)
// Student D. Used by flash_ctrl to check a save slot: 8 one-bit steps (crc_step)
// in a chain, the same way the ripple-carry adder in the lab chains full adders.

// one bit of the division
module crc_step (
    input  wire [15:0] c_in,       // remainder so far
    input  wire        d,          // the next data bit
    output wire [15:0] c_out       // remainder after this bit
);
    wire fb = c_in[15] ^ d;                                  // bit shifted out XOR data bit
    assign c_out = {c_in[14:0], 1'b0} ^ ({16{fb}} & 16'h1021);
endmodule

// one byte = 8 steps in a chain (structural)
module crc16 (
    input  wire [15:0] crc_in,
    input  wire [7:0]  data,       // the next byte
    output wire [15:0] crc_out     // CRC including this byte
);
    // 8 steps in a chain, MSB first
    wire [15:0] c1, c2, c3, c4, c5, c6, c7;                  // between the steps

    crc_step s7 (.c_in(crc_in), .d(data[7]), .c_out(c1));     // MSB first
    crc_step s6 (.c_in(c1),     .d(data[6]), .c_out(c2));
    crc_step s5 (.c_in(c2),     .d(data[5]), .c_out(c3));
    crc_step s4 (.c_in(c3),     .d(data[4]), .c_out(c4));
    crc_step s3 (.c_in(c4),     .d(data[3]), .c_out(c5));
    crc_step s2 (.c_in(c5),     .d(data[2]), .c_out(c6));
    crc_step s1 (.c_in(c6),     .d(data[1]), .c_out(c7));
    crc_step s0 (.c_in(c7),     .d(data[0]), .c_out(crc_out)); // LSB last
endmodule
