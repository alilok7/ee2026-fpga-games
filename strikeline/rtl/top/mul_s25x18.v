`timescale 1ns / 1ps
//=============================================================================
// mul_s25x18.v : the multiplier each physics/gesture part SHARES
//-----------------------------------------------------------------------------
// Owner   : used by A, B and C (one instance each); written by Student B
// Purpose : A DSP48E1 slice multiplies a 25-bit by an 18-bit signed number.
//           Instead of writing "*" all over a datapath (one DSP each) every
//           part feeds its operands from its own FSM into ONE of these, one
//           product per clock. The product register is the DSP's own P
//           register, so the multiply-and-store fits easily in 10 ns.
// Timing  : operands presented in cycle t  ->  p valid in cycle t+1.
//=============================================================================
module mul_s25x18 (
    input  wire               clk,
    input  wire signed [24:0] a,
    input  wire signed [17:0] b,
    output reg  signed [42:0] p
);
    always @(posedge clk) p <= a * b;
endmodule
