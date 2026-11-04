`timescale 1ns / 1ps
//=============================================================================
// led_guides.v : the guide light above each lane's switch
//-----------------------------------------------------------------------------
// Owner   : Student C
// Purpose : For each lane, brightness rises as that lane's next note gets
//           close:  dt >= 1000 ms -> off,  dt = 0 -> full.
//             lin    = (1023 - dt) >> 2            (0..255)
//             bright = lin * lin >> 8              (gamma: the eye sees PWM
//                                                   duty roughly as a square)
//           Inside the Perfect window the LED blinks; on a hit it flashes
//           full on. The 8 levels are recomputed once per frame ONE LANE PER
//           CLOCK through a single 8x8 multiplier (time sharing).
//           PWM: one shared 8-bit counter; LED on while counter < level.
// Ports
//   lane_dt   8 x 11 bits from note_table (ms to next note, 2047 = none)
//   flash     per lane, 1 while that lane's hit flash is active
//   blink     a ~8 Hz square wave for the Perfect-window blink
//   leds      bit k = lane k (lane 0 = C4 = led[15], mapped in game_top)
//=============================================================================
module led_guides (
    input  wire         clk,
    input  wire         rst,
    input  wire         tick_frame,
    input  wire         enable,
    input  wire [87:0]  lane_dt,
    input  wire [7:0]   perf_w,
    input  wire [7:0]   flash,
    input  wire         blink,
    output reg  [7:0]   leds
);
    reg  [7:0] level [0:7];
    reg  [7:0] near;                         // lane is inside the Perfect window
    reg  [3:0] lane;                         // 0..7 while computing, 8 = idle
    reg  [7:0] pwm;
    integer k;

    // two-stage pipeline: (1) pick the lane's dt and make the linear level,
    // (2) square it in the shared multiplier and store it
    wire [10:0] dt    = lane_dt[11*lane[2:0] +: 11];
    wire [9:0]  lin10 = (dt >= 11'd1000) ? 10'd0 : 10'd1023 - dt[9:0];
    reg  [7:0]  lin_q;
    reg  [2:0]  lane_q;
    reg         near_q, busy_q;
    wire [15:0] sq    = lin_q * lin_q;       // the one shared multiplier

    always @(posedge clk) begin
        if (rst) begin
            lane   <= 4'd8;
            pwm    <= 8'd0;
            near   <= 8'd0;
            busy_q <= 1'b0;
            lin_q  <= 8'd0; lane_q <= 3'd0; near_q <= 1'b0;
            for (k = 0; k < 8; k = k + 1) level[k] <= 8'd0;
        end else begin
            pwm <= pwm + 8'd1;
            // stage 1
            busy_q <= (lane != 4'd8) && !tick_frame;
            lin_q  <= lin10[9:2];
            lane_q <= lane[2:0];
            near_q <= (dt <= {3'd0, perf_w});
            if (tick_frame)          lane <= 4'd0;
            else if (lane != 4'd8)   lane <= lane + 4'd1;
            // stage 2
            if (busy_q) begin
                level[lane_q] <= sq[15:8];
                near[lane_q]  <= near_q;
            end
        end
    end

    always @(posedge clk) begin
        for (k = 0; k < 8; k = k + 1) begin
            if (!enable)       leds[k] <= flash[k];                 // guides off: hits only
            else if (flash[k]) leds[k] <= 1'b1;
            else if (near[k])  leds[k] <= blink;
            else               leds[k] <= (pwm < level[k]);
        end
    end
endmodule
