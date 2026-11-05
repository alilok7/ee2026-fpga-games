`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// vga_hud.v - the VGA screen's own layers: scorecard strip, side panel, popups, frame
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : (v3) Everything the VGA shows that the 96 x 64 OLED picture has
//           no room for. A pure function of the VGA pixel (vx, vy) and a few
//           registers, like every other renderer; text goes through the one
//           shared text engine.
//   3-D GAME LAYOUT (v3d = 1; v3.3: the 3-D view fills the screen, the
//     scorecard strip is gone - the scorecard is on the OLED)
//     panel          : a half-size box in the top-right corner, laid out in
//                      the 320 x 240 pixel grid (hx, hy) so the same text is
//                      half as big: FRAME + BALL, SCORE (2 players: both), live SPEED in
//                      mph (falls as the ball slows), POWER bar, SPIN value and
//                      bar, REVS left in the ball (live) or, after the hit, the
//                      ENTRY board with "POCKET", and the pin diagram
//     view overlays  : STRIKE! / SPARE! ... popups in double-size letters,
//                      FRAME n banner, PAUSED, ZOOM title, board / target
//                      readout while aiming, the hint row, swipe messages, and
//                      the STRIKELINE sign on the masking unit
//   REPLAY (v3.3, rp_full): the top-down replay fills the screen; this layer
//     adds a camera look: four corner brackets, a blinking red dot and
//     "REPLAY", and dark bars beside the lane
//   UI LAYOUT (v3d = 0, outside the 96 x 64 window): a gradient backdrop,
//     the STRIKELINE title in double size, a framed window border, and a
//     small animated lane where a ball rolls into the pins.
//=============================================================================
module vga_hud (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [7:0]  vx,
    input  wire [6:0]  vy,
    input  wire [8:0]  hx,               // v3.3: the same pixel in the 320 x 240 grid
    input  wire [7:0]  hy,
    input  wire        v3d,              // this pixel uses the 3-D game layout
    input  wire        u_in,             // this pixel is inside the UI window
    input  wire        rp_full,          // v3.3: full-screen replay
    input  wire [`GS_W-1:0]  game_state,
    input  wire [`SET_W-1:0] settings,
    input  wire [`PK_W-1:0]  kind,
    input  wire        player,
    input  wire [3:0]  frame,            // 0..9
    input  wire [1:0]  ball_no,
    input  wire [8:0]  score0, score1,   // points so far (provisional)
    output wire [4:0]  card_addr,        // {player, frame} -> score_engine
    input  wire [27:0] card_word,        // {known, total, mark0, mark1, mark2}
    input  wire [9:0]  pins_standing,
    input  wire [3:0]  popup_id,
    input  wire [3:0]  popup_n,
    input  wire        banner,
    input  wire        paused,
    input  wire        saving,
    input  wire        grabbing,
    input  wire [2:0]  live_power,
    input  wire        throw_valid,
    input  wire signed [`SPIN_W-1:0] throw_spin,
    input  wire [7:0]  throw_mph10,
    input  wire        reject,
    input  wire [1:0]  reject_msg,
    input  wire        cancel,
    input  wire [7:0]  ball_rev,
    input  wire signed [15:0] ball_vy,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire [`BP_W-1:0] ball_phase,
    input  wire [6:0]  stance_in,
    input  wire [6:0]  target_in,
    input  wire        lefty,
    input  wire        aim_zoom,
    input  wire [7:0]  spare_made,
    input  wire [7:0]  spare_tries,
    output reg  [15:0] color,
    output reg         en,
    output reg  [`TX_W-1:0] txt
);
`include "txt_helpers.vh"
`include "strings_map.vh"
`include "bcd_fns.vh"

    localparam [15:0] W = `C_WHITE, Y = `C_YELLOW, DIM = 16'h8C71, LBL = 16'h9D9B;
    wire neon = settings[`SET_THEME];

    // ---------------- frame counter, remembered throw ------------------------
    reg [7:0] fr;
    always @(posedge clk) if (rst) fr <= 0; else if (tick_frame) fr <= fr + 8'd1;

    reg [7:0]  l_mph;
    reg [4:0]  l_spin;                    // |spin|
    reg        l_left;                    // spin > 0 (hooks left)
    reg [7:0]  msg_frames;
    reg [1:0]  msg;
    wire [`SPIN_W-2:0] tsa = throw_spin[`SPIN_W-1] ? -throw_spin[`SPIN_W-2:0] : throw_spin[`SPIN_W-2:0];
    always @(posedge clk) begin
        if (rst) begin l_mph <= 0; l_spin <= 0; l_left <= 0; msg_frames <= 0; msg <= 0; end
        else begin
            if (throw_valid) begin
                l_mph <= throw_mph10; l_spin <= tsa; l_left <= ~throw_spin[`SPIN_W-1]; msg_frames <= 0;
            end else if (reject || cancel) begin
                msg <= cancel ? `GM_CANCEL : reject_msg; msg_frames <= 8'd90;
            end else if (tick_frame && msg_frames != 0) msg_frames <= msg_frames - 8'd1;
        end
    end

    // entry point: where the ball crosses the head-pin row (714 in)
    reg [6:0] x_entry; reg e_ok;
    reg       y_prev_lo;
    always @(posedge clk) begin
        y_prev_lo <= (ball_y < 16'd45696);
        if (rst) begin x_entry <= 0; e_ok <= 0; end
        else if (throw_valid) e_ok <= 1'b0;
        else if (y_prev_lo && ball_y >= 16'd45696 && ball_phase != `BP_GUTTER && ball_phase != `BP_PIT) begin
            x_entry <= ball_x[12:6]; e_ok <= 1'b1;
        end
    end
    // boards counted from the throwing side (as the aiming readout)
    function [6:0] board_of; input [6:0] x; input lf;
        board_of = lf ? ((x > 7'd8) ? x - 7'd8 : 7'd0) : ((x < 7'd51) ? 7'd51 - x : 7'd0);
    endfunction
    wire [6:0] e_board = board_of(x_entry, lefty);
    wire       pocket  = e_ok && (e_board >= 7'd16) && (e_board <= 7'd20);   // ~17.5 board

    // ---------------- numbers -> digits (registered: they change per frame) -
    reg [11:0] b_s0, b_s1, b_mph, b_live, b_eb, b_bd, b_tg, b_sm, b_st;
    reg [6:0]  st_q, tg_q;
    reg  [17:0] live10;                                                         // mph * 10 << 10 (registered)
    always @(posedge clk) live10 <= (ball_vy[15] ? 18'd0 : {2'b00, ball_vy}) * 8'd145;
    wire        rolling = (game_state == `GS_ROLL);
    always @(posedge clk) begin
        b_s0   <= bcd9(score0);
        b_s1   <= bcd9(score1);
        b_mph  <= bcd9({1'b0, l_mph});
        b_live <= bcd9(live10[17:10] > 8'd250 ? 9'd250 : {1'b0, live10[17:10]});
        b_eb   <= bcd9({2'b00, e_board});
        st_q   <= stance_in; tg_q <= target_in;                        // (timing)
        b_bd   <= bcd9({2'b00, board_of(st_q, lefty)});
        b_tg   <= bcd9({2'b00, board_of(tg_q, lefty)});
        b_sm   <= bcd9({1'b0, spare_made});
        b_st   <= bcd9({1'b0, spare_tries});
    end
    wire [11:0] b_spd = (rolling || game_state == `GS_PINACTION) ? b_live : b_mph;
    function [5:0] dg;                     // digit k (2 = hundreds) with leading blanks
        input [11:0] b; input [1:0] k;
        case (k)
            2'd2: dg = (b[11:8] == 0) ? 6'd0 : 6'd16 + b[11:8];
            2'd1: dg = (b[11:4] == 0) ? 6'd0 : 6'd16 + b[7:4];
            default: dg = 6'd16 + b[3:0];
        endcase
    endfunction
    wire [3:0] sp_t = (l_spin >= 5'd30) ? 4'd3 : (l_spin >= 5'd20) ? 4'd2 : (l_spin >= 5'd10) ? 4'd1 : 4'd0;
    wire [4:0] sp_o5 = l_spin - {sp_t, 3'b000} - {1'b0, sp_t, 1'b0};
    wire [3:0] sp_o = sp_o5[3:0];

    // (v3.3: no scorecard strip on the VGA any more; the read port is unused)
    assign card_addr = {player, 4'd0};

    // ---------------- panel coordinates (320 x 240 grid, half size) ----------
    // box hx 268..319, hy 2..109; content 48 x 104 from (270, 4)
    wire in_panel = (hx >= `H_PANEL_X0) && (hy >= 8'd2) && (hy <= `H_PANEL_Y1);
    wire pan_edge = in_panel && (hx == `H_PANEL_X0 || hy == 8'd2 || hy == `H_PANEL_Y1 || hx == 9'd319);
    wire [8:0] lx9 = hx - (`H_PANEL_X0 + 9'd2);     // 0..47
    wire [6:0] lx  = lx9[6:0];
    wire [7:0] ly8 = hy - 8'd4;                     // 0..103
    wire [6:0] ly  = ly8[6:0];
    wire [3:0] pc  = lx[5:2];                       // 3x5 column (4 px)
    wire [2:0] pfx = {1'b0, lx[1:0]};
    wire [3:0] c6p = c6(lx);                        // 5x7 column (6 px)
    wire [2:0] f6p = f6(lx);
    function in_band; input [6:0] y; input [6:0] y0; input [6:0] h;
        in_band = (y >= y0) && (y < y0 + h);
    endfunction
    function [2:0] bfy; input [6:0] y; input [6:0] y0;
        bfy = y[2:0] - y0[2:0];
    endfunction
    // label from the VPN list (6 wide): FRAME BALL SCORE SPEED POWER SPIN REVS BOARD TARGET ENTRY POCKET PLAYER
    function [10:0] vpn; input [3:0] i; input [3:0] c;
        vpn = `S_VPN + {i, 2'b00} + {i, 1'b0} + c;
    endfunction
    // power level 0..7
    wire [2:0] pow = grabbing ? live_power :
                     (l_mph == 0) ? 3'd0 :
                     (l_mph >= 8'd210) ? 3'd7 : (l_mph >= 8'd190) ? 3'd6 : (l_mph >= 8'd175) ? 3'd5 :
                     (l_mph >= 8'd160) ? 3'd4 : (l_mph >= 8'd145) ? 3'd3 : (l_mph >= 8'd130) ? 3'd2 : 3'd1;
    wire [5:0] pow_w = {pow, 2'b00} + {1'b0, pow, 1'b0} - {3'd0, pow};      // 5 px per level
    wire [9:0] spw10 = l_spin * 5'd23;                                      // bar half: |spin| * 23 / 32
    wire [4:0] spw   = spw10[9:5];
    wire [9:0] rvw10 = ball_rev * 2'd3;                                     // rev bar: rev * 3 / 16
    wire [5:0] rvw   = (rvw10[9:4] > 6'd42) ? 6'd42 : rvw10[9:4];
    wire signed [7:0] sdx = $signed({1'b0, lx}) - 8'sd23;

    // pin diagram: 7 8 9 10 / 4 5 6 / 2 3 / 1, 3x3 dots
    reg       pd_hit; reg [3:0] pd_k; reg pd_core;
    always @(*) begin
        pd_hit = 1'b0; pd_k = 4'd0; pd_core = 1'b0;
        if (ly >= 7'd80 && ly <= 7'd82) begin
            if (lx >= 7'd8  && lx <= 7'd10) begin pd_hit = 1; pd_k = 6; pd_core = (lx == 7'd9);  end
            if (lx >= 7'd18 && lx <= 7'd20) begin pd_hit = 1; pd_k = 7; pd_core = (lx == 7'd19); end
            if (lx >= 7'd28 && lx <= 7'd30) begin pd_hit = 1; pd_k = 8; pd_core = (lx == 7'd29); end
            if (lx >= 7'd38 && lx <= 7'd40) begin pd_hit = 1; pd_k = 9; pd_core = (lx == 7'd39); end
            pd_core = pd_core && (ly == 7'd81);
        end else if (ly >= 7'd86 && ly <= 7'd88) begin
            if (lx >= 7'd13 && lx <= 7'd15) begin pd_hit = 1; pd_k = 3; pd_core = (lx == 7'd14); end
            if (lx >= 7'd23 && lx <= 7'd25) begin pd_hit = 1; pd_k = 4; pd_core = (lx == 7'd24); end
            if (lx >= 7'd33 && lx <= 7'd35) begin pd_hit = 1; pd_k = 5; pd_core = (lx == 7'd34); end
            pd_core = pd_core && (ly == 7'd87);
        end else if (ly >= 7'd92 && ly <= 7'd94) begin
            if (lx >= 7'd18 && lx <= 7'd20) begin pd_hit = 1; pd_k = 1; pd_core = (lx == 7'd19); end
            if (lx >= 7'd28 && lx <= 7'd30) begin pd_hit = 1; pd_k = 2; pd_core = (lx == 7'd29); end
            pd_core = pd_core && (ly == 7'd93);
        end else if (ly >= 7'd98 && ly <= 7'd100) begin
            if (lx >= 7'd23 && lx <= 7'd25) begin pd_hit = 1; pd_k = 0; pd_core = (lx == 7'd24); end
            pd_core = pd_core && (ly == 7'd99);
        end
    end

    // ---------------- view overlays ------------------------------------------
    // (v3.3) the view is 160 wide now: the centred overlays (popups, banner,
    // pause, ZOOM, the masking-unit sign) are laid out as before on a
    // 112-wide view and moved right by 24 (vxc); left-aligned rows use vx
    wire [7:0]  vxc  = vx - 8'd24;
    // double-size 5x7 text: 12 x 16 px cells from x0
    wire [7:0]  bgx  = vxc - 8'd14;                // popup text starts at x 14
    wire [12:0] bg43 = bgx[6:0] * 6'd43;
    wire [3:0]  bcol = bg43[12:9];                 // / 12
    wire [6:0]  bcx  = bgx[6:0] - {bcol, 3'b000} - {1'b0, bcol, 2'b00};
    wire [2:0]  bfx  = bcx[3:1];
    wire [6:0]  bly  = vy - 7'd56;
    wire [2:0]  bfyy = bly[3:1];
    wire in_pop_box = (vxc >= 8'd8) && (vxc <= 8'd103) && (vy >= 7'd52) && (vy <= 7'd75);
    wire pop_edge   = in_pop_box && (vxc == 8'd8 || vxc == 8'd103 || vy == 7'd52 || vy == 7'd75);
    wire in_pop_txt = (vxc >= 8'd14) && (vxc < 8'd98) && (vy >= 7'd56) && (vy < 7'd72);
    reg [15:0] pop_col;
    always @(*) begin
        case (popup_id)
            4'd0, 4'd4, 4'd5: pop_col = fr[2] ? 16'hFD20 : `C_MAGENTA;
            4'd1, 4'd6:       pop_col = 16'h03EF;
            4'd3:             pop_col = `C_ORANGE;
            4'd2, 4'd7:       pop_col = 16'h630C;
            default:          pop_col = 16'h0019;
        endcase
    end
    wire show_pop    = (popup_id != 4'd15) && (game_state == `GS_RESULT);
    wire spare       = kind[`PK_SPARE];
    wire show_banner = banner && !show_pop && (game_state == `GS_AIM || game_state == `GS_SWEEP) && !spare;
    wire [4:0] fno   = {1'b0, frame} + 5'd1;
    // single-size 5x7 rows inside the view
    wire       vc_ok = (vxc < 8'd112);              // inside the centred 112-wide area
    wire [3:0] vc6 = vc_ok ? c6(vxc[6:0]) : 4'd15;
    wire [2:0] vf6 = f6(vxc[6:0]);
    wire in_ban_box = (vxc >= 8'd20) && (vxc <= 8'd91) && (vy >= 7'd38) && (vy <= 7'd51);
    wire ban_edge   = in_ban_box && (vxc == 8'd20 || vxc == 8'd91 || vy == 7'd38 || vy == 7'd51);
    // 3x5 rows inside the view: hint (y 112..117), board readout (104..109), sign (18..23)
    wire [5:0] vc4 = vx[7:2];                       // left-aligned rows
    wire [2:0] vf4 = {1'b0, vx[1:0]};
    wire [4:0] vc4c = vc_ok ? vxc[6:2] : 5'd31;     // centred rows (the sign)
    wire [2:0] vf4c = {1'b0, vxc[1:0]};
    // replay camera overlay: corner brackets (320 x 240 grid), REPLAY text
    wire cb_x = (hx >= 9'd8 && hx <= 9'd9) || (hx >= 9'd310 && hx <= 9'd311);
    wire cb_y = (hy >= 8'd8 && hy <= 8'd9) || (hy >= 8'd230 && hy <= 8'd231);
    wire cb_xr = (hx >= 9'd8 && hx <= 9'd37) || (hx >= 9'd282 && hx <= 9'd311);
    wire cb_yr = (hy >= 8'd8 && hy <= 8'd37) || (hy >= 8'd202 && hy <= 8'd231);
    wire corner = (cb_x && cb_yr) || (cb_y && cb_xr);
    wire [7:0] rpx = vx - 8'd20;                    // "REPLAY" at x 20.., y 9..15
    wire [3:0] rpc = (rpx < 8'd36) ? c6(rpx[6:0]) : 4'd15;
    wire [2:0] rpf = f6(rpx[6:0]);
    wire       rdot = (vx >= 8'd12 && vx <= 8'd16 && vy >= 7'd10 && vy <= 7'd14) &&
                      !((vx == 8'd12 || vx == 8'd16) && (vy == 7'd10 || vy == 7'd14));
    wire       rp_on = fr[5] || fr[4];                       // on 3/4 of the time, ~1 Hz
    wire aiming = (game_state == `GS_AIM);
    wire [6:0] pfy = vy - 7'd60;

    // ---------------- UI backdrop ---------------------------------------------
    wire in_border = (vx >= 8'd29) && (vx <= 8'd130) && (vy >= 7'd25) && (vy <= 7'd94);
    // title "STRIKELINE" in double size: x 20..139, y 4..19
    wire [7:0]  tgx  = vx - 8'd20;
    wire [12:0] tg43 = tgx[6:0] * 6'd43;
    wire [3:0]  tcol = tg43[12:9];
    wire [6:0]  tcx  = tgx[6:0] - {tcol, 3'b000} - {1'b0, tcol, 2'b00};
    wire [6:0]  tly  = vy - 7'd4;
    wire in_title = (vx >= 8'd20) && (vx < 8'd140) && (vy >= 7'd4) && (vy < 7'd20);
    // the little lane at the bottom: a ball rolls in every 128 frames
    wire [6:0] lane_t = fr[6:0];
    wire [7:0] ball_px = 8'd12 + {1'b0, lane_t} ;
    wire in_mlane = (vy >= 7'd107) && (vy <= 7'd115) && (vx >= 8'd8) && (vx <= 8'd151);
    wire mball = (vy >= 7'd110) && (vy <= 7'd112) && (vx >= ball_px) && (vx <= ball_px + 8'd2) && (lane_t < 7'd127);
    wire pins_dn = (lane_t > 7'd126) || (lane_t < 7'd24);
    wire mpin = (vx == 8'd145 || vx == 8'd148) && (vy == 7'd109 || vy == 7'd111 || vy == 7'd113) && !pins_dn;
    wire [15:0] c_bg = {2'b00, vy[6:5], 1'b1, 3'b000, vy[6:5], 1'b1, 2'b01, vy[6:4]} +
                       ((((vx + {1'b0, vy}) & 8'h1F) < 8'd2) ? 16'h0841 : 16'h0000);

    always @(*) begin
        en = 1'b0; color = `C_BLACK; txt = {`TX_W{1'b0}};
        if (rp_full) begin
            // ================= replay: camera look =================
            if (!u_in) begin en = 1'b1; color = 16'h0841; end          // beside the lane
            if (corner) begin en = 1'b1; color = W; end
            else if (rp_on && rdot) begin en = 1'b1; color = `C_RED; end
            else if (rp_on && vy >= 7'd9 && vy <= 7'd15 && rpc < 4'd6)
                txt = tx_s(`S_HINT + 11'd75 + rpc, 1'b0, rpf, vy[2:0] - 3'd1, W, 0, 1'b0);
        end else if (v3d) begin
            // ================= side panel (half size, top right) =================
            if (in_panel) begin
                en = 1'b1;
                color = pan_edge ? 16'h4208 : (ly < 7'd52) ? 16'h0862 : 16'h0841;
                if (pd_hit) color = pins_standing[pd_k] ? (pd_core ? `C_RED : W) : 16'h31A6;
                else if (ly >= 7'd53 && ly <= 7'd56 && lx >= 7'd2 && lx <= 7'd45)
                    color = (lx - 7'd2 < {1'b0, pow_w}) ? ((pow >= 3'd6) ? `C_RED : (pow >= 3'd4) ? `C_ORANGE : `C_GREEN) : 16'h2104;
                else if (ly >= 7'd64 && ly <= 7'd67 && lx >= 7'd1 && lx <= 7'd45) begin
                    if (sdx == 0) color = W;
                    else if (l_left && sdx < 0 && -sdx <= $signed({3'b000, spw})) color = `C_CYAN;
                    else if (!l_left && sdx > 0 && sdx <= $signed({3'b000, spw})) color = `C_MAGENTA;
                    else color = 16'h2104;
                end else if (ly >= 7'd75 && ly <= 7'd77 && lx >= 7'd2 && lx <= 7'd45 && !e_ok)
                    color = (lx - 7'd2 < {1'b0, rvw}) ? 16'hFC60 : 16'h2104;
                // text
                if (in_band(ly, 7'd2, 7'd5)) begin
                    if (pc < 4'd5) txt = tx_s(vpn(4'd0, pc), 1'b1, pfx, bfy(ly, 7'd2), LBL, 0, 1'b0);
                    else if (kind[`PK_TWO] && pc == 4'd10) txt = tx_l(6'd48, 1'b1, pfx, bfy(ly, 7'd2), player ? `C_CYAN : Y, 0, 1'b0);
                    else if (kind[`PK_TWO] && pc == 4'd11) txt = tx_l(player ? 6'd18 : 6'd17, 1'b1, pfx, bfy(ly, 7'd2), player ? `C_CYAN : Y, 0, 1'b0);
                end else if (in_band(ly, 7'd8, 7'd8) && c6p < 4'd2) begin
                    txt = tx_l(c6p == 0 ? (fno >= 5'd10 ? 6'd17 : 6'd0) : 6'd16 + ((fno >= 5'd10) ? 6'd0 : {2'b00, fno[3:0]}),
                               1'b0, f6p, bfy(ly, 7'd8), W, 0, 1'b0);
                end else if (in_band(ly, 7'd10, 7'd5) && pc >= 4'd5) begin
                    if (pc < 4'd9) txt = tx_s(vpn(4'd1, pc - 4'd5), 1'b1, pfx, bfy(ly, 7'd10), LBL, 0, 1'b0);
                    else if (pc == 4'd10) txt = tx_l(dig({2'b00, ball_no} + 4'd1), 1'b1, pfx, bfy(ly, 7'd10), W, 0, 1'b0);
                end else if (in_band(ly, 7'd18, 7'd5)) begin
                    if (pc < 4'd5) txt = tx_s(spare ? `S_POP + 11'd64 + pc : vpn(4'd2, pc), 1'b1, pfx, bfy(ly, 7'd18), LBL, 0, 1'b0);
                end else if (in_band(ly, 7'd24, 7'd8) && c6p < 4'd3) begin
                    txt = tx_l(spare ? dg(b_sm, 2'd2 - c6p[1:0]) : dg(player ? b_s1 : b_s0, 2'd2 - c6p[1:0]),
                               1'b0, f6p, bfy(ly, 7'd24), Y, 0, 1'b0);
                end else if (in_band(ly, 7'd26, 7'd5) && pc >= 4'd8) begin
                    // the other player (2P), or the tries in Spare Challenge
                    if (spare) begin
                        if (pc == 4'd8) txt = tx_l(6'd15, 1'b1, pfx, bfy(ly, 7'd26), W, 0, 1'b0);
                        else if (pc < 4'd11) txt = tx_l(dg(b_st, (pc == 4'd9) ? 2'd1 : 2'd0), 1'b1, pfx, bfy(ly, 7'd26), W, 0, 1'b0);
                    end else if (kind[`PK_TWO]) begin
                        if (pc == 4'd8) txt = tx_l(player ? 6'd17 : 6'd18, 1'b1, pfx, bfy(ly, 7'd26), player ? Y : `C_CYAN, 0, 1'b0);
                        else txt = tx_l(dg(player ? b_s0 : b_s1, (pc == 4'd9) ? 2'd2 : (pc == 4'd10) ? 2'd1 : 2'd0), 1'b1, pfx, bfy(ly, 7'd26), DIM, 0, 1'b0);
                    end
                end else if (in_band(ly, 7'd33, 7'd5)) begin
                    if (pc < 4'd5) txt = tx_s(vpn(4'd3, pc), 1'b1, pfx, bfy(ly, 7'd33), LBL, 0, 1'b0);
                end else if (in_band(ly, 7'd39, 7'd8) && c6p < 4'd4) begin
                    case (c6p)
                        4'd0: txt = tx_l(dg(b_spd, 2'd2), 1'b0, f6p, bfy(ly, 7'd39), W, 0, 1'b0);
                        4'd1: txt = tx_l(6'd16 + b_spd[7:4], 1'b0, f6p, bfy(ly, 7'd39), W, 0, 1'b0);
                        4'd2: txt = tx_l(6'd14, 1'b0, f6p, bfy(ly, 7'd39), W, 0, 1'b0);
                        default: txt = tx_l(6'd16 + b_spd[3:0], 1'b0, f6p, bfy(ly, 7'd39), W, 0, 1'b0);
                    endcase
                end else if (in_band(ly, 7'd41, 7'd5) && pc >= 4'd9) begin
                    txt = tx_s(`S_MPHW + pc - 4'd9, 1'b1, pfx, bfy(ly, 7'd41), LBL, 0, 1'b0);
                end else if (in_band(ly, 7'd47, 7'd5)) begin
                    if (pc < 4'd5) txt = tx_s(vpn(4'd4, pc), 1'b1, pfx, bfy(ly, 7'd47), LBL, 0, 1'b0);
                end else if (in_band(ly, 7'd58, 7'd5)) begin
                    if (pc < 4'd4) txt = tx_s(vpn(4'd5, pc), 1'b1, pfx, bfy(ly, 7'd58), LBL, 0, 1'b0);
                    else if (pc == 4'd9) txt = tx_l(l_spin == 0 ? 6'd0 : (l_left ? 6'd44 : 6'd50), 1'b1, pfx, bfy(ly, 7'd58), Y, 0, 1'b0);
                    else if (pc == 4'd10) txt = tx_l(sp_t == 0 ? 6'd0 : dig(sp_t), 1'b1, pfx, bfy(ly, 7'd58), Y, 0, 1'b0);
                    else if (pc == 4'd11) txt = tx_l(dig(sp_o), 1'b1, pfx, bfy(ly, 7'd58), Y, 0, 1'b0);
                end else if (in_band(ly, 7'd69, 7'd5)) begin
                    if (!e_ok) begin
                        if (pc < 4'd4) txt = tx_s(vpn(4'd6, pc), 1'b1, pfx, bfy(ly, 7'd69), LBL, 0, 1'b0);
                    end else begin
                        if (pc < 4'd5) txt = tx_s(vpn(4'd9, pc), 1'b1, pfx, bfy(ly, 7'd69), LBL, 0, 1'b0);
                        else if (pc == 4'd6) txt = tx_l(dg(b_eb, 2'd1), 1'b1, pfx, bfy(ly, 7'd69), W, 0, 1'b0);
                        else if (pc == 4'd7) txt = tx_l(dg(b_eb, 2'd0), 1'b1, pfx, bfy(ly, 7'd69), W, 0, 1'b0);
                    end
                end else if (in_band(ly, 7'd75, 7'd5) && e_ok && pocket) begin
                    if (pc >= 4'd1 && pc < 4'd7) txt = tx_s(vpn(4'd10, pc - 4'd1), 1'b1, pfx, bfy(ly, 7'd75), fr[3] ? Y : `C_ORANGE, 0, 1'b0);
                end
            end
            // ================= view overlays =================
            else begin
                if (paused && in_pop_box) begin
                    en = 1'b1; color = pop_edge ? W : 16'h0010;
                    if (vy >= 7'd60 && vy < 7'd68 && vc6 >= 4'd6 && vc6 < 4'd12)
                        txt = tx_s(`S_HINT + 11'd60 + vc6 - 4'd6, 1'b0, vf6, pfy[2:0], W, 0, 1'b0);
                end else if (show_pop && in_pop_box) begin
                    en = 1'b1; color = pop_edge ? W : pop_col;
                    if (in_pop_txt && bcol < 4'd7) begin
                        if (popup_id == 4'd8) begin
                            if (bcol == 4'd0) txt = tx_l(dig(popup_n), 1'b0, bfx, bfyy, W, 0, 1'b0);
                            else if (bcol >= 4'd2 && bcol < 4'd6) txt = tx_s(`S_POP + 11'd64 + bcol - 4'd2, 1'b0, bfx, bfyy, W, 0, 1'b0);
                        end else
                            txt = tx_s(`S_POP + {popup_id, 3'd0} + bcol, 1'b0, bfx, bfyy, W, 0, 1'b0);
                    end
                end else if (show_banner && in_ban_box) begin
                    en = 1'b1; color = ban_edge ? 16'h8410 : 16'h0109;
                    if (vy >= 7'd41 && vy < 7'd49) begin
                        if (vc6 >= 4'd4 && vc6 < 4'd9) txt = tx_s(`S_POP + 11'd72 + vc6 - 4'd4, 1'b0, vf6, vy[2:0] - 3'd1, W, 0, 1'b0);
                        else if (vc6 == 4'd10 && fno >= 5'd10) txt = tx_l(6'd17, 1'b0, vf6, vy[2:0] - 3'd1, Y, 0, 1'b0);
                        else if (vc6 == 4'd11) txt = tx_l(6'd16 + ((fno >= 5'd10) ? 6'd0 : {2'b00, fno[3:0]}), 1'b0, vf6, vy[2:0] - 3'd1, Y, 0, 1'b0);
                    end
                end
                // masking-unit sign
                if (vy >= 7'd19 && vy <= 7'd23 && vc4c >= 5'd9 && vc4c < 5'd19)
                    txt = tx_s(`S_VTITLE + vc4c - 5'd9, 1'b1, vf4c, vy[2:0] - 3'd3, neon ? `C_CYAN : 16'hFE60, 0, 1'b0);
                // ZOOM title (v3.1: right button held)
                else if (aiming && aim_zoom && vy >= 7'd33 && vy < 7'd41 && vc6 >= 4'd5 && vc6 < 4'd13)
                    txt = tx_s(`S_PVIEW + vc6 - 4'd5, 1'b0, vf6, vy[2:0] - 3'd1, Y, `C_BLACK, 1'b1);
                // board / target readout while aiming (3x5, y 104..108)
                else if (aiming && !grabbing && vy >= 7'd104 && vy <= 7'd108 && vc4 < 5'd14) begin
                    case (vc4)
                        5'd0: txt = tx_s(vpn(4'd7, 4'd0), 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);      // B
                        5'd1: txt = tx_s(vpn(4'd7, 4'd4), 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);      // D
                        5'd3: txt = tx_l(dg(b_bd, 2'd1), 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);
                        5'd4: txt = tx_l(dg(b_bd, 2'd0), 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);
                        5'd7: txt = tx_s(vpn(4'd8, 4'd0), 1'b1, vf4, vy[2:0], `C_CYAN, `C_BLACK, 1'b1); // T
                        5'd8: txt = tx_s(vpn(4'd8, 4'd3), 1'b1, vf4, vy[2:0], `C_CYAN, `C_BLACK, 1'b1); // G
                        5'd10: txt = tx_l(dg(b_tg, 2'd1), 1'b1, vf4, vy[2:0], `C_CYAN, `C_BLACK, 1'b1);
                        5'd11: txt = tx_l(dg(b_tg, 2'd0), 1'b1, vf4, vy[2:0], `C_CYAN, `C_BLACK, 1'b1);
                        default: txt = tx_l(6'd0, 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);
                    endcase
                end
                // hint row (3x5, y 112..116): messages > saving > what to do now
                else if (vy >= 7'd112 && vy <= 7'd116) begin
                    if (msg_frames != 0 && vc4 < 5'd13)
                        txt = tx_s(`S_AMSG + {msg, 3'b000} + {msg, 2'b00} + msg + vc4, 1'b1, vf4, vy[2:0], `C_RED, `C_BLACK, 1'b1);
                    else if (saving && fr[4] && vc4 < 5'd6)
                        txt = tx_s(`S_HINT + 11'd90 + vc4, 1'b1, vf4, vy[2:0], `C_ORANGE, `C_BLACK, 1'b1);
                    else if (aiming && aim_zoom && vc4 < 5'd26)
                        txt = tx_s(`S_PVIEWH + vc4, 1'b1, vf4, vy[2:0], W, `C_BLACK, 1'b1);
                    else if (vc4 < 5'd15) case (game_state)
                        `GS_AIM:    txt = tx_s(`S_HINT + vc4,          1'b1, vf4, vy[2:0], W, `C_BLACK, 1'b1);
                        `GS_THROW:  txt = tx_s(`S_HINT + 11'd15 + vc4, 1'b1, vf4, vy[2:0], Y, `C_BLACK, vc4 < 5'd14);
                        `GS_RESULT: txt = tx_s(`S_HINT + 11'd30 + vc4, 1'b1, vf4, vy[2:0], 16'hAD55, `C_BLACK, vc4 < 5'd13);
                        default: ;
                    endcase
                end
            end
        end else if (!u_in) begin
            // ================= UI backdrop around the window =================
            en = 1'b1;
            color = c_bg;
            if (in_border) color = (vx == 8'd29 || vx == 8'd130 || vy == 7'd25 || vy == 7'd94) ?
                                   (neon ? `C_CYAN : 16'hFE60) : (neon ? 16'h780F : 16'h8A00);
            else if (in_mlane) begin
                color = (vy == 7'd107 || vy == 7'd115) ? 16'h39E8 : 16'hDDD0;
                if (mball) color = 16'hA8E7;
                else if (mpin) color = W;
            end
            if (in_title && tcol < 4'd10)
                txt = tx_s(`S_VTITLE + tcol, 1'b0, tcx[3:1], tly[3:1],
                           neon ? (tly[3] ? `C_MAGENTA : `C_CYAN) : (tly[3] ? 16'hFC00 : 16'hFEA0), 0, 1'b0);
            else if (vy >= 7'd98 && vy <= 7'd102 && vx >= 8'd56 && vx < 8'd104)
                txt = tx_s(`S_VSUB + vx[6:2] - 5'd14, 1'b1, vf4, vy[2:0] - 3'd2, 16'hAD55, 0, 1'b0);
        end
    end
endmodule
