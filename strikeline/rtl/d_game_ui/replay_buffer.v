`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// replay_buffer.v : instant replay of the last throw, in slow motion
//-----------------------------------------------------------------------------
// Owner   : Student D
// Record  : every OLED frame (60 Hz) while the ball rolls and the pins act
//           (ROLL, PINACTION, SETTLE), one "snapshot" of what is on screen:
//             ball {visible, x, y, finger-hole angle}  23 bit
//             camera                                    11 bit
//             10 pins (pin_vis)                         240 bit
//           = 274 bits, stored as 8 words of 36 bits in a 2048 x 36 block
//           RAM (2 BRAM36): 256 snapshots = 4.3 s, the last 4.3 s are kept.
// Play    : (start) from the oldest snapshot: every 2nd frame (half speed)
//           the 8 words of the next snapshot are read (1 per clock) into
//           registers; while `active` the top-level muxes feed these
//           registers to B's and C's renderers instead of the live state.
//           The physics itself is not touched: it is only a picture.
//=============================================================================
module replay_buffer (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [`GS_W-1:0] game_state,
    input  wire        start,
    input  wire        ball_vis_in,
    input  wire [15:0] ball_x_in,
    input  wire [15:0] ball_y_in,
    input  wire [5:0]  angle_in,
    input  wire signed [10:0] cam_in,
    input  wire [239:0] pins_in,
    output reg         active,
    output reg         done,
    output reg         ball_vis,
    output reg  [15:0] ball_x,
    output reg  [15:0] ball_y,
    output reg  [5:0]  angle,
    output reg  signed [10:0] cam,
    output reg  [239:0] pins
);
    reg [35:0] ram [0:2047];
    reg        we;
    reg [10:0] wa, ra;
    reg [35:0] wd, rd;
    always @(posedge clk) begin
        if (we) ram[wa] <= wd;
        rd <= ram[ra];
    end

    // the snapshot being recorded, as 8 words
    // {pad 14, visible 1, x 6 (whole inches < 64), y 10, angle 6, camera 11, pins 240} = 288
    wire [287:0] snap = {14'd0, ball_vis_in, ball_x_in[11:6], ball_y_in[15:6], angle_in, cam_in, pins_in};
    wire recording = (game_state == `GS_ROLL) || (game_state == `GS_PINACTION) || (game_state == `GS_SETTLE);

    reg [7:0]  wslot;                 // next snapshot slot (0..255)
    reg [8:0]  count;                 // snapshots recorded for this throw (max 256)
    reg [3:0]  wi;                    // word being written
    reg        wbusy;
    reg [287:0] snap_l;
    reg        was_rec;

    localparam P_IDLE = 2'd0, P_WAIT = 2'd1, P_READ = 2'd2;
    reg [1:0]  ps;
    reg [7:0]  rslot;
    reg [8:0]  left;                  // snapshots still to show
    reg [3:0]  ri;
    reg        half;
    reg [287:0] acc;
    wire [287:0] full7 = {rd, acc[287:36]};     // word 7 on top of words 0..6 (after 7 shifts)

    always @(posedge clk) begin
        we <= 1'b0; done <= 1'b0;
        if (rst) begin
            wslot <= 0; count <= 0; wi <= 0; wbusy <= 0; snap_l <= 0; was_rec <= 0;
            ps <= P_IDLE; rslot <= 0; left <= 0; ri <= 0; half <= 0; acc <= 0; active <= 0;
            wa <= 0; ra <= 0; wd <= 0;
            ball_vis <= 0; ball_x <= 0; ball_y <= 0; angle <= 0; cam <= 0; pins <= 0;
        end else begin
            // ---------------- record ----------------
            was_rec <= recording;
            if (recording && !was_rec) count <= 0;                  // a new throw
            if (recording && tick_frame && !wbusy && !active) begin
                snap_l <= snap; wi <= 0; wbusy <= 1;
            end
            if (wbusy) begin                     // shift the snapshot out, 36 bits per clock
                we <= 1'b1; wa <= {wslot, wi[2:0]}; wd <= snap_l[35:0];
                snap_l <= snap_l >> 36;
                wi <= wi + 4'd1;
                if (wi == 4'd7) begin
                    wbusy <= 0; wslot <= wslot + 8'd1;
                    if (count != 9'd256) count <= count + 9'd1;
                end
            end
            // ---------------- play ----------------
            case (ps)
                P_IDLE: if (start && count != 0) begin
                    active <= 1; rslot <= wslot - count[7:0]; left <= count; half <= 0;
                    ps <= P_WAIT;
                end else if (start) done <= 1'b1;
                P_WAIT: if (tick_frame) begin
                    half <= ~half;
                    if (!half) begin
                        if (left == 0) begin active <= 0; done <= 1'b1; ps <= P_IDLE; end
                        else begin ri <= 0; ra <= {rslot, 3'd0}; ps <= P_READ; end
                    end
                end
                P_READ: begin                 // rd belongs to the address set one clock earlier
                    ri <= ri + 4'd1;
                    ra <= {rslot, ri[2:0] + 3'd1};
                    if (ri != 0) acc <= {rd, acc[287:36]};   // shift in: word 0 ends at the bottom
                    if (ri == 4'd8) begin              // rd = word 7 now: unpack the snapshot
                        pins     <= full7[239:0];
                        cam      <= full7[250:240];
                        ps <= P_WAIT; rslot <= rslot + 8'd1; left <= left - 9'd1;
                        {ball_vis, ball_x, ball_y} <= {full7[273], 4'd0, full7[272:267], 6'd32, full7[266:257], 6'd32};
                        angle    <= full7[256:251];
                    end
                end
                default: ps <= P_IDLE;
            endcase
        end
    end
endmodule
