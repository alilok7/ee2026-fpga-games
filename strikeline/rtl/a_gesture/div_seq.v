`timescale 1ns / 1ps
// div_seq.v : unsigned restoring divider, one quotient bit per clock
// Owner: Student A
module div_seq #(parameter W = 40, parameter COUNT_W = 6) (
    input wire clk, rst, start,
    input wire [W-1:0] num, den,
    output reg [W-1:0] quo,
    output reg done,
    output wire busy
);
    reg [COUNT_W-1:0] count;
    reg [W-1:0] remainder, numerator, divisor;
    wire [W:0] shifted = {remainder, numerator[W-1]};
    assign busy = count != 0;

    always @(posedge clk) begin
        done <= 0;
        if (rst) begin
            count <= 0;
            remainder <= 0;
            numerator <= 0;
            divisor <= 0;
            quo <= 0;
        end else if (start && !busy) begin
            count <= W;
            remainder <= 0;
            numerator <= num;
            divisor <= den;
            quo <= 0;
        end else if (busy) begin
            numerator <= numerator << 1;
            if (shifted >= divisor) begin
                remainder <= shifted - divisor;
                quo <= (quo << 1) + 1'b1;
            end else begin
                remainder <= shifted;
                quo <= quo << 1;
            end
            count <= count - 1'b1;
            if (count == 1) done <= 1;
        end
    end
endmodule

module gesture_multiply (
    input wire clk, rst, start,
    input wire signed [16:0] a,
    input wire signed [16:0] b,
    output reg signed [33:0] product,
    output reg done
);
    reg [33:0] shifted;
    reg [16:0] bits;
    reg [4:0] count;

    always @(posedge clk) begin
        done <= 0;
        if (rst) begin
            shifted <= 0;
            bits <= 0;
            count <= 0;
            product <= 0;
        end else if (start && count == 0) begin
            shifted <= {{17{a[16]}}, a};
            bits <= b;
            product <= 0;
            count <= 17;
        end else if (count != 0) begin
            if (bits[0]) begin
                if (count == 1) product <= product - shifted;
                else product <= product + shifted;
            end
            shifted <= shifted << 1;
            bits <= bits >> 1;
            count <= count - 1'b1;
            if (count == 1) done <= 1;
        end
    end
endmodule
