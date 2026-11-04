`timescale 1ns / 1ps
//=============================================================================
// crc16.v : CRC-16-CCITT of one more byte (polynomial 0x1021, init 0xFFFF)
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : The checksum of a save slot. A CRC is long division of the data
//           by the polynomial in GF(2) (subtraction = XOR): for every bit,
//           shift the 16-bit remainder left and XOR in 0x1021 when the bit
//           shifted out is 1. Unrolled for the 8 bits of a byte, it is a
//           small block of XOR gates, used once per byte as data streams
//           past. Any 1-bit or 2-bit error, and any burst up to 16 bits, in a
//           slot changes the CRC, so a slot cut off by a power loss is
//           always rejected.
//=============================================================================
module crc16 (
    input  wire [15:0] crc_in,
    input  wire [7:0]  data,
    output reg  [15:0] crc_out
);
    integer i;
    always @(*) begin
        crc_out = crc_in ^ {data, 8'h00};
        for (i = 0; i < 8; i = i + 1)
            crc_out = crc_out[15] ? ({crc_out[14:0], 1'b0} ^ 16'h1021) : {crc_out[14:0], 1'b0};
    end
endmodule
