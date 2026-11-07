`timescale 1ns / 1ps
// spi_byte.v - sends and receives one byte to the flash chip (SPI mode 0)
// Student D
module spi_byte (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] tx,
    output reg  [7:0] rx = 0,
    output reg        done = 0,
    output wire       busy,
    output reg        sck = 0,
    output reg        mosi = 0,
    input  wire       miso
);
    // two states: waiting, or shifting a byte
    parameter IDLE = 1'b0, SHIFT = 1'b1;
    reg state = IDLE, nextstate;

    // phase counts the 8 clocks of one bit, bit_cnt counts the bits
    reg [2:0] phase   = 0;
    reg [2:0] bit_cnt = 0;
    reg [7:0] sh      = 0;

    wire last_clk = (phase == 3'd7) && (bit_cnt == 3'd7);

    always @(*) begin
        case (state)
            IDLE:    nextstate = start ? SHIFT : IDLE;
            SHIFT:   nextstate = last_clk ? IDLE : SHIFT;
            default: nextstate = IDLE;
        endcase
    end

    always @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= nextstate;
    end

    assign busy = (state == SHIFT);

    // SCK goes high halfway through each bit, that's when MISO is read
    always @(posedge clk) begin
        if (rst) begin
            phase <= 0; bit_cnt <= 0; sh <= 0; rx <= 0; done <= 0; sck <= 0; mosi <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    sck <= 1'b0; phase <= 0; bit_cnt <= 0;
                    if (start) sh <= tx;
                end
                SHIFT: begin
                    phase <= phase + 3'd1;
                    if (phase == 3'd0) begin sck <= 1'b0; mosi <= sh[7]; end
                    if (phase == 3'd4) begin sck <= 1'b1; sh <= {sh[6:0], miso}; end
                    if (phase == 3'd7) begin
                        bit_cnt <= bit_cnt + 3'd1;
                        if (bit_cnt == 3'd7) begin done <= 1'b1; rx <= sh; end
                    end
                end
            endcase
        end
    end
endmodule
