`timescale 1ns / 1ps
// spi_byte.v : send and receive one byte over SPI mode 0, MSB first
// Student D. SCK = 100 MHz / 8 (mod-8 phase counter, same idea as the clock
// divider from the lab). MOSI is set while SCK is low, MISO is read when it goes high.
module spi_byte (
    input  wire       clk,
    input  wire       rst,
    input  wire       start,
    input  wire [7:0] tx,         // byte to send
    output reg  [7:0] rx = 0,
    output reg        done = 0,   // 1 clock: the byte is finished
    output wire       busy,       // a byte is in flight
    output reg        sck = 0,
    output reg        mosi = 0,   // SPI data out (QspiDB[0])
    input  wire       miso        // SPI data in  (QspiDB[1])
);
    // state register + next-state logic
    parameter IDLE = 1'b0, SHIFT = 1'b1;
    reg state = IDLE, nextstate;

    // two mod-8 counters (clock in the bit, which bit) and the shift register
    reg [2:0] phase   = 0;
    reg [2:0] bit_cnt = 0;
    reg [7:0] sh      = 0;

    wire last_clk = (phase == 3'd7) && (bit_cnt == 3'd7);    // end of the 8th bit

    // next-state logic
    always @(*) begin
        case (state)
            IDLE:    nextstate = start ? SHIFT : IDLE;
            SHIFT:   nextstate = last_clk ? IDLE : SHIFT;
            default: nextstate = IDLE;
        endcase
    end

    // state register
    always @(posedge clk) begin
        if (rst) state <= IDLE;
        else     state <= nextstate;
    end

    // output logic (Moore)
    assign busy = (state == SHIFT);

    // datapath: counters, shift register, pins
    always @(posedge clk) begin
        if (rst) begin
            phase <= 0; bit_cnt <= 0; sh <= 0; rx <= 0; done <= 0; sck <= 0; mosi <= 0;
        end else begin
            done <= 1'b0;                                    // a pulse: low unless set below
            case (state)
                IDLE: begin
                    sck <= 1'b0; phase <= 0; bit_cnt <= 0;
                    if (start) sh <= tx;                     // load the byte to send
                end
                SHIFT: begin
                    phase <= phase + 3'd1;                   // 7 + 1 wraps to 0
                    if (phase == 3'd0) begin sck <= 1'b0; mosi <= sh[7]; end   // set the bit
                    if (phase == 3'd4) begin sck <= 1'b1; sh <= {sh[6:0], miso}; end // read a bit
                    if (phase == 3'd7) begin
                        bit_cnt <= bit_cnt + 3'd1;
                        if (bit_cnt == 3'd7) begin done <= 1'b1; rx <= sh; end
                    end
                end
            endcase
        end
    end
endmodule
