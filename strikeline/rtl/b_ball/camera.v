`timescale 1ns / 1ps
`include "strike_defs.vh"
// camera.v : low-pass camera with speed lead and dolly zoom
// Owner: Student B

module camera (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire        paused,
    input  wire        slowmo,
    input  wire        aim_zoom,
    input  wire [`GS_W-1:0] game_state,
    input  wire [15:0] ball_y,
    input  wire signed [15:0] ball_vy,
    output reg  signed [10:0] cam_y,
    output reg  signed [10:0] cam_fp,
    output reg  [15:0] k_fp,
    output reg  [7:0]  zoom_lvl
);

    // ---------- 1. Where each camera wants to be ----------
    wire [`GS_W-1:0] gs;
    wire signed [11:0] target_q, target_fp_q;

    camera_target u_target (
        .clk(clk),
        .slowmo(slowmo),
        .game_state(game_state),
        .ball_y(ball_y),
        .ball_vy(ball_vy),
        .gs(gs),
        .target_q(target_q),
        .target_fp_q(target_fp_q)
    );

    // ---------- 2. First-person camera: closes 1/8 of the gap every frame ----------
    reg  signed [10:0] cam_base;
    wire signed [11:0] gap_fp = target_fp_q - cam_base;
    wire signed [11:0] step_fp = gap_fp >>> 3;
    // Jump straight to the target during a swipe and outside play
    wire snap = (gs == `GS_THROW) || (gs < `GS_AIM) || (gs > `GS_SWEEP);

    always @ (posedge clk) begin
        if (rst)
            cam_base <= -11'sd40;
        else if (snap)
            cam_base <= target_fp_q[10:0];
        else if (tick_frame && !paused) begin
            if (step_fp != 0)
                cam_base <= cam_base + step_fp[10:0];
            else if (gap_fp > 0)
                cam_base <= cam_base + 11'sd1;
            else if (gap_fp < 0)
                cam_base <= cam_base - 11'sd1;
        end
    end

    // ---------- 3. Dolly zoom: longer lens, and the camera backs off at the same time ----------
    reg       zoom_q;
    // Hold right click: zl glides up by 12 per frame, and back down on release
    reg [7:0] zl;

    always @ (posedge clk) begin
        zoom_q <= aim_zoom;
    end

    always @ (posedge clk) begin
        if (rst)
            zl <= 8'd0;
        else if (tick_frame) begin
            if (zoom_q)
                zl <= (zl > 8'd243) ? 8'd255 : zl + 8'd12;
            else
                zl <= (zl < 8'd12) ? 8'd0 : zl - 8'd12;
        end
    end

    always @ (posedge clk) begin
        if (rst) begin
            cam_fp <= -11'sd40;
            k_fp <= 16'd3060;
            zoom_lvl <= 8'd0;
        end
        else begin
            // K = 3060 + 84*zl. All three come from the same zl, so the views never disagree
            cam_fp <= cam_base - $signed({3'b000, zl});
            k_fp <= 16'd3060 + {2'b00, zl, 6'd0} + {4'b0000, zl, 4'd0} + {6'd0, zl, 2'd0};
            zoom_lvl <= zl;
        end
    end

    // ---------- 4. Top-down camera: closes 1/8 of the gap every frame ----------
    wire signed [11:0] gap = target_q - cam_y;
    wire signed [11:0] step = gap >>> 3;

    always @ (posedge clk) begin
        if (rst)
            cam_y <= -11'sd12;
        else if (tick_frame && !paused) begin
            if (step != 0)
                cam_y <= cam_y + step[10:0];
            else if (gap > 0)
                cam_y <= cam_y + 11'sd1;
            else if (gap < 0)
                cam_y <= cam_y - 11'sd1;
        end
    end
endmodule


// Camera targets from the game state and the ball, with a lead for the ball's speed
module camera_target (
    input  wire        clk,
    input  wire        slowmo,
    input  wire [`GS_W-1:0] game_state,
    input  wire [15:0] ball_y,
    input  wire signed [15:0] ball_vy,
    output reg  [`GS_W-1:0] gs,
    output reg  signed [11:0] target_q,
    output reg  signed [11:0] target_fp_q
);
    localparam signed [11:0] CAM_MIN = -12'sd40;
    localparam signed [11:0] CAM_MAX = 12'sd700;
    localparam signed [11:0] FP_STOP = 12'sd640;

    // Inputs are registered for timing. The lead cancels the lag of the 1/8 filter
    reg  [15:0] by_q;
    reg  signed [15:0] vy_q;
    reg  signed [11:0] lead, roll_top, roll_fp;
    wire signed [11:0] by = $signed({2'b00, by_q[15:6]});

    always @ (posedge clk) begin
        by_q <= ball_y;
        vy_q <= ball_vy;
        gs <= game_state;
        lead <= slowmo ? (vy_q >>> 7) : (vy_q >>> 5);
        roll_top <= by - 12'sd14 + lead;
        roll_fp <= by - 12'sd40 + lead;
    end

    // Top-down camera target for each game state, limited to the lane
    reg signed [11:0] target;
    always @ (*) begin
        case (gs)
            `GS_ROLL:
                target = roll_top;
            `GS_PINACTION, `GS_SETTLE, `GS_RESULT, `GS_SWEEP:
                target = CAM_MAX;
            default:
                target = -12'sd12;
        endcase
        if (target < CAM_MIN)
            target = CAM_MIN;
        if (target > CAM_MAX)
            target = CAM_MAX;
    end

    // First-person camera target: follows the ball and stops 80 in before the head pin
    reg signed [11:0] target_fp;
    always @ (*) begin
        case (gs)
            `GS_AIM:
                target_fp = -12'sd40;
            `GS_ROLL:
                target_fp = (roll_fp > FP_STOP) ? FP_STOP : roll_fp;
            `GS_PINACTION, `GS_SETTLE, `GS_RESULT, `GS_SWEEP:
                target_fp = FP_STOP;
            default:
                target_fp = -12'sd40;
        endcase
        if (target_fp < -12'sd60)
            target_fp = -12'sd60;
    end

    always @ (posedge clk) begin
        target_q <= target;
        target_fp_q <= target_fp;
    end
endmodule
