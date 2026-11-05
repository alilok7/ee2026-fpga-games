`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// gesture_render.v : everything A draws, plus led[15:10]
//-----------------------------------------------------------------------------
// Owner   : Student A
// World layer (between the ball and D's overlays):
//   AIM    a dotted target line straight up from the ball and a yellow
//          stance marker on the approach; "BD 20" = the board you stand on
//          (counted from your throwing side, as in real bowling)
//   SWIPE  the trail: the last 32 pointer positions, newest brightest
//   AFTER  label "HOOK L3 17.2" / "STRAIGHT 15.0" for 2.5 s, or the reason a
//          swipe was refused ("SWIPE FASTER" ...) for 1.5 s
//   PANEL  POWER bar (live while swiping, then the throw's speed) and SPIN
//          bar (left/right of centre) in x 71..95, y 36..63
//   (the v2-v3.4 Swipe Lab screen was removed in v3.5 with the practice section)
// Cursor layer (on top of everything): an arrow in menus, a crosshair on
//   the lane, a filled dot while the ball is held.
// LEDs: power level while swiping; after the throw, spin as a bar that
//   grows from the left (hook left) or right (hook right) end.
//=============================================================================
module gesture_render (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [7:0]  vx,               // v3: VGA pixel
    input  wire [6:0]  vy,
    input  wire [6:0]  px_x,             // UI-space pixel (96 x 64)
    input  wire [5:0]  px_y,
    input  wire        scr,              // v3: 0 = VGA pass, 1 = OLED pass
    input  wire [`GS_W-1:0] game_state,
    input  wire        fp,               // the VGA 3-D view: no top-down aim guides / meters
    input  wire        lefty,
    input  wire [7:0]  cursor_x,         // VGA pointer
    input  wire [6:0]  cursor_y,
    input  wire [6:0]  ucur_x,           // UI-space pointer
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
`include "txt_helpers.vh"
`include "strings_map.vh"

    // ---------------- remembered results of the last swipe ------------------
    // v3: the throw spin is -31..+31; the labels, bar and LEDs show it as a
    // level 0..7 = (|spin| + 3) / 4 (same look as before)
    wire [`SPIN_W-2:0] tsp_abs = throw_spin[`SPIN_W-1] ? -throw_spin[`SPIN_W-2:0] : throw_spin[`SPIN_W-2:0];
    wire [`SPIN_W-1:0] tsp_q   = ({1'b0, tsp_abs} + 6'd3) >> 2;
    wire [`SPIN_W-1:0] tsp_l   = (tsp_q > 6'd7) ? 6'd7 : tsp_q;
    wire signed [3:0] spin_lvl = (tsp_abs == 0) ? 4'sd0 :
                                 throw_spin[`SPIN_W-1] ? -$signed({1'b0, tsp_l[2:0]}) : $signed({1'b0, tsp_l[2:0]});
    reg [7:0] l_mph;  reg signed [3:0] l_spin;  reg [2:0] l_aim;  reg l_right;  reg [6:0] l_n;
    reg [7:0] lbl_frames, msg_frames;
    reg [1:0] msg;
    always @(posedge clk) begin
        if (rst) begin
            l_mph <= 0; l_spin <= 0; l_aim <= 0; l_right <= 0; l_n <= 0; lbl_frames <= 0; msg_frames <= 0; msg <= 0;
        end else begin
            if (throw_valid) begin
                l_mph <= throw_mph10; l_spin <= spin_lvl; l_aim <= aim_level; l_right <= aim_right;
                l_n <= (n_samples > 8'd99) ? 7'd99 : n_samples[6:0]; lbl_frames <= 8'd150; msg_frames <= 0;
            end else if (reject || cancel) begin
                msg <= cancel ? `GM_CANCEL : reject_msg; msg_frames <= 8'd90; lbl_frames <= 0;
            end else if (tick_frame) begin
                if (lbl_frames != 0) lbl_frames <= lbl_frames - 8'd1;
                if (msg_frames != 0) msg_frames <= msg_frames - 8'd1;
            end
        end
    end
    // mph * 10 -> three BCD digits (0..255), by comparisons (no divider)
    wire [3:0] m_h = (l_mph >= 8'd200) ? 4'd2 : (l_mph >= 8'd100) ? 4'd1 : 4'd0;
    wire [7:0] m_r = l_mph - ((m_h == 2) ? 8'd200 : (m_h == 1) ? 8'd100 : 8'd0);
    wire [3:0] m_t = (m_r >= 90) ? 9 : (m_r >= 80) ? 8 : (m_r >= 70) ? 7 : (m_r >= 60) ? 6 : (m_r >= 50) ? 5 :
                     (m_r >= 40) ? 4 : (m_r >= 30) ? 3 : (m_r >= 20) ? 2 : (m_r >= 10) ? 1 : 0;
    wire [7:0] m_o8 = m_r - {m_t, 3'b000} - {3'b000, m_t, 1'b0};    // m_r - 10 * m_t
    wire [3:0] m_o = m_o8[3:0];
    wire [3:0] spin_mag = l_spin[3] ? -l_spin : l_spin;
    // number of samples (0..64) -> two digits
    wire [3:0] n_t = (l_n >= 7'd90) ? 4'd9 : (l_n >= 7'd80) ? 4'd8 : (l_n >= 7'd70) ? 4'd7 :
                     (l_n >= 7'd60) ? 4'd6 : (l_n >= 7'd50) ? 4'd5 : (l_n >= 7'd40) ? 4'd4 :
                     (l_n >= 7'd30) ? 4'd3 : (l_n >= 7'd20) ? 4'd2 : (l_n >= 7'd10) ? 4'd1 : 4'd0;
    wire [6:0] n_o7 = l_n - {n_t, 3'b000} - {2'b00, n_t, 1'b0};
    wire [3:0] n_o = n_o7[3:0];

    // ---------------- where things are on screen ----------------------------
    wire in_lane  = (px_x < `SCR_LANE_W);
    wire in_game  = (game_state >= `GS_AIM && game_state <= `GS_SWEEP);
    wire aiming   = (game_state == `GS_AIM) || (game_state == `GS_THROW);
    wire [6:0] bx = stance_x[12:6];
    wire signed [11:0] ball_row  = 12'sd63 - (12'sd5 - cam_y);         // ball centre row (y = 5 in)
    wire signed [11:0] foul_row  = 12'sd63 + cam_y;                    // y = 0
    wire signed [11:0] py_s      = {6'd0, px_y};
    wire [6:0] adxb = (px_x > bx) ? px_x - bx : bx - px_x;
    wire signed [11:0] sm = py_s - foul_row - 12'sd3;              // stance triangle row 0..2

    // trail: the newest matching point decides the brightness
    reg       tr_hit;
    reg [4:0] tr_age;
    integer k;
    always @(*) begin
        tr_hit = 1'b0; tr_age = 5'd0;
        for (k = 31; k >= 0; k = k - 1)
            if (trail_valid[k] && trail_bus[15*k + 7 +: 8] == vx && trail_bus[15*k +: 7] == vy) begin
                tr_hit = 1'b1; tr_age = k[4:0];
            end
    end
    wire [4:0] tr_lvl = 5'd31 - tr_age;
    wire [15:0] tr_col = {tr_lvl, tr_lvl, 1'b0, tr_lvl[4:1], 1'b0};    // yellow fading to dark

    // text cells: 3x5 font, 4 x 6 px
    wire [4:0] mcol = px_x[6:2];
    wire [1:0] mfx  = px_x[1:0];
    wire [12:0] my43 = px_y * 6'd43;
    wire [3:0] mrow = my43[11:8];
    wire [5:0] mfy6 = px_y - {mrow, 2'b00} - {1'b0, mrow, 1'b0};
    wire [2:0] mfy  = mfy6[2:0];
    // board number: counted from the throwing side (39 boards, ~1 px each)
    wire [6:0] board = lefty ? bx - 7'd8 : 7'd51 - bx;
    wire [3:0] bd_t = (board >= 7'd30) ? 4'd3 : (board >= 7'd20) ? 4'd2 : (board >= 7'd10) ? 4'd1 : 4'd0;
    wire [6:0] bd_o7 = board - {bd_t, 3'b000} - {2'b00, bd_t, 1'b0};
    wire [3:0] bd_o = bd_o7[3:0];

    // meters in the panel
    wire in_pnl = (px_x >= `SCR_HUD_X0) && (px_y >= `SCR_MTR_Y0) && in_game && !fp;
    wire [2:0] pow = grabbing ? live_power :
                     (lbl_frames != 0) ? ((l_mph >= 8'd210) ? 3'd7 : (l_mph >= 8'd190) ? 3'd6 :
                     (l_mph >= 8'd175) ? 3'd5 : (l_mph >= 8'd160) ? 3'd4 : (l_mph >= 8'd145) ? 3'd3 :
                     (l_mph >= 8'd130) ? 3'd2 : 3'd1) : 3'd0;
    wire [6:0] pow_end = 7'd72 + {1'b0, pow, 1'b0} + {2'b00, pow};      // 3 px per level
    // screen direction of the spin bar: a left hook (spin > 0) grows to the left
    wire signed [7:0] spin_px = (lbl_frames != 0) ? -({{4{l_spin[3]}}, l_spin} * 8'sd2) : 8'sd0;
    wire signed [7:0] dxc = $signed({1'b0, px_x}) - 8'sd83;             // spin bar centre x = 83

    // ---------------- world layer -------------------------------------------
    // (v3.5: the Swipe Lab screen was removed with the practice section)
    always @(*) begin
        en = 1'b0; color = `C_BLACK; txt = {`TX_W{1'b0}};
        if (in_game) begin
            // ---- lane graphics ----
            if (!scr && tr_hit && (grabbing || aiming || trail_valid != 0)) begin
                en = 1'b1; color = tr_col;
            end else if (in_lane && aiming && !fp && !grabbing && px_x == bx && py_s < ball_row - 12'sd6 && px_y[1:0] == 2'b00) begin
                en = 1'b1; color = 16'hC618;                                   // target line
            end else if (in_lane && aiming && !fp && sm >= 0 && sm <= 2 && adxb <= {5'd0, sm[1:0]}) begin
                en = 1'b1; color = `C_YELLOW;                                  // stance marker
            end
            // ---- panel meters ----
            if (in_pnl) begin
                if (px_y >= 6'd43 && px_y <= 6'd46 && px_x >= 7'd72 && px_x <= 7'd93) begin
                    en = 1'b1;
                    color = (px_x < pow_end) ? ((pow >= 3'd6) ? `C_RED : (pow >= 3'd4) ? `C_ORANGE : `C_GREEN) : 16'h2104;
                end else if (px_y >= 6'd56 && px_y <= 6'd59 && px_x >= 7'd72 && px_x <= 7'd94) begin
                    en = 1'b1;
                    if (dxc == 0) color = `C_WHITE;
                    else if (spin_px < 0 && dxc < 0 && dxc >= spin_px) color = `C_CYAN;     // hook left
                    else if (spin_px > 0 && dxc > 0 && dxc <= spin_px) color = `C_MAGENTA;  // hook right
                    else color = 16'h2104;
                end
                if (mrow == 4'd6 && mcol >= 5'd18 && mcol < 5'd21)
                    txt = tx_s(`S_POWERW + (mcol - 5'd18), 1'b1, {1'b0, mfx}, mfy, 16'hAD55, 0, 1'b0);
                else if (mrow == 4'd8 && mcol >= 5'd18 && mcol < 5'd22)
                    txt = tx_s(`S_LABW + 8 + (mcol - 5'd18), 1'b1, {1'b0, mfx}, mfy, 16'hAD55, 0, 1'b0);
            end
            // ---- lane text: label / message / board ----
            if (in_lane && mrow == 4'd0 && !fp) begin
                if (msg_frames != 0 && mcol < 5'd13)
                    txt = tx_s(`S_AMSG + {msg, 3'b000} + {msg, 2'b00} + msg + mcol, 1'b1, {1'b0, mfx}, mfy, `C_RED, `C_BLACK, 1'b1);
                else if (lbl_frames != 0 && mcol < 5'd14) begin
                    if (l_spin == 0) begin
                        if (mcol < 5'd8) txt = tx_s(`S_STRT + mcol, 1'b1, {1'b0, mfx}, mfy, `C_WHITE, `C_BLACK, 1'b1);
                    end else begin
                        if (mcol < 5'd4) txt = tx_s(`S_HOOKW + mcol, 1'b1, {1'b0, mfx}, mfy, `C_YELLOW, `C_BLACK, 1'b1);
                        else if (mcol == 5'd5) txt = tx_l(l_spin[3] ? 6'd50 : 6'd44, 1'b1, {1'b0, mfx}, mfy, `C_YELLOW, `C_BLACK, 1'b1);
                        else if (mcol == 5'd6) txt = tx_l(dig(spin_mag), 1'b1, {1'b0, mfx}, mfy, `C_YELLOW, `C_BLACK, 1'b1);
                    end
                    case (mcol)
                        5'd9:  txt = tx_l(m_h == 0 ? 6'd0 : dig(m_h), 1'b1, {1'b0, mfx}, mfy, `C_WHITE, `C_BLACK, 1'b1);
                        5'd10: txt = tx_l(dig(m_t), 1'b1, {1'b0, mfx}, mfy, `C_WHITE, `C_BLACK, 1'b1);
                        5'd11: txt = tx_l(6'd14,    1'b1, {1'b0, mfx}, mfy, `C_WHITE, `C_BLACK, 1'b1);
                        5'd12: txt = tx_l(dig(m_o), 1'b1, {1'b0, mfx}, mfy, `C_WHITE, `C_BLACK, 1'b1);
                        default: ;
                    endcase
                end else if (aiming && !grabbing && mcol < 5'd5) begin
                    case (mcol)
                        5'd0: txt = tx_s(`S_LABW + 16, 1'b1, {1'b0, mfx}, mfy, `C_YELLOW, `C_BLACK, 1'b1);  // "B"
                        5'd1: txt = tx_s(`S_LABW + 17, 1'b1, {1'b0, mfx}, mfy, `C_YELLOW, `C_BLACK, 1'b1);  // "D"
                        5'd3: txt = tx_l(dig(bd_t), 1'b1, {1'b0, mfx}, mfy, `C_YELLOW, `C_BLACK, 1'b1);
                        5'd4: txt = tx_l(dig(bd_o), 1'b1, {1'b0, mfx}, mfy, `C_YELLOW, `C_BLACK, 1'b1);
                        default: txt = tx_l(6'd0, 1'b1, {1'b0, mfx}, mfy, `C_YELLOW, `C_BLACK, 1'b1);
                    endcase
                end
            end
        end
    end

    // ---------------- cursor layer -------------------------------------------
    // v3: the VGA pass draws the real pointer; the OLED pass draws it in UI
    // space, and only outside a game (on the OLED the game is top-down only)
    wire signed [8:0] cdx = scr ? $signed({2'b00, px_x}) - $signed({2'b00, ucur_x})
                                : $signed({1'b0, vx})    - $signed({1'b0, cursor_x});
    wire signed [8:0] cdy = scr ? $signed({3'b000, px_y}) - $signed({3'b000, ucur_y})
                                : $signed({2'b00, vy})    - $signed({2'b00, cursor_y});
    wire show_cur = !(game_state >= `GS_ROLL && game_state <= `GS_SWEEP) && game_state != `GS_REPLAY &&
                    !(scr && in_game);
    always @(*) begin
        cur_en = 1'b0; cur_color = `C_WHITE;
        if (show_cur) begin
            if (in_game) begin
                if (grabbing) begin                                     // holding the ball: dot
                    if (cdx >= -1 && cdx <= 1 && cdy >= -1 && cdy <= 1) begin cur_en = 1'b1; cur_color = `C_YELLOW; end
                end else if ((cdx == 0 && cdy >= -2 && cdy <= 2) || (cdy == 0 && cdx >= -2 && cdx <= 2)) begin
                    cur_en = 1'b1; cur_color = (cdx == 0 && cdy == 0) ? `C_BLACK : `C_YELLOW;   // crosshair
                end
            end else if (cdx >= 0 && cdy >= 0 && cdy <= 6 && cdx <= cdy && cdx <= 4) begin
                // arrow: outline on the edges, white inside
                cur_en = 1'b1;
                cur_color = (cdx == 0 || cdx == cdy || cdy == 6 || (cdx == 4)) ? `C_BLACK : `C_WHITE;
                if (cdy == 6 && cdx > 2) cur_en = 1'b0;
            end
        end
    end

    // ---------------- LEDs -----------------------------------------------------
    always @(*) begin
        led_a = 6'd0;
        if (grabbing) begin
            led_a = (live_power >= 3'd6) ? 6'b111111 : ~(6'b111111 << live_power);
        end else if (lbl_frames != 0 && l_spin != 0) begin
            // hook left: bar from led[15] down, hook right: from led[10] up
            if (!l_spin[3]) led_a = ~(6'b111111 >> ((spin_mag > 4'd6) ? 3'd6 : spin_mag[2:0]));  // left
            else            led_a = ~(6'b111111 << ((spin_mag > 4'd6) ? 3'd6 : spin_mag[2:0]));  // right
        end
    end
endmodule
