`timescale 1ns / 1ps
// gesture_render.v : everything A draws, plus led[15:10]
// Owner: Student A
`include "strike_defs.vh"

module gesture_render (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [7:0]  vx,
    input  wire [6:0]  vy,
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire        scr,
    input  wire [`GS_W-1:0] game_state,
    input  wire        fp,
    input  wire        lefty,
    input  wire [7:0]  cursor_x,
    input  wire [6:0]  cursor_y,
    input  wire [6:0]  ucur_x,
    input  wire [5:0]  ucur_y,
    input  wire        grabbing,
    input  wire [479:0] trail_bus,
    input  wire [31:0] trail_valid,
    input  wire [15:0] stance_x,
    input  wire signed [10:0] cam_y,
    input  wire [2:0]  live_power,
    input  wire        throw_valid,
    input  wire signed [`SPIN_W-1:0] throw_spin,
    input  wire [7:0]  throw_mph10,
    input  wire [2:0]  aim_level,
    input  wire        aim_right,
    input  wire        reject,
    input  wire [1:0]  reject_msg,
    input  wire        cancel,
    input  wire [7:0]  n_samples,
    output reg  [15:0] color,
    output reg         en,
    output reg  [`TX_W-1:0] txt,
    output reg  [15:0] cur_color,
    output reg         cur_en,
    output reg  [5:0]  led_a
);
`include "strings_map.vh"

    reg [`SPIN_W-2:0] tsp_abs;
    always @(*) begin
        if (throw_spin[`SPIN_W-1]) begin
            tsp_abs = -throw_spin[`SPIN_W-2:0];
        end else begin
            tsp_abs = throw_spin[`SPIN_W-2:0];
        end
    end
    wire [`SPIN_W-1:0] tsp_q   = ({1'b0, tsp_abs} + 6'd3) >> 2;
    reg [`SPIN_W-1:0] tsp_l;
    always @(*) begin
        if ((tsp_q > 6'd7)) begin
            tsp_l = 6'd7;
        end else begin
            tsp_l = tsp_q;
        end
    end
    reg signed [3:0] spin_lvl;
    always @(*) begin
        if ((tsp_abs == 0)) begin
            spin_lvl = 4'sd0;
        end else begin
            if (throw_spin[`SPIN_W-1]) begin
                spin_lvl = -$signed({1'b0, tsp_l[2:0]});
            end else begin
                spin_lvl = $signed({1'b0, tsp_l[2:0]});
            end
        end
    end
    reg [7:0] l_mph;  reg signed [3:0] l_spin;  reg [2:0] l_aim;  reg l_right;  reg [6:0] l_n;
    reg [7:0] lbl_frames, msg_frames;
    reg [1:0] msg;
    always @(posedge clk) begin
        if (rst) begin
            l_mph <= 0;
            l_spin <= 0;
            l_aim <= 0;
            l_right <= 0;
            l_n <= 0;
            lbl_frames <= 0;
            msg_frames <= 0;
            msg <= 0;
        end else begin
            if (throw_valid) begin
                l_mph <= throw_mph10;
                l_spin <= spin_lvl;
                l_aim <= aim_level;
                l_right <= aim_right;
                if ((n_samples > 8'd99)) begin
                    l_n <= 7'd99;
                end else begin
                    l_n <= n_samples[6:0];
                end lbl_frames <= 8'd150;
                msg_frames <= 0;
            end else if (reject || cancel) begin
                if (cancel) begin
                    msg <= `GM_CANCEL;
                end else begin
                    msg <= reject_msg;
                end msg_frames <= 8'd90;
                lbl_frames <= 0;
            end else if (tick_frame) begin
                if (lbl_frames != 0) lbl_frames <= lbl_frames - 8'd1;
                if (msg_frames != 0) msg_frames <= msg_frames - 8'd1;
            end
        end
    end

    reg [3:0] m_h;
    always @(*) begin
        if ((l_mph >= 8'd200)) begin
            m_h = 4'd2;
        end else begin
            if ((l_mph >= 8'd100)) begin
                m_h = 4'd1;
            end else begin
                m_h = 4'd0;
            end
        end
    end
    wire [7:0] m_r = l_mph - ((m_h == 2) ? 8'd200 : (m_h == 1) ? 8'd100 : 8'd0);
    reg [3:0] m_t;
    always @(*) begin
        if ((m_r >= 90)) begin
            m_t = 9;
        end else begin
            if ((m_r >= 80)) begin
                m_t = 8;
            end else begin
                if ((m_r >= 70)) begin
                    m_t = 7;
                end else begin
                    if ((m_r >= 60)) begin
                        m_t = 6;
                    end else begin
                        if ((m_r >= 50)) begin
                            m_t = 5;
                        end else begin
                            if ((m_r >= 40)) begin
                                m_t = 4;
                            end else begin
                                if ((m_r >= 30)) begin
                                    m_t = 3;
                                end else begin
                                    if ((m_r >= 20)) begin
                                        m_t = 2;
                                    end else begin
                                        if ((m_r >= 10)) begin
                                            m_t = 1;
                                        end else begin
                                            m_t = 0;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    wire [7:0] m_o8 = m_r - {m_t, 3'b000} - {3'b000, m_t, 1'b0};
    wire [3:0] m_o = m_o8[3:0];
    reg [3:0] spin_mag;
    always @(*) begin
        if (l_spin[3]) begin
            spin_mag = -l_spin;
        end else begin
            spin_mag = l_spin;
        end
    end

    reg [3:0] n_t;
    always @(*) begin
        if ((l_n >= 7'd90)) begin
            n_t = 4'd9;
        end else begin
            if ((l_n >= 7'd80)) begin
                n_t = 4'd8;
            end else begin
                if ((l_n >= 7'd70)) begin
                    n_t = 4'd7;
                end else begin
                    if ((l_n >= 7'd60)) begin
                        n_t = 4'd6;
                    end else begin
                        if ((l_n >= 7'd50)) begin
                            n_t = 4'd5;
                        end else begin
                            if ((l_n >= 7'd40)) begin
                                n_t = 4'd4;
                            end else begin
                                if ((l_n >= 7'd30)) begin
                                    n_t = 4'd3;
                                end else begin
                                    if ((l_n >= 7'd20)) begin
                                        n_t = 4'd2;
                                    end else begin
                                        if ((l_n >= 7'd10)) begin
                                            n_t = 4'd1;
                                        end else begin
                                            n_t = 4'd0;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    wire [6:0] n_o7 = l_n - {n_t, 3'b000} - {2'b00, n_t, 1'b0};
    wire [3:0] n_o = n_o7[3:0];

    wire in_lane  = (px_x < `SCR_LANE_W);
    wire in_game  = (game_state >= `GS_AIM && game_state <= `GS_SWEEP);
    wire aiming   = (game_state == `GS_AIM) || (game_state == `GS_THROW);
    wire [6:0] bx = stance_x[12:6];
    wire signed [11:0] ball_row  = 12'sd63 - (12'sd5 - cam_y);
    wire signed [11:0] foul_row  = 12'sd63 + cam_y;
    wire signed [11:0] py_s      = {6'd0, px_y};
    reg [6:0] adxb;
    always @(*) begin
        if ((px_x > bx)) begin
            adxb = px_x - bx;
        end else begin
            adxb = bx - px_x;
        end
    end
    wire signed [11:0] sm = py_s - foul_row - 12'sd3;

    reg       tr_hit;
    reg [4:0] tr_age;
    always @(*) begin
        tr_hit = 0;
        tr_age = 0;
        if (trail_valid[31] && trail_bus[479:472] == vx && trail_bus[471:465] == vy) begin
            tr_hit = 1;
            tr_age = 5'd31;
        end
        if (trail_valid[30] && trail_bus[464:457] == vx && trail_bus[456:450] == vy) begin
            tr_hit = 1;
            tr_age = 5'd30;
        end
        if (trail_valid[29] && trail_bus[449:442] == vx && trail_bus[441:435] == vy) begin
            tr_hit = 1;
            tr_age = 5'd29;
        end
        if (trail_valid[28] && trail_bus[434:427] == vx && trail_bus[426:420] == vy) begin
            tr_hit = 1;
            tr_age = 5'd28;
        end
        if (trail_valid[27] && trail_bus[419:412] == vx && trail_bus[411:405] == vy) begin
            tr_hit = 1;
            tr_age = 5'd27;
        end
        if (trail_valid[26] && trail_bus[404:397] == vx && trail_bus[396:390] == vy) begin
            tr_hit = 1;
            tr_age = 5'd26;
        end
        if (trail_valid[25] && trail_bus[389:382] == vx && trail_bus[381:375] == vy) begin
            tr_hit = 1;
            tr_age = 5'd25;
        end
        if (trail_valid[24] && trail_bus[374:367] == vx && trail_bus[366:360] == vy) begin
            tr_hit = 1;
            tr_age = 5'd24;
        end
        if (trail_valid[23] && trail_bus[359:352] == vx && trail_bus[351:345] == vy) begin
            tr_hit = 1;
            tr_age = 5'd23;
        end
        if (trail_valid[22] && trail_bus[344:337] == vx && trail_bus[336:330] == vy) begin
            tr_hit = 1;
            tr_age = 5'd22;
        end
        if (trail_valid[21] && trail_bus[329:322] == vx && trail_bus[321:315] == vy) begin
            tr_hit = 1;
            tr_age = 5'd21;
        end
        if (trail_valid[20] && trail_bus[314:307] == vx && trail_bus[306:300] == vy) begin
            tr_hit = 1;
            tr_age = 5'd20;
        end
        if (trail_valid[19] && trail_bus[299:292] == vx && trail_bus[291:285] == vy) begin
            tr_hit = 1;
            tr_age = 5'd19;
        end
        if (trail_valid[18] && trail_bus[284:277] == vx && trail_bus[276:270] == vy) begin
            tr_hit = 1;
            tr_age = 5'd18;
        end
        if (trail_valid[17] && trail_bus[269:262] == vx && trail_bus[261:255] == vy) begin
            tr_hit = 1;
            tr_age = 5'd17;
        end
        if (trail_valid[16] && trail_bus[254:247] == vx && trail_bus[246:240] == vy) begin
            tr_hit = 1;
            tr_age = 5'd16;
        end
        if (trail_valid[15] && trail_bus[239:232] == vx && trail_bus[231:225] == vy) begin
            tr_hit = 1;
            tr_age = 5'd15;
        end
        if (trail_valid[14] && trail_bus[224:217] == vx && trail_bus[216:210] == vy) begin
            tr_hit = 1;
            tr_age = 5'd14;
        end
        if (trail_valid[13] && trail_bus[209:202] == vx && trail_bus[201:195] == vy) begin
            tr_hit = 1;
            tr_age = 5'd13;
        end
        if (trail_valid[12] && trail_bus[194:187] == vx && trail_bus[186:180] == vy) begin
            tr_hit = 1;
            tr_age = 5'd12;
        end
        if (trail_valid[11] && trail_bus[179:172] == vx && trail_bus[171:165] == vy) begin
            tr_hit = 1;
            tr_age = 5'd11;
        end
        if (trail_valid[10] && trail_bus[164:157] == vx && trail_bus[156:150] == vy) begin
            tr_hit = 1;
            tr_age = 5'd10;
        end
        if (trail_valid[9] && trail_bus[149:142] == vx && trail_bus[141:135] == vy) begin
            tr_hit = 1;
            tr_age = 5'd9;
        end
        if (trail_valid[8] && trail_bus[134:127] == vx && trail_bus[126:120] == vy) begin
            tr_hit = 1;
            tr_age = 5'd8;
        end
        if (trail_valid[7] && trail_bus[119:112] == vx && trail_bus[111:105] == vy) begin
            tr_hit = 1;
            tr_age = 5'd7;
        end
        if (trail_valid[6] && trail_bus[104:97] == vx && trail_bus[96:90] == vy) begin
            tr_hit = 1;
            tr_age = 5'd6;
        end
        if (trail_valid[5] && trail_bus[89:82] == vx && trail_bus[81:75] == vy) begin
            tr_hit = 1;
            tr_age = 5'd5;
        end
        if (trail_valid[4] && trail_bus[74:67] == vx && trail_bus[66:60] == vy) begin
            tr_hit = 1;
            tr_age = 5'd4;
        end
        if (trail_valid[3] && trail_bus[59:52] == vx && trail_bus[51:45] == vy) begin
            tr_hit = 1;
            tr_age = 5'd3;
        end
        if (trail_valid[2] && trail_bus[44:37] == vx && trail_bus[36:30] == vy) begin
            tr_hit = 1;
            tr_age = 5'd2;
        end
        if (trail_valid[1] && trail_bus[29:22] == vx && trail_bus[21:15] == vy) begin
            tr_hit = 1;
            tr_age = 5'd1;
        end
        if (trail_valid[0] && trail_bus[14:7] == vx && trail_bus[6:0] == vy) begin
            tr_hit = 1;
            tr_age = 5'd0;
        end
    end
    wire [4:0] tr_lvl = 5'd31 - tr_age;
    wire [15:0] tr_col = {tr_lvl, tr_lvl, 1'b0, tr_lvl[4:1], 1'b0};

    wire [4:0] mcol = px_x[6:2];
    wire [1:0] mfx  = px_x[1:0];
    wire [12:0] my43 = ({7'd0, px_y} << 5) + ({7'd0, px_y} << 3) + ({7'd0, px_y} << 1) + px_y;
    wire [3:0] mrow = my43[11:8];
    wire [5:0] mfy6 = px_y - {mrow, 2'b00} - {1'b0, mrow, 1'b0};
    wire [2:0] mfy  = mfy6[2:0];

    reg [6:0] board;
    always @(*) begin
        if (lefty) begin
            board = bx - 7'd8;
        end else begin
            board = 7'd51 - bx;
        end
    end
    reg [3:0] bd_t;
    always @(*) begin
        if ((board >= 7'd30)) begin
            bd_t = 4'd3;
        end else begin
            if ((board >= 7'd20)) begin
                bd_t = 4'd2;
            end else begin
                if ((board >= 7'd10)) begin
                    bd_t = 4'd1;
                end else begin
                    bd_t = 4'd0;
                end
            end
        end
    end
    wire [6:0] bd_o7 = board - {bd_t, 3'b000} - {2'b00, bd_t, 1'b0};
    wire [3:0] bd_o = bd_o7[3:0];

    wire in_pnl = (px_x >= `SCR_HUD_X0) && (px_y >= `SCR_MTR_Y0) && in_game && !fp;
    reg [2:0] pow;
    always @(*) begin
        if (grabbing) begin
            pow = live_power;
        end else begin
            if ((lbl_frames != 0)) begin
                if ((l_mph >= 8'd210)) begin
                    pow = 3'd7;
                end else begin
                    if ((l_mph >= 8'd190)) begin
                        pow = 3'd6;
                    end else begin
                        if ((l_mph >= 8'd175)) begin
                            pow = 3'd5;
                        end else begin
                            if ((l_mph >= 8'd160)) begin
                                pow = 3'd4;
                            end else begin
                                if ((l_mph >= 8'd145)) begin
                                    pow = 3'd3;
                                end else begin
                                    if ((l_mph >= 8'd130)) begin
                                        pow = 3'd2;
                                    end else begin
                                        pow = 3'd1;
                                    end
                                end
                            end
                        end
                    end
                end
            end else begin
                pow = 3'd0;
            end
        end
    end
    wire [6:0] pow_end = 7'd72 + {1'b0, pow, 1'b0} + {2'b00, pow};

    reg signed [7:0] spin_px;
    always @(*) begin
        if ((lbl_frames != 0)) begin
            spin_px = -({{4{l_spin[3]}}, l_spin} <<< 1);
        end else begin
            spin_px = 8'sd0;
        end
    end
    wire signed [7:0] dxc = $signed({1'b0, px_x}) - 8'sd83;

    wire [`TX_W-1:0] text0;
    wire [10:0] text0_address = `S_POWERW + (mcol - 5'd18);
    wire  text0_font = 1'b1;
    wire [2:0] text0_fx = {1'b0, mfx};
    wire [2:0] text0_fy = mfy;
    wire [15:0] text0_fg = 16'hAD55;
    wire [15:0] text0_bg = 0;
    wire  text0_bgen = 1'b0;
    gesture_text_string text_request0 (
        .address(text0_address),
        .font(text0_font),
        .fx(text0_fx),
        .fy(text0_fy),
        .fg(text0_fg),
        .bg(text0_bg),
        .bgen(text0_bgen),
        .request(text0)
    );
    wire [`TX_W-1:0] text1;
    wire [10:0] text1_address = `S_LABW + 8 + (mcol - 5'd18);
    wire  text1_font = 1'b1;
    wire [2:0] text1_fx = {1'b0, mfx};
    wire [2:0] text1_fy = mfy;
    wire [15:0] text1_fg = 16'hAD55;
    wire [15:0] text1_bg = 0;
    wire  text1_bgen = 1'b0;
    gesture_text_string text_request1 (
        .address(text1_address),
        .font(text1_font),
        .fx(text1_fx),
        .fy(text1_fy),
        .fg(text1_fg),
        .bg(text1_bg),
        .bgen(text1_bgen),
        .request(text1)
    );
    wire [`TX_W-1:0] text2;
    wire [10:0] text2_address = `S_AMSG + {msg, 3'b000} + {msg, 2'b00} + msg + mcol;
    wire  text2_font = 1'b1;
    wire [2:0] text2_fx = {1'b0, mfx};
    wire [2:0] text2_fy = mfy;
    wire [15:0] text2_fg = `C_RED;
    wire [15:0] text2_bg = `C_BLACK;
    wire  text2_bgen = 1'b1;
    gesture_text_string text_request2 (
        .address(text2_address),
        .font(text2_font),
        .fx(text2_fx),
        .fy(text2_fy),
        .fg(text2_fg),
        .bg(text2_bg),
        .bgen(text2_bgen),
        .request(text2)
    );
    wire [`TX_W-1:0] text3;
    wire [10:0] text3_address = `S_STRT + mcol;
    wire  text3_font = 1'b1;
    wire [2:0] text3_fx = {1'b0, mfx};
    wire [2:0] text3_fy = mfy;
    wire [15:0] text3_fg = `C_WHITE;
    wire [15:0] text3_bg = `C_BLACK;
    wire  text3_bgen = 1'b1;
    gesture_text_string text_request3 (
        .address(text3_address),
        .font(text3_font),
        .fx(text3_fx),
        .fy(text3_fy),
        .fg(text3_fg),
        .bg(text3_bg),
        .bgen(text3_bgen),
        .request(text3)
    );
    wire [`TX_W-1:0] text4;
    wire [10:0] text4_address = `S_HOOKW + mcol;
    wire  text4_font = 1'b1;
    wire [2:0] text4_fx = {1'b0, mfx};
    wire [2:0] text4_fy = mfy;
    wire [15:0] text4_fg = `C_YELLOW;
    wire [15:0] text4_bg = `C_BLACK;
    wire  text4_bgen = 1'b1;
    gesture_text_string text_request4 (
        .address(text4_address),
        .font(text4_font),
        .fx(text4_fx),
        .fy(text4_fy),
        .fg(text4_fg),
        .bg(text4_bg),
        .bgen(text4_bgen),
        .request(text4)
    );
    wire [`TX_W-1:0] text5;
    wire [10:0] text5_address = `S_LABW + 16;
    wire  text5_font = 1'b1;
    wire [2:0] text5_fx = {1'b0, mfx};
    wire [2:0] text5_fy = mfy;
    wire [15:0] text5_fg = `C_YELLOW;
    wire [15:0] text5_bg = `C_BLACK;
    wire  text5_bgen = 1'b1;
    gesture_text_string text_request5 (
        .address(text5_address),
        .font(text5_font),
        .fx(text5_fx),
        .fy(text5_fy),
        .fg(text5_fg),
        .bg(text5_bg),
        .bgen(text5_bgen),
        .request(text5)
    );
    wire [`TX_W-1:0] text6;
    wire [10:0] text6_address = `S_LABW + 17;
    wire  text6_font = 1'b1;
    wire [2:0] text6_fx = {1'b0, mfx};
    wire [2:0] text6_fy = mfy;
    wire [15:0] text6_fg = `C_YELLOW;
    wire [15:0] text6_bg = `C_BLACK;
    wire  text6_bgen = 1'b1;
    gesture_text_string text_request6 (
        .address(text6_address),
        .font(text6_font),
        .fx(text6_fx),
        .fy(text6_fy),
        .fg(text6_fg),
        .bg(text6_bg),
        .bgen(text6_bgen),
        .request(text6)
    );
    wire [`TX_W-1:0] text7;
    wire [5:0] text7_code = l_spin[3] ? 6'd50 : 6'd44;
    wire  text7_font = 1'b1;
    wire [2:0] text7_fx = {1'b0, mfx};
    wire [2:0] text7_fy = mfy;
    wire [15:0] text7_fg = `C_YELLOW;
    wire [15:0] text7_bg = `C_BLACK;
    wire  text7_bgen = 1'b1;
    gesture_text_literal text_request7 (
        .code(text7_code),
        .font(text7_font),
        .fx(text7_fx),
        .fy(text7_fy),
        .fg(text7_fg),
        .bg(text7_bg),
        .bgen(text7_bgen),
        .request(text7)
    );
    wire [`TX_W-1:0] text8;
    wire [5:0] text8_code = (6'd16 + {2'b00, spin_mag});
    wire  text8_font = 1'b1;
    wire [2:0] text8_fx = {1'b0, mfx};
    wire [2:0] text8_fy = mfy;
    wire [15:0] text8_fg = `C_YELLOW;
    wire [15:0] text8_bg = `C_BLACK;
    wire  text8_bgen = 1'b1;
    gesture_text_literal text_request8 (
        .code(text8_code),
        .font(text8_font),
        .fx(text8_fx),
        .fy(text8_fy),
        .fg(text8_fg),
        .bg(text8_bg),
        .bgen(text8_bgen),
        .request(text8)
    );
    wire [`TX_W-1:0] text9;
    wire [5:0] text9_code = m_h == 0 ? 6'd0 : (6'd16 + {2'b00, m_h});
    wire  text9_font = 1'b1;
    wire [2:0] text9_fx = {1'b0, mfx};
    wire [2:0] text9_fy = mfy;
    wire [15:0] text9_fg = `C_WHITE;
    wire [15:0] text9_bg = `C_BLACK;
    wire  text9_bgen = 1'b1;
    gesture_text_literal text_request9 (
        .code(text9_code),
        .font(text9_font),
        .fx(text9_fx),
        .fy(text9_fy),
        .fg(text9_fg),
        .bg(text9_bg),
        .bgen(text9_bgen),
        .request(text9)
    );
    wire [`TX_W-1:0] text10;
    wire [5:0] text10_code = (6'd16 + {2'b00, m_t});
    wire  text10_font = 1'b1;
    wire [2:0] text10_fx = {1'b0, mfx};
    wire [2:0] text10_fy = mfy;
    wire [15:0] text10_fg = `C_WHITE;
    wire [15:0] text10_bg = `C_BLACK;
    wire  text10_bgen = 1'b1;
    gesture_text_literal text_request10 (
        .code(text10_code),
        .font(text10_font),
        .fx(text10_fx),
        .fy(text10_fy),
        .fg(text10_fg),
        .bg(text10_bg),
        .bgen(text10_bgen),
        .request(text10)
    );
    wire [`TX_W-1:0] text11;
    wire [5:0] text11_code = 6'd14;
    wire  text11_font = 1'b1;
    wire [2:0] text11_fx = {1'b0, mfx};
    wire [2:0] text11_fy = mfy;
    wire [15:0] text11_fg = `C_WHITE;
    wire [15:0] text11_bg = `C_BLACK;
    wire  text11_bgen = 1'b1;
    gesture_text_literal text_request11 (
        .code(text11_code),
        .font(text11_font),
        .fx(text11_fx),
        .fy(text11_fy),
        .fg(text11_fg),
        .bg(text11_bg),
        .bgen(text11_bgen),
        .request(text11)
    );
    wire [`TX_W-1:0] text12;
    wire [5:0] text12_code = (6'd16 + {2'b00, m_o});
    wire  text12_font = 1'b1;
    wire [2:0] text12_fx = {1'b0, mfx};
    wire [2:0] text12_fy = mfy;
    wire [15:0] text12_fg = `C_WHITE;
    wire [15:0] text12_bg = `C_BLACK;
    wire  text12_bgen = 1'b1;
    gesture_text_literal text_request12 (
        .code(text12_code),
        .font(text12_font),
        .fx(text12_fx),
        .fy(text12_fy),
        .fg(text12_fg),
        .bg(text12_bg),
        .bgen(text12_bgen),
        .request(text12)
    );
    wire [`TX_W-1:0] text13;
    wire [5:0] text13_code = (6'd16 + {2'b00, bd_t});
    wire  text13_font = 1'b1;
    wire [2:0] text13_fx = {1'b0, mfx};
    wire [2:0] text13_fy = mfy;
    wire [15:0] text13_fg = `C_YELLOW;
    wire [15:0] text13_bg = `C_BLACK;
    wire  text13_bgen = 1'b1;
    gesture_text_literal text_request13 (
        .code(text13_code),
        .font(text13_font),
        .fx(text13_fx),
        .fy(text13_fy),
        .fg(text13_fg),
        .bg(text13_bg),
        .bgen(text13_bgen),
        .request(text13)
    );
    wire [`TX_W-1:0] text14;
    wire [5:0] text14_code = (6'd16 + {2'b00, bd_o});
    wire  text14_font = 1'b1;
    wire [2:0] text14_fx = {1'b0, mfx};
    wire [2:0] text14_fy = mfy;
    wire [15:0] text14_fg = `C_YELLOW;
    wire [15:0] text14_bg = `C_BLACK;
    wire  text14_bgen = 1'b1;
    gesture_text_literal text_request14 (
        .code(text14_code),
        .font(text14_font),
        .fx(text14_fx),
        .fy(text14_fy),
        .fg(text14_fg),
        .bg(text14_bg),
        .bgen(text14_bgen),
        .request(text14)
    );
    wire [`TX_W-1:0] text15;
    wire [5:0] text15_code = 6'd0;
    wire  text15_font = 1'b1;
    wire [2:0] text15_fx = {1'b0, mfx};
    wire [2:0] text15_fy = mfy;
    wire [15:0] text15_fg = `C_YELLOW;
    wire [15:0] text15_bg = `C_BLACK;
    wire  text15_bgen = 1'b1;
    gesture_text_literal text_request15 (
        .code(text15_code),
        .font(text15_font),
        .fx(text15_fx),
        .fy(text15_fy),
        .fg(text15_fg),
        .bg(text15_bg),
        .bgen(text15_bgen),
        .request(text15)
    );

    always @(*) begin
        en = 1'b0; color = `C_BLACK; txt = {`TX_W{1'b0}};
        if (in_game) begin
            if (!scr && tr_hit && (grabbing || aiming || trail_valid != 0)) begin
                en = 1'b1; color = tr_col;
            end else if (in_lane && aiming && !fp && !grabbing && px_x == bx && py_s < ball_row - 12'sd6 && px_y[1:0] == 2'b00) begin
                en = 1'b1; color = 16'hC618;
            end else if (in_lane && aiming && !fp && sm >= 0 && sm <= 2 && adxb <= {5'd0, sm[1:0]}) begin
                en = 1'b1; color = `C_YELLOW;
            end

            if (in_pnl) begin
                if (px_y >= 6'd43 && px_y <= 6'd46 && px_x >= 7'd72 && px_x <= 7'd93) begin
                    en = 1'b1;
                    color = (px_x < pow_end) ? ((pow >= 3'd6) ? `C_RED : (pow >= 3'd4) ? `C_ORANGE : `C_GREEN) : 16'h2104;
                end else if (px_y >= 6'd56 && px_y <= 6'd59 && px_x >= 7'd72 && px_x <= 7'd94) begin
                    en = 1'b1;
                    if (dxc == 0) color = `C_WHITE;
                    else if (spin_px < 0 && dxc < 0 && dxc >= spin_px) color = `C_CYAN;
                    else if (spin_px > 0 && dxc > 0 && dxc <= spin_px) color = `C_MAGENTA;
                    else color = 16'h2104;
                end
                if (mrow == 4'd6 && mcol >= 5'd18 && mcol < 5'd21)
                    txt = text0;
                else if (mrow == 4'd8 && mcol >= 5'd18 && mcol < 5'd22)
                    txt = text1;
            end

            if (in_lane && mrow == 4'd0 && !fp) begin
                if (msg_frames != 0 && mcol < 5'd13)
                    txt = text2;
                else if (lbl_frames != 0 && mcol < 5'd14) begin
                    if (l_spin == 0) begin
                        if (mcol < 5'd8) txt = text3;
                    end else begin
                        if (mcol < 5'd4) txt = text4;
                        else if (mcol == 5'd5) txt = text7;
                        else if (mcol == 5'd6) txt = text8;
                    end
                    case (mcol)
                        5'd9:  txt = text9;
                        5'd10: txt = text10;
                        5'd11: txt = text11;
                        5'd12: txt = text12;
                        default: ;
                    endcase
                end else if (aiming && !grabbing && mcol < 5'd5) begin
                    case (mcol)
                        5'd0: txt = text5;
                        5'd1: txt = text6;
                        5'd3: txt = text13;
                        5'd4: txt = text14;
                        default: txt = text15;
                    endcase
                end
            end
        end
    end

    reg signed [8:0] cdx;
    always @(*) begin
        if (scr) begin
            cdx = $signed({2'b00, px_x}) - $signed({2'b00, ucur_x});
        end else begin
            cdx = $signed({1'b0, vx})    - $signed({1'b0, cursor_x});
        end
    end
    reg signed [8:0] cdy;
    always @(*) begin
        if (scr) begin
            cdy = $signed({3'b000, px_y}) - $signed({3'b000, ucur_y});
        end else begin
            cdy = $signed({2'b00, vy})    - $signed({2'b00, cursor_y});
        end
    end
    wire show_cur = !(game_state >= `GS_ROLL && game_state <= `GS_SWEEP) && game_state != `GS_REPLAY &&
                    !(scr && in_game);
    always @(*) begin
        cur_en = 1'b0; cur_color = `C_WHITE;
        if (show_cur) begin
            if (in_game) begin
                if (grabbing) begin
                    if (cdx >= -1 && cdx <= 1 && cdy >= -1 && cdy <= 1) begin
                        cur_en = 1'b1; cur_color = `C_YELLOW;
                    end
                end else if ((cdx == 0 && cdy >= -2 && cdy <= 2) || (cdy == 0 && cdx >= -2 && cdx <= 2)) begin
                    cur_en = 1'b1; cur_color = (cdx == 0 && cdy == 0) ? `C_BLACK : `C_YELLOW;
                end
            end else if (cdx >= 0 && cdy >= 0 && cdy <= 6 && cdx <= cdy && cdx <= 4) begin
                cur_en = 1'b1;
                cur_color = (cdx == 0 || cdx == cdy || cdy == 6 || (cdx == 4)) ? `C_BLACK : `C_WHITE;
                if (cdy == 6 && cdx > 2) cur_en = 1'b0;
            end
        end
    end

    always @(*) begin
        led_a = 6'd0;
        if (grabbing) begin
            led_a = (live_power >= 3'd6) ? 6'b111111 : ~(6'b111111 << live_power);
        end else if (lbl_frames != 0 && l_spin != 0) begin
            if (!l_spin[3]) led_a = ~(6'b111111 >> ((spin_mag > 4'd6) ? 3'd6 : spin_mag[2:0]));
            else            led_a = ~(6'b111111 << ((spin_mag > 4'd6) ? 3'd6 : spin_mag[2:0]));
        end
    end
endmodule

module gesture_text_string (
    input wire [10:0] address,
    input wire font,
    input wire [2:0] fx, fy,
    input wire [15:0] fg, bg,
    input wire bgen,
    output wire [`TX_W-1:0] request
);
    assign request = {bgen, bg, fg, fy, fx, font, address, 1'b0, 1'b1};
endmodule

module gesture_text_literal (
    input wire [5:0] code,
    input wire font,
    input wire [2:0] fx, fy,
    input wire [15:0] fg, bg,
    input wire bgen,
    output wire [`TX_W-1:0] request
);
    assign request = {bgen, bg, fg, fy, fx, font, 5'd0, code, 1'b1, 1'b1};
endmodule
