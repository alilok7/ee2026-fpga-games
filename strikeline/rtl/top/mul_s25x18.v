`timescale 1ns / 1ps
// mul_s25x18.v : the multiplier each physics/gesture part shares
// Owner: Student B

module mul_s25x18 (
    input  wire               clk,
    input  wire signed [24:0] a,
    input  wire signed [17:0] b,
    output reg  signed [42:0] p
);
    always @ (posedge clk) begin
        p <= a * b;
    end
endmodule
