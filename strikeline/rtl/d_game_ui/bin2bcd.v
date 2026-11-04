`timescale 1ns / 1ps
//=============================================================================
// bin2bcd.v : sequential binary -> BCD ("double dabble")
//-----------------------------------------------------------------------------
// Owner   : Student D (used by D for scores, by A for speeds)
// Purpose : To draw a number we need its decimal digits. A combinational
//           converter for 20 bits is large; this one does it in W clock
//           cycles with one small "add 3" stage per digit:
//             repeat W times: every BCD digit >= 5 gets +3, then shift the
//             whole {bcd, binary} register left by one bit.
//           (The +3 before a shift is the same as +6 after it, which is the
//           decimal-carry correction.) 20 cycles = 0.2 us, so running it
//           once per frame is free.
// Ports
//   start   1-cycle pulse: latch `bin` and begin
//   bcd     D digits, digit 0 in bits [3:0]; holds the last result
//   done    1-cycle pulse when bcd is updated
//=============================================================================
module bin2bcd #(
    parameter W = 20,
    parameter D = 6
) (
    input  wire           clk,
    input  wire           rst,
    input  wire           start,
    input  wire [W-1:0]   bin,
    output reg  [4*D-1:0] bcd,
    output reg            done
);
    reg [W-1:0]   sh;
    reg [4*D-1:0] acc;
    reg [5:0]     cnt;
    reg           busy;

    // "add 3 if >= 5" on every digit of acc
    wire [4*D-1:0] adj;
    genvar k;
    generate
        for (k = 0; k < D; k = k + 1) begin : g_adj
            wire [3:0] dg = acc[4*k +: 4];
            assign adj[4*k +: 4] = (dg >= 4'd5) ? dg + 4'd3 : dg;
        end
    endgenerate

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            busy <= 1'b0;
            bcd  <= {4*D{1'b0}};
            acc  <= {4*D{1'b0}};
            sh   <= {W{1'b0}};
            cnt  <= 6'd0;
        end else if (start) begin
            sh   <= bin;
            acc  <= {4*D{1'b0}};
            cnt  <= W[5:0];
            busy <= 1'b1;
        end else if (busy) begin
            {acc, sh} <= {adj, sh} << 1;
            cnt <= cnt - 6'd1;
            if (cnt == 6'd1) begin
                busy <= 1'b0;
                done <= 1'b1;
                bcd  <= {adj[4*D-2:0], sh[W-1]};   // value after this last shift
            end
        end
    end
endmodule
