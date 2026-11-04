`timescale 1ns / 1ps
//=============================================================================
// reset_gen.v : power-on reset + soft reset
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student D (game controller)
// Purpose     : After configuration every flip-flop starts at its INIT value,
//               but the switches and buttons may still be bouncing and the
//               OLED needs time to power up. We hold the synchronous reset
//               `rst` high for ~10 ms after power-on, and again for 10 ms
//               whenever the soft-reset combo (U+D held 2 s) fires.
//               por_rst covers only power-on, so the OLED is not
//               re-initialised (no flicker) by a soft reset.
// Ports
//   clk        100 MHz
//   soft_req   1-cycle pulse from input_conditioner (btnU+btnD held 2 s)
//   rst        synchronous active-high reset for the whole design
//   por_rst    power-on reset only (Oled_Display)
//=============================================================================
module reset_gen #(
    parameter HOLD_CYCLES = 1_000_000          // 10 ms at 100 MHz
) (
    input  wire clk,
    input  wire soft_req,
    (* max_fanout = 40 *) output reg rst = 1'b1,   // copied by synthesis: ~7000 loads
    output reg  por_rst = 1'b1
);
    reg [19:0] cnt     = 20'd0;
    reg        por_done = 1'b0;

    always @(posedge clk) begin
        if (soft_req) begin
            cnt <= 20'd0;                       // restart the 10 ms hold
            rst <= 1'b1;
        end else if (cnt != HOLD_CYCLES - 1) begin
            cnt <= cnt + 20'd1;
            rst <= 1'b1;
        end else begin
            rst      <= 1'b0;
            por_done <= 1'b1;
        end
        por_rst <= ~por_done;
    end
endmodule
