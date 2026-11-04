`timescale 1ns / 1ps
//=============================================================================
// audio_out.v : the ONLY module that knows which audio Pmod is plugged in
//-----------------------------------------------------------------------------
// Owner   : Student A
// Target  : Digilent Pmod AMP2 on the top row of JA
//             JA1 AIN       PWM audio in (the AMP2 low-pass filters it)
//             JA2 GAIN      1 = 6 dB (quieter, safer for headphones)
//             JA3 NC        driven low
//             JA4 ~SHUTDOWN 1 = amplifier on
// Purpose : 8-bit PWM. A free-running 8-bit counter at 100 MHz wraps every
//           256 clocks (390.6 kHz, far above hearing). The output is high
//           while counter < sample, so the average voltage, after the AMP2's
//           filter, is proportional to the sample.
//           If the lab gives us a Pmod I2S2 instead, only this file changes.
// Ports
//   sample   8-bit unsigned sample from sound_engine (128 = silence)
//   ja[3:0]  {~SHUTDOWN, NC, GAIN, AIN} = {JA4, JA3, JA2, JA1}
//=============================================================================
module audio_out (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] sample,
    output reg  [3:0] ja
);
    reg [7:0] pwm_cnt;
    always @(posedge clk) begin
        if (rst) begin
            pwm_cnt <= 8'd0;
            ja      <= 4'b0010;              // amp shut down during reset
        end else begin
            pwm_cnt <= pwm_cnt + 8'd1;
            ja[0]   <= (pwm_cnt < sample);   // AIN
            ja[1]   <= 1'b1;                 // GAIN = 6 dB
            ja[2]   <= 1'b0;                 // not connected
            ja[3]   <= 1'b1;                 // ~SHUTDOWN = run
        end
    end
endmodule
