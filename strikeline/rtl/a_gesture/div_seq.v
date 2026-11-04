`timescale 1ns / 1ps
//=============================================================================
// div_seq.v : unsigned restoring divider, one quotient bit per clock
//-----------------------------------------------------------------------------
// Owner   : Student A
// Purpose : Long division in binary, exactly as on paper: shift the next
//           dividend bit into a remainder; if remainder >= divisor,
//           subtract and write a 1 into the quotient, else write a 0.
//           W cycles for W-bit numbers, one subtractor in hardware instead
//           of a huge combinational divider. Only used twice per throw
//           (aim ratio and spin), so speed does not matter.
//           Divide by zero returns all ones (callers check den != 0).
//=============================================================================
module div_seq #(
    parameter W = 40
) (
    input  wire         clk,
    input  wire         rst,
    input  wire         start,
    input  wire [W-1:0] num,
    input  wire [W-1:0] den,
    output reg  [W-1:0] quo,
    output reg          done,
    output wire         busy
);
    reg [W-1:0] rem, n_sh, d_r;
    reg [6:0]   cnt;
    assign busy = (cnt != 7'd0);

    // remainder is always < divisor < 2^W, so {rem, next bit} fits W+1 bits
    wire [W:0]   shifted = {rem, n_sh[W-1]};
    wire [W+1:0] trial   = {1'b0, shifted} - {2'b00, d_r};      // remainder - divisor
    wire         ge      = ~trial[W+1];                         // no borrow -> >=

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            cnt <= 7'd0; rem <= 0; n_sh <= 0; d_r <= 0; quo <= 0;
        end else if (start) begin
            rem <= 0; n_sh <= num; d_r <= den; quo <= 0;
            cnt <= W[6:0];
        end else if (busy) begin
            rem  <= ge ? trial[W-1:0] : shifted[W-1:0];
            n_sh <= n_sh << 1;
            quo  <= {quo[W-2:0], ge};
            cnt  <= cnt - 7'd1;
            if (cnt == 7'd1) done <= 1'b1;
        end
    end
endmodule
