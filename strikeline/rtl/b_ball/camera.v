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
// Zoom (v3.1, hold right-click): a dolly zoom of the first-person camera.
//           zoom level zl glides 0..255 (~0.35 s). The lens gets longer,
//             K = 3060 + 84 * zl        (x1 .. x8; row = 30 + K / distance)
//           and the camera backs off by zl inches at the same time, so the
//           ball (40 + zl in ahead) stays near the bottom row while the pins
//           grow about 5x. Both come from zl in the same clock, so the
//           projector, the lane and the guide always agree.
//=============================================================================
module camera (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire        paused,
    input  wire        slowmo,           // v3: sw[3], 1/4 as many physics ticks per frame
    input  wire        aim_zoom,         // v3.1: zoom held (right button, from D)
    input  wire [`GS_W-1:0] game_state,
    input  wire [15:0] ball_y,
    input  wire signed [15:0] ball_vy,
    output reg  signed [10:0] cam_y,
    output reg  signed [10:0] cam_fp,    // first person: world y of the camera (zoom back-off included)
    output reg  [15:0] k_fp,             // first person: lens constant K (3060 = no zoom)
    output reg  [7:0]  zoom_lvl          // 0..255
);
    localparam signed [11:0] CAM_MIN = -12'sd40, CAM_MAX = 12'sd700;
    // v3 3-D camera: it follows the ball up to FP_STOP (80 in short of the
    // head pin) and watches the pin action from there.
    localparam signed [11:0] FP_STOP = 12'sd640;

    reg  [15:0] by_r;
    reg  signed [15:0] vy_r;
    reg  [`GS_W-1:0] gs;                         // game state and zoom, registered (timing)
    reg         zoom_r;
    always @(posedge clk) begin by_r <= ball_y; vy_r <= ball_vy; gs <= game_state; zoom_r <= aim_zoom; end
    wire signed [11:0] by    = $signed({2'b00, by_r[15:6]});       // whole inches
    // the lead assumes ~17 physics ticks per frame; slow motion has ~4 (v3 fix:
    // the overhead camera used to run ~27 in ahead of a slow-motion ball)
    reg  signed [11:0] lead;                     // registered (timing)
    always @(posedge clk) lead <= slowmo ? (vy_r >>> 7) : (vy_r >>> 5);
    // the two rolling targets, registered (timing), then only the clamps remain
    reg  signed [11:0] roll_top, roll_fp;
    always @(posedge clk) begin roll_top <= by - 12'sd14 + lead; roll_fp <= by - 12'sd40 + lead; end
    reg  signed [11:0] target;
    always @(*) begin
        case (gs)
            `GS_ROLL:                         target = roll_top;
            `GS_PINACTION, `GS_SETTLE,
            `GS_RESULT, `GS_SWEEP:            target = CAM_MAX;
            default:                          target = -12'sd12;
        endcase
        if (target < CAM_MIN) target = CAM_MIN;
        if (target > CAM_MAX) target = CAM_MAX;
    end

    // first person: 40 in behind the ball (aiming: 40 in behind the foul line),
    // same low-pass filter and the same speed lead
    reg  signed [11:0] tfp;
    always @(*) begin
        case (gs)
            `GS_AIM:                          tfp = -12'sd40;
            `GS_ROLL:                         tfp = (roll_fp > FP_STOP) ? FP_STOP : roll_fp;
            `GS_PINACTION, `GS_SETTLE,
            `GS_RESULT, `GS_SWEEP:            tfp = FP_STOP;
            default:                          tfp = -12'sd40;
        endcase
        if (tfp < -12'sd60)  tfp = -12'sd60;           // (every other target is a constant <= FP_STOP)
    end
    reg  signed [11:0] tfp_q;
    always @(posedge clk) tfp_q <= tfp;
    reg  signed [10:0] cam_base;                 // the camera before the zoom back-off
    wire signed [11:0] gfp  = tfp_q - cam_base;
    wire signed [11:0] sfp  = gfp >>> 3;
    // the camera glides everywhere except when a throw starts (it must be
    // behind the ball at once) and in menus
    wire fp_snap = (gs == `GS_THROW) || (gs < `GS_AIM) || (gs > `GS_SWEEP);
    always @(posedge clk) begin
        if (rst) cam_base <= -11'sd40;
        else if (fp_snap) cam_base <= tfp_q[10:0];
        else if (tick_frame && !paused) begin
            if (sfp != 0)      cam_base <= cam_base + sfp[10:0];
            else if (gfp > 0)  cam_base <= cam_base + 11'sd1;
            else if (gfp < 0)  cam_base <= cam_base - 11'sd1;
        end
    end

    // zoom: zl glides toward 255 while held and back to 0 when let go
    reg  [7:0] zl;
    always @(posedge clk) begin
        if (rst) zl <= 8'd0;
        else if (tick_frame) begin
            if (zoom_r) zl <= (zl > 8'd243) ? 8'd255 : zl + 8'd12;
            else        zl <= (zl < 8'd12)  ? 8'd0   : zl - 8'd12;
        end
    end
    // K = 3060 + 84 zl (84 = 64 + 16 + 4: shifts and adds), back-off = zl inches;
    // all three outputs from the same zl, registered
    always @(posedge clk) begin
        if (rst) begin cam_fp <= -11'sd40; k_fp <= 16'd3060; zoom_lvl <= 8'd0; end
        else begin
            cam_fp   <= cam_base - $signed({3'b000, zl});
            k_fp     <= 16'd3060 + {2'b00, zl, 6'd0} + {4'b0000, zl, 4'd0} + {6'd0, zl, 2'd0};
            zoom_lvl <= zl;
        end
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
