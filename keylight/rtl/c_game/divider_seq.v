`timescale 1ns / 1ps
//=============================================================================
// divider_seq.v : sequential shift-subtract (restoring) divider
//-----------------------------------------------------------------------------
// Owner   : Student C
// Purpose : Accuracy % = (2P + G) * 100 / (2N) is needed ONCE per song, so
//           instead of a big combinational divider we do long division in
//           binary, one quotient bit per clock - exactly like pencil-and-
//           paper long division:
//             rem = (rem << 1) | next dividend bit
//             if rem >= den: rem -= den, quotient bit = 1, else 0
//           WN clocks per division (17 cycles = 170 ns).
// Ports
//   start     1-cycle pulse, latches num/den
//   quot      result, valid when done pulses (den = 0 gives all ones)
//=============================================================================
module divider_seq #(
    parameter WN = 17,
    parameter WD = 10
) (
    input  wire          clk,
    input  wire          rst,
    input  wire          start,
    input  wire [WN-1:0] num,
    input  wire [WD-1:0] den,
    output reg  [WN-1:0] quot,
    output reg           done
);
    reg [WN-1:0] q;
    reg [WD:0]   rem;
    reg [WD-1:0] d;
    reg [5:0]    cnt;
    reg          busy;

    wire [WD:0] shifted = {rem[WD-1:0], q[WN-1]};       // bring down next bit
    wire        fits    = (shifted >= {1'b0, d});

    always @(posedge clk) begin
        done <= 1'b0;
        if (rst) begin
            busy <= 1'b0;
            quot <= {WN{1'b0}};
            q    <= {WN{1'b0}};
            rem  <= {(WD+1){1'b0}};
            d    <= {WD{1'b0}};
            cnt  <= 6'd0;
        end else if (start) begin
            q    <= num;
            d    <= den;
            rem  <= {(WD+1){1'b0}};
            cnt  <= WN[5:0];
            busy <= 1'b1;
        end else if (busy) begin
            rem <= fits ? shifted - {1'b0, d} : shifted;
            q   <= {q[WN-2:0], fits};
            cnt <= cnt - 6'd1;
            if (cnt == 6'd1) begin
                busy <= 1'b0;
                done <= 1'b1;
                quot <= {q[WN-2:0], fits};
            end
        end
    end
endmodule
