`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// swipe_capture.v : grab -> swipe -> release, sampled at 200 Hz
//-----------------------------------------------------------------------------
// Owner   : Student A
// Purpose : (1) Before a grab, the cursor's x position is the STANCE: the
//               ball sits under the pointer, one pixel = one inch = ~one
//               board. (2) Pressing the left button on the lane GRABS the
//               ball. While held, every mouse delta is added to a swipe
//               position (sx = sideways, sf = forward; forward is "mouse
//               away from you", which is negative screen y).
//           (3) Every 5 ms (tick_sample) the position is written into a
//               64-entry ring buffer (320 ms of history), together with a
//               4-tap moving average:  f = (s0 + s1 + s2 + s3) >> 2
//               (a shift, no divider). MouseCtl only reports every 25 ms,
//               so raw samples are a staircase; the average turns them
//               into a smooth path.
//           (4) Release -> swipe_done (gesture_features measures it).
//               Right click -> cancel. Held > 3 s (or mouse unplugged
//               mid-swipe) -> cancel, so the game can never get stuck.
//           Live feedback while held: the power level (forward motion in
//               the last 80 ms) for the LEDs/meter, and the last 32 cursor
//               positions for the trail.
// Ring entry (64 bits): {raw_x, raw_f, filt_x, filt_f}, 16-bit signed each.
//=============================================================================
module swipe_capture (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_sample,
    input  wire        tick_1ms,
    input  wire [`GS_W-1:0] game_state,
    input  wire        busy,             // gesture_features / plot still working
    input  wire        delta_valid,
    input  wire signed [11:0] delta_x,
    input  wire signed [11:0] delta_y,
    input  wire        l_press,
    input  wire        l_release,
    input  wire        r_press,
    input  wire [6:0]  cursor_x,
    input  wire [5:0]  cursor_y,
    // to gesture_features / swipe_lab_plot (read port of the ring)
    input  wire [5:0]  rd_addr,
    output wire [63:0] rd_data,
    output reg  [5:0]  wp,               // next write slot
    output reg  [6:0]  n_samples,        // 0..64 valid samples
    output reg         grabbing,
    output reg         swipe_done,       // 1-cycle: measure the swipe
    output reg         swipe_cancel,     // 1-cycle: right click / timeout
    output reg         too_short,        // 1-cycle: released after < 4 samples
    output reg  [15:0] stance_x,         // POS units, ball x before release
    output reg  [2:0]  live_power,       // 0..7 while grabbing
    output wire [415:0] trail_bus,       // 32 x {x[6:0], y[5:0]}, [12:0] newest
    output reg  [31:0] trail_valid
);
    // ---------------- where a grab is allowed -------------------------------
    wire in_aim = (game_state == `GS_AIM);
    wire in_lab = (game_state == `GS_PRACTICE_SWIPE);
    wire grab_ok = (in_aim && cursor_x < `SCR_LANE_W) || (in_lab && !busy);

    // ---------------- stance: ball centre under the pointer -----------------
    // Clamp so the whole ball (radius 4.3 in) is on the lane: 14..46 in.
    wire [6:0] st_px = (cursor_x < 7'd14) ? 7'd14 : (cursor_x > 7'd46) ? 7'd46 : cursor_x;
    always @(posedge clk) begin
        if (rst)                    stance_x <= `W_LANE_CX;
        else if (in_aim && !grabbing) stance_x <= {3'b000, st_px, 6'd32}; // pixel centre
    end

    // ---------------- ring buffer: 64 x 64-bit distributed RAM ---------------
    reg  [63:0] ring [0:63];
    reg         wr_en;
    reg  [63:0] wr_data;
    wire [5:0]  live_addr;
    wire [5:0]  ra = grabbing ? live_addr : rd_addr;   // read port shared
    always @(posedge clk) if (wr_en) ring[wp] <= wr_data;
    assign rd_data = ring[ra];

    // ---------------- swipe position, filter history ------------------------
    reg signed [15:0] sx, sf;                  // accumulated counts
    reg signed [15:0] hx1, hx2, hx3, hf1, hf2, hf3;  // last 3 raw samples
    wire signed [17:0] sumx = sx + hx1 + hx2 + hx3;
    wire signed [17:0] sumf = sf + hf1 + hf2 + hf3;
    wire signed [15:0] fx = sumx[17:2];        // >> 2 = divide by 4
    wire signed [15:0] ff = sumf[17:2];
    reg  [9:0] hold_samples;                   // timeout counter (5 ms units)

    // live power: filtered forward motion over the last 16 samples (80 ms),
    // read from the ring 1 cycle after each write (rd port is ours while held)
    reg        live_rd;
    reg signed [15:0] ff_now;
    wire signed [15:0] ff_old = rd_data[15:0];
    wire signed [16:0] dlive  = ff_now - ff_old;

    // ---------------- grab FSM ---------------------------------------------
    always @(posedge clk) begin
        wr_en <= 1'b0;
        swipe_done <= 1'b0; swipe_cancel <= 1'b0; too_short <= 1'b0;
        live_rd <= 1'b0;
        if (rst) begin
            grabbing <= 1'b0; wp <= 6'd0; n_samples <= 7'd0;
            sx <= 0; sf <= 0; hx1 <= 0; hx2 <= 0; hx3 <= 0; hf1 <= 0; hf2 <= 0; hf3 <= 0;
            hold_samples <= 0; live_power <= 0; ff_now <= 0; wr_data <= 0;
        end else if (!grabbing) begin
            live_power <= 3'd0;
            if (l_press && grab_ok) begin       // start a new swipe
                grabbing <= 1'b1;
                sx <= 0; sf <= 0; hx1 <= 0; hx2 <= 0; hx3 <= 0; hf1 <= 0; hf2 <= 0; hf3 <= 0;
                n_samples <= 7'd0; hold_samples <= 10'd0;
            end
        end else begin
            if (delta_valid) begin               // forward = mouse away = -y
                sx <= sx + delta_x;
                sf <= sf - delta_y;
            end
            if (tick_sample) begin
                wr_data <= {sx, sf, fx, ff};
                wr_en   <= 1'b1;
                hx3 <= hx2; hx2 <= hx1; hx1 <= sx;
                hf3 <= hf2; hf2 <= hf1; hf1 <= sf;
                ff_now <= ff;
                live_rd <= (n_samples >= 7'd16);
                if (n_samples != 7'd64) n_samples <= n_samples + 7'd1;
                hold_samples <= hold_samples + 10'd1;
            end
            if (wr_en) wp <= wp + 6'd1;          // advance after the write
            if (live_rd) begin                   // speed index = d >> 3, power = idx >> 3
                if (dlive <= 0)               live_power <= 3'd0;
                else if (dlive[16:6] > 11'd7) live_power <= 3'd7;
                else                           live_power <= dlive[8:6];
            end
            if (r_press || hold_samples == 10'd600 || !(in_aim || in_lab || game_state == `GS_THROW)) begin
                grabbing <= 1'b0;
                swipe_cancel <= 1'b1;
            end else if (l_release) begin
                grabbing <= 1'b0;
                if (n_samples < 7'd4) too_short  <= 1'b1;
                else                  swipe_done <= 1'b1;
            end
        end
    end

    // live read happens in the same cycle as the write of the newest sample
    // (slot wp), so 16 samples back is slot wp - 16.
    assign live_addr = wp - 6'd16;
    // ---------------- trail: last 32 cursor positions ----------------------
    reg [12:0] trail [0:31];
    reg [9:0]  fade_ms;
    reg        grab_d;
    integer k;
    always @(posedge clk) begin
        if (rst) begin
            trail_valid <= 32'd0;
            fade_ms <= 10'd0;
            grab_d  <= 1'b0;
            for (k = 0; k < 32; k = k + 1) trail[k] <= 13'd0;
        end else begin
            grab_d <= grabbing;
            if (grabbing && !grab_d) begin
                trail_valid <= 32'd0;            // a new swipe starts a new trail
            end else if (grabbing && tick_sample) begin
                for (k = 31; k > 0; k = k - 1) trail[k] <= trail[k-1];
                trail[0]    <= {cursor_x, cursor_y};
                trail_valid <= {trail_valid[30:0], 1'b1};
                fade_ms     <= 10'd0;
            end else if (!grabbing && tick_1ms && trail_valid != 32'd0) begin
                // after release the trail shrinks from its old end: 1 point / 16 ms
                fade_ms <= fade_ms + 10'd1;
                if (fade_ms[3:0] == 4'hF) trail_valid <= trail_valid >> 1;
            end
        end
    end
    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : g_tb
            assign trail_bus[13*g +: 13] = trail[g];
        end
    endgenerate
endmodule
