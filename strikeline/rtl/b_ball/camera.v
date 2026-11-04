`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// camera.v : which 64 inches of lane the OLED shows
//-----------------------------------------------------------------------------
// Owner   : Student B
// Output  : cam_y = world y (inches, signed) of the BOTTOM screen row.
//           Every world renderer draws row py at world y = cam_y + 63 - py.
// Smoothing (once per frame, 60 Hz):  cam += (target - cam) >> 3
//           a first-order low-pass filter (each frame closes 1/8 of the
//           gap), so the view glides instead of jumping. A filter like this
//           lags a moving target by speed / (1/8) = 8 frames of travel, so
//           the target includes a LEAD of the same size:
//             lead = 8 frames * 17.07 ticks/frame * vy  ~= vy(Q3.12) >> 5
//           and the ball stays ~14 rows above the bottom of the screen.
// Targets   aiming: -12 (foul line near the bottom, approach visible)
//           rolling: ball - 14 + lead      pin action: 700 (whole deck)
//           always clamped to [-40, 700].
//=============================================================================
module camera (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire        paused,
    input  wire [`GS_W-1:0] game_state,
    input  wire [15:0] ball_y,
    input  wire signed [15:0] ball_vy,
    output reg  signed [10:0] cam_y
);
    localparam signed [11:0] CAM_MIN = -12'sd40, CAM_MAX = 12'sd700;

    reg  [15:0] by_r;
    reg  signed [15:0] vy_r;
    always @(posedge clk) begin by_r <= ball_y; vy_r <= ball_vy; end   // timing
    wire signed [11:0] by    = $signed({2'b00, by_r[15:6]});       // whole inches
    wire signed [11:0] lead  = vy_r >>> 5;
    reg  signed [11:0] target;
    always @(*) begin
        case (game_state)
            `GS_ROLL:                         target = by - 12'sd14 + lead;
            `GS_PINACTION, `GS_SETTLE,
            `GS_RESULT, `GS_SWEEP:            target = CAM_MAX;
            default:                          target = -12'sd12;
        endcase
        if (target < CAM_MIN) target = CAM_MIN;
        if (target > CAM_MAX) target = CAM_MAX;
    end

    reg  signed [11:0] target_q;                 // registered (timing)
    always @(posedge clk) target_q <= target;
    wire signed [11:0] gap  = target_q - cam_y;
    wire signed [11:0] step = gap >>> 3;
    always @(posedge clk) begin
        if (rst) cam_y <= -11'sd12;
        else if (tick_frame && !paused) begin
            if (step != 0)     cam_y <= cam_y + step[10:0];
            else if (gap > 0)  cam_y <= cam_y + 11'sd1;     // finish the last pixels
            else if (gap < 0)  cam_y <= cam_y - 11'sd1;
        end
    end
endmodule
