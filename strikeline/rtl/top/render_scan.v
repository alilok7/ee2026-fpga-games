`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// render_scan.v - walks every pixel of both screens once per frame (v3, v3.2)
//-----------------------------------------------------------------------------
// Owner (Q&A) : Student D (integration)
// Purpose : In v2 the OLED driver asked for pixels and the renderers answered
//           within 6 clocks. With two screens of different sizes we instead
//           draw each frame ourselves, into frame buffers:
//             1. on `start` (the VGA's vertical blank) the VGA picture,
//                320 x 240 (v3.2; v3 was 160 x 120), scr = 0, written to the
//                VGA buffer, top row first
//             2. then the OLED picture, 96 x 64, scr = 1, written to the
//                OLED buffer
//             3. `done` = the frame tick for the whole design (60 Hz)
//           Each pixel position is held for 8 clocks: the renderers are
//           combinational, the compositor captures the colour on `cap`
//           (clock 7) and the buffer is written on clock 8.
//           (76 800 + 6 144 pixels x 8 = 664 k clocks = 6.6 ms of 16.7 ms.)
// One VGA buffer, no tearing (v3.2): a 320-pixel row takes 2 560 clocks to
//           draw, the monitor needs 6 400 clocks to show it (2 lines), and the
//           drawing starts in the vertical blank. So the drawing is always
//           ahead of the monitor: every row is rewritten after the monitor
//           showed the old frame and before it shows the new one.
// Timing  : the XDC gives every path from px_x / px_y into the compositor's
//           pix register 7 clocks (multicycle).
//=============================================================================
module render_scan (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,            // VGA frame start (vertical blank)
    output reg         scr,              // 0 = VGA pass, 1 = OLED pass
    (* max_fanout = 64 *) output reg  [8:0]  px_x,
    (* max_fanout = 64 *) output reg  [7:0]  px_y,
    output reg         cap,              // compositor: capture now
    output reg         we_v,             // write the VGA buffer
    output reg         we_o,             // write the OLED buffer
    output reg  [16:0] wa,               // write address (y * width + x)
    output reg  [1:0]  wpar,             // {y[0], x[0]} of the pixel written (dither)
    output reg         done,             // 1-cycle: both pictures are drawn
    output wire        busy_out          // a frame is being drawn
);
    reg       busy;
    assign busy_out = busy;
    reg [2:0] cnt;
    reg [16:0] idx;
    wire last_x = scr ? (px_x == 9'd95)  : (px_x == 9'd319);
    wire last_y = scr ? (px_y == 8'd63)  : (px_y == 8'd239);
    always @(posedge clk) begin
        cap <= 1'b0; we_v <= 1'b0; we_o <= 1'b0; done <= 1'b0;
        if (rst) begin
            busy <= 1'b0; cnt <= 3'd0; idx <= 17'd0; scr <= 1'b0;
            px_x <= 9'd0; px_y <= 8'd0; wa <= 17'd0; wpar <= 2'd0;
        end else if (!busy) begin
            if (start) begin
                busy <= 1'b1; cnt <= 3'd0; idx <= 17'd0; scr <= 1'b0; px_x <= 9'd0; px_y <= 8'd0;
            end
        end else begin
            cnt <= cnt + 3'd1;
            if (cnt == 3'd6) cap <= 1'b1;                 // colour registered at the end of clock 7
            if (cnt == 3'd7) begin
                // write the pixel just captured, then step to the next one
                wa <= idx;
                wpar <= {px_y[0], px_x[0]};
                if (scr) we_o <= 1'b1; else we_v <= 1'b1;
                idx <= idx + 17'd1;
                if (!last_x) px_x <= px_x + 9'd1;
                else begin
                    px_x <= 9'd0;
                    if (!last_y) px_y <= px_y + 8'd1;
                    else begin
                        px_y <= 8'd0; idx <= 17'd0;
                        if (!scr) scr <= 1'b1;                 // VGA done -> OLED
                        else begin scr <= 1'b0; busy <= 1'b0; done <= 1'b1; end
                    end
                end
            end
        end
    end
endmodule
