`timescale 1ns / 1ps
`include "strike_defs.vh"

module swipe_capture (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_sample,
    input  wire        tick_1ms,
    input  wire [`GS_W-1:0] game_state,
    input  wire        busy,
    input  wire        delta_valid,
    input  wire signed [11:0] delta_x,
    input  wire signed [11:0] delta_y,
    input  wire        l_press,
    input  wire        l_release,
    input  wire        r_press,
    input  wire        nudge_l,
    input  wire        nudge_r,
    input  wire [7:0]  cursor_x,
    input  wire [6:0]  cursor_y,
    input  wire [6:0]  aim_px,
    input  wire        grab_zone,
    input  wire signed [3:0] wheel,

    input  wire [6:0]  rd_addr,
    output wire [63:0] rd_data,
    output reg  [6:0]  wp,
    output reg  [7:0]  n_samples,
    output reg         grabbing,
    output reg         swipe_done,
    output reg         swipe_cancel,
    output reg         too_short,
    output reg  [15:0] stance_x,
    output reg  [2:0]  live_power,
    output wire [479:0] trail_bus,
    output reg  [31:0] trail_valid,
    output wire [6:0]  target_in,
    output wire        steer_valid,
    output wire signed [11:0] steer_dx
);

    wire in_aim = (game_state == `GS_AIM);
    wire in_lab = 1'b0;
    wire grab_ok = (in_aim && grab_zone) || (in_lab && !busy);

    reg [6:0] st_px;
    always @(*) begin
        if ((aim_px < 7'd14)) begin
            st_px = 7'd14;
        end else begin
            if ((aim_px > 7'd46)) begin
                st_px = 7'd46;
            end else begin
                st_px = aim_px;
            end
        end
    end
    reg  [6:0] st_board;
    always @(posedge clk) begin
        if (rst) st_board <= 7'd30;
        else if (in_aim && !grabbing) begin
            if (delta_valid)                         st_board <= st_px;
            else if (nudge_l && st_board > 7'd14)    st_board <= st_board - 7'd1;
            else if (nudge_r && st_board < 7'd46)    st_board <= st_board + 7'd1;
        end
    end
    always @(posedge clk) begin
        if (rst)                    stance_x <= `W_LANE_CX;
        else if (in_aim && !grabbing) stance_x <= {3'b000, st_board, 6'd32};
    end

    reg signed [4:0] tgt_off;
    wire signed [5:0] tgt_new = tgt_off - wheel;
    always @(posedge clk) begin
        if (rst) tgt_off <= 5'sd0;
        else if (in_aim && !grabbing && delta_valid && wheel != 0)
            if ((tgt_new > 6'sd15)) begin
                tgt_off <= 5'sd15;
            end else begin
                if ((tgt_new < -6'sd15)) begin
                    tgt_off <= -5'sd15;
                end else begin
                    tgt_off <= tgt_new[4:0];
                end
            end
    end
    wire signed [8:0] tgt_s = $signed({2'b00, st_board}) + tgt_off;
    assign target_in = (tgt_s < 9'sd10) ? 7'd10 : (tgt_s > 9'sd50) ? 7'd50 : tgt_s[6:0];

    reg  [63:0] ring [0:127];
    reg         wr_en;
    reg  [63:0] wr_data;
    wire [6:0]  live_addr;
    reg [6:0]  ra;
    always @(*) begin
        if (grabbing) begin
            ra = live_addr;
        end else begin
            ra = rd_addr;
        end
    end
    always @(posedge clk) if (wr_en) ring[wp] <= wr_data;
    assign rd_data = ring[ra];

    reg signed [15:0] sx, sf;
    reg signed [15:0] hx1, hx2, hx3, hf1, hf2, hf3;
    wire signed [17:0] sumx = sx + hx1 + hx2 + hx3;
    wire signed [17:0] sumf = sf + hf1 + hf2 + hf3;
    wire signed [15:0] fx = sumx[17:2];
    wire signed [15:0] ff = sumf[17:2];
    reg  [9:0] hold_samples;

    reg        live_rd;
    reg signed [15:0] ff_now;
    wire signed [15:0] ff_old = rd_data[15:0];
    wire signed [16:0] dlive  = ff_now - ff_old;

    reg        flushing;
    reg [2:0]  flush_n;
    reg        fin1, fin2;
    always @(posedge clk) begin
        wr_en <= 1'b0;
        swipe_done <= 1'b0;
        swipe_cancel <= 1'b0;
        too_short <= 1'b0;
        live_rd <= 1'b0;
        fin1 <= 1'b0;
        fin2 <= fin1;
        if (rst) begin
            grabbing <= 1'b0;
            wp <= 7'd0;
            n_samples <= 8'd0;
            sx <= 0;
            sf <= 0;
            hx1 <= 0;
            hx2 <= 0;
            hx3 <= 0;
            hf1 <= 0;
            hf2 <= 0;
            hf3 <= 0;
            hold_samples <= 0;
            live_power <= 0;
            ff_now <= 0;
            wr_data <= 0;
            flushing <= 1'b0;
            flush_n <= 3'd0;
            fin1 <= 1'b0;
            fin2 <= 1'b0;
        end else begin
            if (wr_en) wp <= wp + 7'd1;
            if (!grabbing) begin
                live_power <= 3'd0;
                flushing   <= 1'b0;
                if (l_press && grab_ok) begin
                    grabbing <= 1'b1;
                    sx <= 0;
                    sf <= 0;
                    hx1 <= 0;
                    hx2 <= 0;
                    hx3 <= 0;
                    hf1 <= 0;
                    hf2 <= 0;
                    hf3 <= 0;
                    n_samples <= 8'd0;
                    hold_samples <= 10'd0;
                end
            end else begin
                if (delta_valid && !flushing) begin
                    sx <= sx + delta_x;
                    sf <= sf - delta_y;
                end
                if (tick_sample) begin
                    wr_data <= {sx, sf, fx, ff};
                    wr_en   <= 1'b1;
                    hx3 <= hx2;
                    hx2 <= hx1;
                    hx1 <= sx;
                    hf3 <= hf2;
                    hf2 <= hf1;
                    hf1 <= sf;
                    ff_now <= ff;
                    live_rd <= (n_samples >= 8'd16);
                    if (n_samples != 8'd128) n_samples <= n_samples + 8'd1;
                    hold_samples <= hold_samples + 10'd1;
                    if (flushing) begin
                        flush_n <= flush_n + 3'd1;
                        if (flush_n == 3'd3) fin1 <= 1'b1;
                    end
                end
                if (live_rd) begin
                    if (dlive <= 0)               live_power <= 3'd0;
                    else if (dlive[16:6] > 11'd7) live_power <= 3'd7;
                    else                           live_power <= dlive[8:6];
                end
                if (fin2) begin
                    grabbing   <= 1'b0;
                    swipe_done <= 1'b1;
                end else if (!flushing && (r_press || hold_samples == 10'd600 ||
                             !(in_aim || in_lab || game_state == `GS_THROW))) begin
                    grabbing <= 1'b0;
                    swipe_cancel <= 1'b1;
                end else if (!flushing && l_release) begin
                    if (n_samples < 8'd4) begin
                        grabbing  <= 1'b0;
                        too_short <= 1'b1;
                    end else begin
                        flushing <= 1'b1;
                        flush_n  <= 3'd0;
                    end
                end
            end
        end
    end

    assign steer_valid = delta_valid && (game_state == `GS_ROLL);
    assign steer_dx    = delta_x;

    assign live_addr = wp - 7'd16;

    reg [14:0] trail [0:31];
    reg [9:0]  fade_ms;
    reg        grab_d;
    always @(posedge clk) begin
        if (rst) begin
            trail_valid <= 32'd0;
            fade_ms <= 10'd0;
            grab_d  <= 1'b0;
            trail[0] <= 15'd0;
            trail[1] <= 15'd0;
            trail[2] <= 15'd0;
            trail[3] <= 15'd0;
            trail[4] <= 15'd0;
            trail[5] <= 15'd0;
            trail[6] <= 15'd0;
            trail[7] <= 15'd0;
            trail[8] <= 15'd0;
            trail[9] <= 15'd0;
            trail[10] <= 15'd0;
            trail[11] <= 15'd0;
            trail[12] <= 15'd0;
            trail[13] <= 15'd0;
            trail[14] <= 15'd0;
            trail[15] <= 15'd0;
            trail[16] <= 15'd0;
            trail[17] <= 15'd0;
            trail[18] <= 15'd0;
            trail[19] <= 15'd0;
            trail[20] <= 15'd0;
            trail[21] <= 15'd0;
            trail[22] <= 15'd0;
            trail[23] <= 15'd0;
            trail[24] <= 15'd0;
            trail[25] <= 15'd0;
            trail[26] <= 15'd0;
            trail[27] <= 15'd0;
            trail[28] <= 15'd0;
            trail[29] <= 15'd0;
            trail[30] <= 15'd0;
            trail[31] <= 15'd0;
        end else begin
            grab_d <= grabbing;
            if (grabbing && !grab_d) begin
                trail_valid <= 32'd0;
            end else if (grabbing && tick_sample) begin
                trail[31] <= trail[30];
                trail[30] <= trail[29];
                trail[29] <= trail[28];
                trail[28] <= trail[27];
                trail[27] <= trail[26];
                trail[26] <= trail[25];
                trail[25] <= trail[24];
                trail[24] <= trail[23];
                trail[23] <= trail[22];
                trail[22] <= trail[21];
                trail[21] <= trail[20];
                trail[20] <= trail[19];
                trail[19] <= trail[18];
                trail[18] <= trail[17];
                trail[17] <= trail[16];
                trail[16] <= trail[15];
                trail[15] <= trail[14];
                trail[14] <= trail[13];
                trail[13] <= trail[12];
                trail[12] <= trail[11];
                trail[11] <= trail[10];
                trail[10] <= trail[9];
                trail[9] <= trail[8];
                trail[8] <= trail[7];
                trail[7] <= trail[6];
                trail[6] <= trail[5];
                trail[5] <= trail[4];
                trail[4] <= trail[3];
                trail[3] <= trail[2];
                trail[2] <= trail[1];
                trail[1] <= trail[0];
                trail[0]    <= {cursor_x, cursor_y};
                trail_valid <= {trail_valid[30:0], 1'b1};
                fade_ms     <= 10'd0;
            end else if (!grabbing && tick_1ms && trail_valid != 32'd0) begin
                fade_ms <= fade_ms + 10'd1;
                if (fade_ms[3:0] == 4'hF) trail_valid <= trail_valid >> 1;
            end
        end
    end
    assign trail_bus[14:0] = trail[0];
    assign trail_bus[29:15] = trail[1];
    assign trail_bus[44:30] = trail[2];
    assign trail_bus[59:45] = trail[3];
    assign trail_bus[74:60] = trail[4];
    assign trail_bus[89:75] = trail[5];
    assign trail_bus[104:90] = trail[6];
    assign trail_bus[119:105] = trail[7];
    assign trail_bus[134:120] = trail[8];
    assign trail_bus[149:135] = trail[9];
    assign trail_bus[164:150] = trail[10];
    assign trail_bus[179:165] = trail[11];
    assign trail_bus[194:180] = trail[12];
    assign trail_bus[209:195] = trail[13];
    assign trail_bus[224:210] = trail[14];
    assign trail_bus[239:225] = trail[15];
    assign trail_bus[254:240] = trail[16];
    assign trail_bus[269:255] = trail[17];
    assign trail_bus[284:270] = trail[18];
    assign trail_bus[299:285] = trail[19];
    assign trail_bus[314:300] = trail[20];
    assign trail_bus[329:315] = trail[21];
    assign trail_bus[344:330] = trail[22];
    assign trail_bus[359:345] = trail[23];
    assign trail_bus[374:360] = trail[24];
    assign trail_bus[389:375] = trail[25];
    assign trail_bus[404:390] = trail[26];
    assign trail_bus[419:405] = trail[27];
    assign trail_bus[434:420] = trail[28];
    assign trail_bus[449:435] = trail[29];
    assign trail_bus[464:450] = trail[30];
    assign trail_bus[479:465] = trail[31];
endmodule
