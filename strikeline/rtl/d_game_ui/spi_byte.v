`timescale 1ns / 1ps
//=============================================================================
// spi_byte.v : one SPI byte, mode 0, MSB first, SCK = 100 MHz / 8
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : The flash samples MOSI on the rising SCK edge and changes MISO
//           after the falling edge (mode 0). One bit takes 8 system clocks:
//             phase 0..3  SCK low   (MOSI set at phase 0)
//             phase 4..7  SCK high  (MISO sampled at phase 4)
//           12.5 MHz is far below the flash's 40-50 MHz READ limit, so the
//           STARTUPE2 clock-path delay does not matter.
//=============================================================================
module spi_byte (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] tx,
    output reg  [7:0] rx,
    output reg        done,
    output wire       busy,
    output reg        sck,
    output reg        mosi,
    input  wire       miso
);
    reg [2:0] phase;
    reg [3:0] bits;                    // bits left
    reg [7:0] sh;
    assign busy = (bits != 4'd0);

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            phase <= 0; bits <= 0; sh <= 0; rx <= 0; sck <= 1'b0; mosi <= 1'b0;
        end else if (start && !busy) begin
            sh <= tx; bits <= 4'd8; phase <= 3'd0;
        end else if (busy) begin
            phase <= phase + 3'd1;
            case (phase)
                3'd0: begin sck <= 1'b0; mosi <= sh[7]; end
                3'd4: begin sck <= 1'b1; sh <= {sh[6:0], miso}; end
                3'd7: begin
                    bits <= bits - 4'd1;
                    if (bits == 4'd1) begin
                        done <= 1'b1;
                        rx   <= sh;            // all 8 bits shifted in
                    end
                end
                default: ;
            endcase
        end else begin
            sck <= 1'b0;
        end
    end
endmodule
