`timescale 1ns / 1ps
`include "strike_defs.vh"
// vga_hud.v : VGA-only layers - info panel, pop-ups, replay look, menu backdrop
// Student D. Panel in the 320 x 240 grid (hx, hy), overlays in 160 x 120 (vx, vy).

// board number counted from the throwing side
module vh_board (
    input  wire [6:0] x,
    input  wire       lefty,
    output wire [6:0] board
);
    assign board = lefty ? ((x > 7'd8)  ? x - 7'd8  : 7'd0)
                         : ((x < 7'd51) ? 7'd51 - x : 7'd0);
endmodule

module vga_hud (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [7:0]  vx,
    input  wire [6:0]  vy,
    input  wire [8:0]  hx,
    input  wire [7:0]  hy,
    input  wire        v3d,
    input  wire        u_in,
    input  wire        rp_full,          // full-screen replay
    input  wire [6:0]  sign_row,
    input  wire        sign_ok,
    input  wire [`GS_W-1:0]  game_state,
    input  wire [`SET_W-1:0] settings,
    input  wire [`PK_W-1:0]  kind,       // C: play kind (2 players?)
    input  wire        player,           // C: whose turn
    input  wire [3:0]  frame,            // C: 0..9
    input  wire [1:0]  ball_no,          // C: ball in the frame
    input  wire [8:0]  score0, score1,   // C: points so far (provisional)
    output wire [4:0]  card_addr,        // C score_engine read address (not used by the VGA any more)
    input  wire [27:0] card_word,        // (not used)
    input  wire [9:0]  pins_standing,    // C
    input  wire [3:0]  popup_id,         // C: which popup (15 = none)
    input  wire [3:0]  popup_n,          // C: "n PINS"
    input  wire        banner,           // C: show the FRAME n banner
    input  wire        paused,           // sw0
    input  wire        saving,           // flash_ctrl
    input  wire        grabbing,         // A: the ball is held
    input  wire [2:0]  live_power,       // A: swipe power while held
    input  wire        throw_valid,      // A: a throw was made (1 clock)
    input  wire signed [`SPIN_W-1:0] throw_spin,
    input  wire [7:0]  throw_mph10,      // A: speed x 10
    input  wire        reject,           // A: swipe refused ...
    input  wire [1:0]  reject_msg,       //    ... why
    input  wire        cancel,           // A: swipe cancelled / too short
    input  wire [7:0]  ball_rev,         // B: side spin left (REVS bar)
    input  wire signed [15:0] ball_vy,   // B: ball speed down the lane
    input  wire [15:0] ball_x,           // B: ball position (POS units)
    input  wire [15:0] ball_y,
    input  wire [`BP_W-1:0] ball_phase,  // B
    input  wire [6:0]  stance_in,        // A: stance (inches)
    input  wire [6:0]  target_in,        // A: aim target (inches)
    input  wire        lefty,
    input  wire        aim_zoom,         // game_fsm: zoom held
    input  wire [7:0]  spare_made,       // (not used)
    input  wire [7:0]  spare_tries,      // (not used)
    output reg  [15:0] color,
    output reg         en,
    output reg  [`TX_W-1:0] txt
);
`include "txt_helpers.vh"
`include "strings_map.vh"
`include "bcd_fns.vh"

    localparam [15:0] W = `C_WHITE, Y = `C_YELLOW, DIM = 16'h8C71, LBL = 16'h9D9B;
    wire neon = settings[`SET_THEME];
    assign card_addr = {player, 4'd0};

    // frame counter: blinking and the little lane
    reg [7:0] fr;
    always @(posedge clk) begin
        if (rst)             fr <= 0;
        else if (tick_frame) fr <= fr + 8'd1;
    end

    // the last throw, and the swipe message timer (90 frames = 1.5 s)
    reg [7:0] l_mph;                     // speed x 10
    reg [4:0] l_spin;                    // |spin|
    reg       l_left;                    // spin > 0: hooks left
    reg [7:0] msg_frames;
    reg [1:0] msg;                       // which message
    wire [`SPIN_W-2:0] spin_abs = throw_spin[`SPIN_W-1] ? -throw_spin[`SPIN_W-2:0] : throw_spin[`SPIN_W-2:0];
    always @(posedge clk) begin
        if (rst) begin
            l_mph <= 0; l_spin <= 0; l_left <= 0; msg_frames <= 0; msg <= 0;
        end else if (throw_valid) begin
            l_mph <= throw_mph10; l_spin <= spin_abs; l_left <= ~throw_spin[`SPIN_W-1]; msg_frames <= 0;
        end else if (reject || cancel) begin
            msg <= cancel ? `GM_CANCEL : reject_msg; msg_frames <= 8'd90;
        end else if (tick_frame && msg_frames != 0) begin
            msg_frames <= msg_frames - 8'd1;
        end
    end

    // entry board: where the ball crosses the head-pin row (714 in)
    reg [6:0] x_entry;
    reg       e_ok;
    reg       y_prev_lo;
    always @(posedge clk) begin
        y_prev_lo <= (ball_y < 16'd45696);
        if (rst) begin
            x_entry <= 0; e_ok <= 0;
        end else if (throw_valid) begin
            e_ok <= 1'b0;
        end else if (y_prev_lo && ball_y >= 16'd45696 && ball_phase != `BP_GUTTER && ball_phase != `BP_PIT) begin
            x_entry <= ball_x[12:6]; e_ok <= 1'b1;
        end
    end

    // board numbers (3 instances of vh_board)
    reg  [6:0] st_q, tg_q;
    wire [6:0] e_board, bd_board, tg_board;
    // board numbers: entry point, stance, target
    vh_board u_be (.x(x_entry), .lefty(lefty), .board(e_board));
    vh_board u_bs (.x(st_q),    .lefty(lefty), .board(bd_board));
    vh_board u_bt (.x(tg_q),    .lefty(lefty), .board(tg_board));
    wire pocket = e_ok && (e_board >= 7'd16) && (e_board <= 7'd20);   // ~17.5 board = the pocket

    // digits of every number, registered
    reg [11:0] b_s0, b_s1, b_mph, b_live, b_eb, b_bd, b_tg;
    reg [17:0] live10;
    // live speed: vy x 145, then >> 10 = mph x 10
    always @(posedge clk) live10 <= (ball_vy[15] ? 18'd0 : {2'b00, ball_vy}) * 8'd145;
    // digits, updated every clock
    always @(posedge clk) begin
        b_s0   <= bcd9(score0);
        b_s1   <= bcd9(score1);
        b_mph  <= bcd9({1'b0, l_mph});
        b_live <= bcd9(live10[17:10] > 8'd250 ? 9'd250 : {1'b0, live10[17:10]});
        b_eb   <= bcd9({2'b00, e_board});
        st_q   <= stance_in; tg_q <= target_in;
        b_bd   <= bcd9({2'b00, bd_board});
        b_tg   <= bcd9({2'b00, tg_board});
    end
    // while rolling show the live speed, otherwise the speed of the throw
    wire [11:0] b_spd = (game_state == `GS_ROLL || game_state == `GS_PINACTION) ? b_live : b_mph;
    // digit k (2 = hundreds) with leading blanks
    function [5:0] dg;
        input [11:0] b; input [1:0] k;
        case (k)
            2'd2: dg = (b[11:8] == 0) ? 6'd0 : 6'd16 + b[11:8];
            2'd1: dg = (b[11:4] == 0) ? 6'd0 : 6'd16 + b[7:4];
            default: dg = 6'd16 + b[3:0];
        endcase
    endfunction
    // |spin| as tens and ones
    wire [3:0] sp_t  = (l_spin >= 5'd30) ? 4'd3 : (l_spin >= 5'd20) ? 4'd2 : (l_spin >= 5'd10) ? 4'd1 : 4'd0;
    wire [4:0] sp_o5 = l_spin - {sp_t, 3'b000} - {1'b0, sp_t, 1'b0};
    wire [3:0] sp_o  = sp_o5[3:0];

    // PANEL (320 x 240 grid): box hx 268..319, hy 2..109; content from (270, 4)
    wire in_panel = (hx >= `H_PANEL_X0) && (hy >= 8'd2) && (hy <= `H_PANEL_Y1);
    wire pan_edge = in_panel && (hx == `H_PANEL_X0 || hy == 8'd2 || hy == `H_PANEL_Y1 || hx == 9'd319);
    wire [8:0] lx9 = hx - (`H_PANEL_X0 + 9'd2);
    wire [6:0] lx  = lx9[6:0];                      // 0..47 inside the panel
    wire [7:0] ly8 = hy - 8'd4;
    wire [6:0] ly  = ly8[6:0];                      // 0..103 inside the panel
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
    // panel labels (6 chars): 0 FRAME 1 BALL 2 SCORE 3 SPEED 4 POWER 5 SPIN 6 REVS 7 BOARD 8 TARGET 9 ENTRY 10 POCKET
    function [10:0] vpn; input [3:0] i; input [3:0] c;
        vpn = `S_VPN + {i, 2'b00} + {i, 1'b0} + c;
    endfunction
    // power level 0..7: live while the ball is held, else from the throw speed
    wire [2:0] pow = grabbing ? live_power :
                     (l_mph == 0) ? 3'd0 :
                     (l_mph >= 8'd210) ? 3'd7 : (l_mph >= 8'd190) ? 3'd6 : (l_mph >= 8'd175) ? 3'd5 :
                     (l_mph >= 8'd160) ? 3'd4 : (l_mph >= 8'd145) ? 3'd3 : (l_mph >= 8'd130) ? 3'd2 : 3'd1;
    wire [5:0] pow_w = {pow, 2'b00} + {1'b0, pow, 1'b0} - {3'd0, pow};      // 5 px per level
    wire [9:0] spw10 = l_spin * 5'd23;
    wire [4:0] spw   = spw10[9:5];
    wire [9:0] rvw10 = ball_rev * 2'd3;                                     // revs bar: rev x 3 / 16, max 42
    wire [5:0] rvw   = (rvw10[9:4] > 6'd42) ? 6'd42 : rvw10[9:4];
    wire signed [7:0] sdx = $signed({1'b0, lx}) - 8'sd23;

    // pin diagram 7 8 9 10 / 4 5 6 / 2 3 / 1 : 3x3 dots, red centre when standing
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

    wire [4:0] fno = {1'b0, frame} + 5'd1;          // frame number 1..10

    // the panel: graphics first, then the text band by band
    reg [15:0] p_col; reg [`TX_W-1:0] p_txt;
    always @(*) begin
        p_txt = {`TX_W{1'b0}};
        // graphics: box, bars, pin diagram
        p_col = pan_edge ? 16'h4208 : (ly < 7'd52) ? 16'h0862 : 16'h0841;
        if (pd_hit) p_col = pins_standing[pd_k] ? (pd_core ? `C_RED : W) : 16'h31A6;
        else if (ly >= 7'd53 && ly <= 7'd56 && lx >= 7'd2 && lx <= 7'd45)                    // POWER bar
            p_col = (lx - 7'd2 < {1'b0, pow_w}) ? ((pow >= 3'd6) ? `C_RED : (pow >= 3'd4) ? `C_ORANGE : `C_GREEN) : 16'h2104;
        else if (ly >= 7'd64 && ly <= 7'd67 && lx >= 7'd1 && lx <= 7'd45) begin               // SPIN bar from the centre
            if (sdx == 0) p_col = W;
            else if (l_left && sdx < 0 && -sdx <= $signed({3'b000, spw})) p_col = `C_CYAN;
            else if (!l_left && sdx > 0 && sdx <= $signed({3'b000, spw})) p_col = `C_MAGENTA;
            else p_col = 16'h2104;
        end else if (ly >= 7'd75 && ly <= 7'd77 && lx >= 7'd2 && lx <= 7'd45 && !e_ok)       // REVS bar
            p_col = (lx - 7'd2 < {1'b0, rvw}) ? 16'hFC60 : 16'h2104;
        // text, band by band from the top
        if (in_band(ly, 7'd2, 7'd5)) begin                                                    // FRAME   (P1/P2)
            if (pc < 4'd5) p_txt = tx_s(vpn(4'd0, pc), 1'b1, pfx, bfy(ly, 7'd2), LBL, 0, 1'b0);
            else if (kind[`PK_TWO] && pc == 4'd10) p_txt = tx_l(6'd48, 1'b1, pfx, bfy(ly, 7'd2), player ? `C_CYAN : Y, 0, 1'b0);
            else if (kind[`PK_TWO] && pc == 4'd11) p_txt = tx_l(player ? 6'd18 : 6'd17, 1'b1, pfx, bfy(ly, 7'd2), player ? `C_CYAN : Y, 0, 1'b0);
        end else if (in_band(ly, 7'd8, 7'd8) && c6p < 4'd2) begin                             // frame number (5x7)
            p_txt = tx_l(c6p == 0 ? (fno >= 5'd10 ? 6'd17 : 6'd0) : 6'd16 + ((fno >= 5'd10) ? 6'd0 : {2'b00, fno[3:0]}),
                         1'b0, f6p, bfy(ly, 7'd8), W, 0, 1'b0);
        end else if (in_band(ly, 7'd10, 7'd5) && pc >= 4'd5) begin                            // BALL n
            if (pc < 4'd9) p_txt = tx_s(vpn(4'd1, pc - 4'd5), 1'b1, pfx, bfy(ly, 7'd10), LBL, 0, 1'b0);
            else if (pc == 4'd10) p_txt = tx_l(dig({2'b00, ball_no} + 4'd1), 1'b1, pfx, bfy(ly, 7'd10), W, 0, 1'b0);
        end else if (in_band(ly, 7'd18, 7'd5)) begin                                          // SCORE
            if (pc < 4'd5) p_txt = tx_s(vpn(4'd2, pc), 1'b1, pfx, bfy(ly, 7'd18), LBL, 0, 1'b0);
        end else if (in_band(ly, 7'd24, 7'd8) && c6p < 4'd3) begin                            // the score (5x7)
            p_txt = tx_l(dg(player ? b_s1 : b_s0, 2'd2 - c6p[1:0]), 1'b0, f6p, bfy(ly, 7'd24), Y, 0, 1'b0);
        end else if (in_band(ly, 7'd26, 7'd5) && pc >= 4'd8) begin                            // the other player (2P)
            if (kind[`PK_TWO]) begin
                if (pc == 4'd8) p_txt = tx_l(player ? 6'd17 : 6'd18, 1'b1, pfx, bfy(ly, 7'd26), player ? Y : `C_CYAN, 0, 1'b0);
                else p_txt = tx_l(dg(player ? b_s0 : b_s1, (pc == 4'd9) ? 2'd2 : (pc == 4'd10) ? 2'd1 : 2'd0),
                                  1'b1, pfx, bfy(ly, 7'd26), DIM, 0, 1'b0);
            end
        end else if (in_band(ly, 7'd33, 7'd5)) begin                                          // SPEED
            if (pc < 4'd5) p_txt = tx_s(vpn(4'd3, pc), 1'b1, pfx, bfy(ly, 7'd33), LBL, 0, 1'b0);
        end else if (in_band(ly, 7'd39, 7'd8) && c6p < 4'd4) begin                            // nn.n (5x7)
            case (c6p)
                4'd0:    p_txt = tx_l(dg(b_spd, 2'd2), 1'b0, f6p, bfy(ly, 7'd39), W, 0, 1'b0);
                4'd1:    p_txt = tx_l(6'd16 + b_spd[7:4], 1'b0, f6p, bfy(ly, 7'd39), W, 0, 1'b0);
                4'd2:    p_txt = tx_l(6'd14, 1'b0, f6p, bfy(ly, 7'd39), W, 0, 1'b0);          // '.'
                default: p_txt = tx_l(6'd16 + b_spd[3:0], 1'b0, f6p, bfy(ly, 7'd39), W, 0, 1'b0);
            endcase
        end else if (in_band(ly, 7'd41, 7'd5) && pc >= 4'd9) begin                            // MPH
            p_txt = tx_s(`S_MPHW + pc - 4'd9, 1'b1, pfx, bfy(ly, 7'd41), LBL, 0, 1'b0);
        end else if (in_band(ly, 7'd47, 7'd5)) begin                                          // POWER
            if (pc < 4'd5) p_txt = tx_s(vpn(4'd4, pc), 1'b1, pfx, bfy(ly, 7'd47), LBL, 0, 1'b0);
        end else if (in_band(ly, 7'd58, 7'd5)) begin                                          // SPIN <nn / >nn
            if (pc < 4'd4) p_txt = tx_s(vpn(4'd5, pc), 1'b1, pfx, bfy(ly, 7'd58), LBL, 0, 1'b0);
            else if (pc == 4'd9)  p_txt = tx_l(l_spin == 0 ? 6'd0 : (l_left ? 6'd44 : 6'd50), 1'b1, pfx, bfy(ly, 7'd58), Y, 0, 1'b0);
            else if (pc == 4'd10) p_txt = tx_l(sp_t == 0 ? 6'd0 : dig(sp_t), 1'b1, pfx, bfy(ly, 7'd58), Y, 0, 1'b0);
            else if (pc == 4'd11) p_txt = tx_l(dig(sp_o), 1'b1, pfx, bfy(ly, 7'd58), Y, 0, 1'b0);
        end else if (in_band(ly, 7'd69, 7'd5)) begin                                          // REVS, or ENTRY nn
            if (!e_ok) begin
                if (pc < 4'd4) p_txt = tx_s(vpn(4'd6, pc), 1'b1, pfx, bfy(ly, 7'd69), LBL, 0, 1'b0);
            end else begin
                if (pc < 4'd5) p_txt = tx_s(vpn(4'd9, pc), 1'b1, pfx, bfy(ly, 7'd69), LBL, 0, 1'b0);
                else if (pc == 4'd6) p_txt = tx_l(dg(b_eb, 2'd1), 1'b1, pfx, bfy(ly, 7'd69), W, 0, 1'b0);
                else if (pc == 4'd7) p_txt = tx_l(dg(b_eb, 2'd0), 1'b1, pfx, bfy(ly, 7'd69), W, 0, 1'b0);
            end
        end else if (in_band(ly, 7'd75, 7'd5) && e_ok && pocket) begin                        // POCKET (blinks)
            if (pc >= 4'd1 && pc < 4'd7) p_txt = tx_s(vpn(4'd10, pc - 4'd1), 1'b1, pfx, bfy(ly, 7'd75), fr[3] ? Y : `C_ORANGE, 0, 1'b0);
        end
    end

    // OVERLAYS (160 x 120): centred ones on a 112-wide view, moved right by 24 (vxc)
    wire [7:0]  vxc  = vx - 8'd24;
    // double-size 5x7 text: 12 x 16 cells from x 14
    wire [7:0]  bgx  = vxc - 8'd14;
    wire [12:0] bg43 = bgx[6:0] * 6'd43;
    wire [3:0]  bcol = bg43[12:9];                 // / 12
    wire [6:0]  bcx  = bgx[6:0] - {bcol, 3'b000} - {1'b0, bcol, 2'b00};
    wire [2:0]  bfx  = bcx[3:1];
    wire [6:0]  bly  = vy - 7'd56;
    wire [2:0]  bfyy = bly[3:1];
    wire in_pop_box = (vxc >= 8'd8) && (vxc <= 8'd103) && (vy >= 7'd52) && (vy <= 7'd75);
    wire pop_edge   = in_pop_box && (vxc == 8'd8 || vxc == 8'd103 || vy == 7'd52 || vy == 7'd75);
    wire in_pop_txt = (vxc >= 8'd14) && (vxc < 8'd98) && (vy >= 7'd56) && (vy < 7'd72);
    reg [15:0] pop_col;                            // popup colour by kind
    always @(*) begin
        case (popup_id)
            4'd0, 4'd4, 4'd5: pop_col = fr[2] ? 16'hFD20 : `C_MAGENTA;
            4'd1, 4'd6:       pop_col = 16'h03EF;
            4'd3:             pop_col = `C_ORANGE;
            4'd2, 4'd7:       pop_col = 16'h630C;
            default:          pop_col = 16'h0019;
        endcase
    end
    // what is showing now
    wire show_pop    = (popup_id != 4'd15) && (game_state == `GS_RESULT);
    wire show_banner = banner && !show_pop && (game_state == `GS_AIM || game_state == `GS_SWEEP);
    wire       vc_ok = (vxc < 8'd112);             // inside the centred area
    wire [7:0] pq    = (vxc - 8'd24) >> 2;         // pause hint column
    wire [6:0] sgy   = vy - (sign_row - 7'd2);     // sign glyph row 0..4
    wire [3:0] vc6   = vc_ok ? c6(vxc[6:0]) : 4'd15;
    wire [2:0] vf6   = f6(vxc[6:0]);
    wire in_ban_box  = (vxc >= 8'd20) && (vxc <= 8'd91) && (vy >= 7'd38) && (vy <= 7'd51);
    wire ban_edge    = in_ban_box && (vxc == 8'd20 || vxc == 8'd91 || vy == 7'd38 || vy == 7'd51);
    wire [5:0] vc4   = vx[7:2];                    // 3x5 left-aligned rows
    wire [2:0] vf4   = {1'b0, vx[1:0]};
    wire [4:0] vc4c  = vc_ok ? vxc[6:2] : 5'd31;   // 3x5 centred rows (the sign)
    wire [2:0] vf4c  = {1'b0, vxc[1:0]};
    wire aiming = (game_state == `GS_AIM);

    // the overlays: a box first, then a text line on top
    reg o_en; reg [15:0] o_col; reg [`TX_W-1:0] o_txt;
    always @(*) begin
        o_en = 1'b0; o_col = `C_BLACK; o_txt = {`TX_W{1'b0}};
        // boxes: PAUSED > popup > FRAME banner
        if (paused && in_pop_box) begin
            o_en = 1'b1; o_col = pop_edge ? W : 16'h0010;
            if (vy >= 7'd58 && vy < 7'd66 && vc6 >= 4'd6 && vc6 < 4'd12)                  // "PAUSED"
                o_txt = tx_s(`S_HINT + 11'd60 + vc6 - 4'd6, 1'b0, vf6, vy[2:0] - 3'd2, W, 0, 1'b0);
            else if (vy >= 7'd68 && vy <= 7'd72 && vxc >= 8'd24 && vxc < 8'd88)            // "CLICK: QUIT GAME"
                o_txt = tx_s(`S_PAUSEH + {5'd0, pq[5:0]}, 1'b1, {1'b0, vxc[1:0]}, vy[2:0] - 3'd4, Y, 0, 1'b0);
        end else if (show_pop && in_pop_box) begin
            o_en = 1'b1; o_col = pop_edge ? W : pop_col;
            if (in_pop_txt && bcol < 4'd7) begin
                if (popup_id == 4'd8) begin                                                // "n PINS"
                    if (bcol == 4'd0) o_txt = tx_l(dig(popup_n), 1'b0, bfx, bfyy, W, 0, 1'b0);
                    else if (bcol >= 4'd2 && bcol < 4'd6) o_txt = tx_s(`S_POP + 11'd64 + bcol - 4'd2, 1'b0, bfx, bfyy, W, 0, 1'b0);
                end else
                    o_txt = tx_s(`S_POP + {popup_id, 3'd0} + bcol, 1'b0, bfx, bfyy, W, 0, 1'b0);
            end
        end else if (show_banner && in_ban_box) begin
            o_en = 1'b1; o_col = ban_edge ? 16'h8410 : 16'h0109;
            if (vy >= 7'd41 && vy < 7'd49) begin                                           // "FRAME n"
                if (vc6 >= 4'd4 && vc6 < 4'd9) o_txt = tx_s(`S_POP + 11'd72 + vc6 - 4'd4, 1'b0, vf6, vy[2:0] - 3'd1, W, 0, 1'b0);
                else if (vc6 == 4'd10 && fno >= 5'd10) o_txt = tx_l(6'd17, 1'b0, vf6, vy[2:0] - 3'd1, Y, 0, 1'b0);
                else if (vc6 == 4'd11) o_txt = tx_l(6'd16 + ((fno >= 5'd10) ? 6'd0 : {2'b00, fno[3:0]}), 1'b0, vf6, vy[2:0] - 3'd1, Y, 0, 1'b0);
            end
        end
        // text lines (replace the request above): the masking-unit sign, ZOOM, BD/TG, hints
        if (sign_ok && vy >= sign_row - 7'd2 && vy <= sign_row + 7'd2 && vc4c >= 5'd9 && vc4c < 5'd19)
            o_txt = tx_s(`S_VTITLE + vc4c - 5'd9, 1'b1, vf4c, sgy[2:0], neon ? `C_CYAN : 16'hFE60, 0, 1'b0);
        // ZOOM title (right button held)
        else if (aiming && aim_zoom && vy >= 7'd33 && vy < 7'd41 && vc6 >= 4'd5 && vc6 < 4'd13)
            o_txt = tx_s(`S_PVIEW + vc6 - 4'd5, 1'b0, vf6, vy[2:0] - 3'd1, Y, `C_BLACK, 1'b1);
        // board / target readout while aiming: "BD nn  TG nn" (3x5, y 104..108)
        else if (aiming && !grabbing && vy >= 7'd104 && vy <= 7'd108 && vc4 < 5'd14) begin
            case (vc4)
                5'd0:  o_txt = tx_s(vpn(4'd7, 4'd0), 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);       // B
                5'd1:  o_txt = tx_s(vpn(4'd7, 4'd4), 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);       // D
                5'd3:  o_txt = tx_l(dg(b_bd, 2'd1), 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);
                5'd4:  o_txt = tx_l(dg(b_bd, 2'd0), 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);
                5'd7:  o_txt = tx_s(vpn(4'd8, 4'd0), 1'b1, vf4, vy[2:0], `C_CYAN, `C_BLACK, 1'b1);  // T
                5'd8:  o_txt = tx_s(vpn(4'd8, 4'd3), 1'b1, vf4, vy[2:0], `C_CYAN, `C_BLACK, 1'b1);  // G
                5'd10: o_txt = tx_l(dg(b_tg, 2'd1), 1'b1, vf4, vy[2:0], `C_CYAN, `C_BLACK, 1'b1);
                5'd11: o_txt = tx_l(dg(b_tg, 2'd0), 1'b1, vf4, vy[2:0], `C_CYAN, `C_BLACK, 1'b1);
                default: o_txt = tx_l(6'd0, 1'b1, vf4, vy[2:0], Y, `C_BLACK, 1'b1);
            endcase
        end
        // hint row (3x5, y 112..116): swipe message > SAVING > what to do now
        else if (vy >= 7'd112 && vy <= 7'd116) begin
            if (msg_frames != 0 && vc4 < 5'd13)
                o_txt = tx_s(`S_AMSG + {msg, 3'b000} + {msg, 2'b00} + msg + vc4, 1'b1, vf4, vy[2:0], `C_RED, `C_BLACK, 1'b1);
            else if (saving && fr[4] && vc4 < 5'd6)
                o_txt = tx_s(`S_HINT + 11'd90 + vc4, 1'b1, vf4, vy[2:0], `C_ORANGE, `C_BLACK, 1'b1);
            else if (aiming && aim_zoom && vc4 < 5'd26)
                o_txt = tx_s(`S_PVIEWH + vc4, 1'b1, vf4, vy[2:0], W, `C_BLACK, 1'b1);
            else if (vc4 < 5'd15) case (game_state)
                `GS_AIM:    o_txt = tx_s(`S_HINT + vc4,          1'b1, vf4, vy[2:0], W, `C_BLACK, 1'b1);
                `GS_THROW:  o_txt = tx_s(`S_HINT + 11'd15 + vc4, 1'b1, vf4, vy[2:0], Y, `C_BLACK, vc4 < 5'd14);
                `GS_RESULT: o_txt = tx_s(`S_HINT + 11'd30 + vc4, 1'b1, vf4, vy[2:0], 16'hAD55, `C_BLACK, vc4 < 5'd13);
                default: ;
            endcase
        end
    end

    // REPLAY camera look (corner brackets in the 320 x 240 grid)
    wire cb_x   = (hx >= 9'd8 && hx <= 9'd9) || (hx >= 9'd310 && hx <= 9'd311);
    wire cb_y   = (hy >= 8'd8 && hy <= 8'd9) || (hy >= 8'd230 && hy <= 8'd231);
    wire cb_xr  = (hx >= 9'd8 && hx <= 9'd37) || (hx >= 9'd282 && hx <= 9'd311);
    wire cb_yr  = (hy >= 8'd8 && hy <= 8'd37) || (hy >= 8'd202 && hy <= 8'd231);
    wire corner = (cb_x && cb_yr) || (cb_y && cb_xr);
    wire [7:0] rpx = vx - 8'd20;                    // "REPLAY" at x 20.., y 9..15
    wire [3:0] rpc = (rpx < 8'd36) ? c6(rpx[6:0]) : 4'd15;
    wire [2:0] rpf = f6(rpx[6:0]);
    wire rdot  = (vx >= 8'd12 && vx <= 8'd16 && vy >= 7'd10 && vy <= 7'd14) &&
                 !((vx == 8'd12 || vx == 8'd16) && (vy == 7'd10 || vy == 7'd14));   // round-ish dot
    wire rp_on = fr[5] || fr[4];                    // on 3/4 of the time, ~1 Hz

    // the replay look
    reg r_en; reg [15:0] r_col; reg [`TX_W-1:0] r_txt;
    always @(*) begin
        r_en = 1'b0; r_col = `C_BLACK; r_txt = {`TX_W{1'b0}};
        if (!u_in) begin r_en = 1'b1; r_col = 16'h0841; end                             // beside the lane
        if (corner) begin r_en = 1'b1; r_col = W; end
        else if (rp_on && rdot) begin r_en = 1'b1; r_col = `C_RED; end
        else if (rp_on && vy >= 7'd9 && vy <= 7'd15 && rpc < 4'd6)
            r_txt = tx_s(`S_HINT + 11'd75 + rpc, 1'b0, rpf, vy[2:0] - 3'd1, W, 0, 1'b0);
    end

    // MENU BACKDROP around the UI window
    wire in_border = (vx >= 8'd29) && (vx <= 8'd130) && (vy >= 7'd25) && (vy <= 7'd94);
    // title "STRIKELINE" in double size: x 20..139, y 4..19
    wire [7:0]  tgx  = vx - 8'd20;
    wire [12:0] tg43 = tgx[6:0] * 6'd43;
    wire [3:0]  tcol = tg43[12:9];
    wire [6:0]  tcx  = tgx[6:0] - {tcol, 3'b000} - {1'b0, tcol, 2'b00};
    wire [6:0]  tly  = vy - 7'd4;
    wire in_title = (vx >= 8'd20) && (vx < 8'd140) && (vy >= 7'd4) && (vy < 7'd20);
    // the little lane at the bottom: a ball rolls in every 128 frames
    wire [6:0] lane_t  = fr[6:0];
    wire [7:0] ball_px = 8'd12 + {1'b0, lane_t};
    wire in_mlane = (vy >= 7'd107) && (vy <= 7'd115) && (vx >= 8'd8) && (vx <= 8'd151);
    wire mball    = (vy >= 7'd110) && (vy <= 7'd112) && (vx >= ball_px) && (vx <= ball_px + 8'd2) && (lane_t < 7'd127);
    wire pins_dn  = (lane_t > 7'd126) || (lane_t < 7'd24);
    wire mpin     = (vx == 8'd145 || vx == 8'd148) && (vy == 7'd109 || vy == 7'd111 || vy == 7'd113) && !pins_dn;
    // vertical gradient + faint diagonal stripes
    wire [15:0] c_bg = {2'b00, vy[6:5], 1'b1, 3'b000, vy[6:5], 1'b1, 2'b01, vy[6:4]} +
                       ((((vx + {1'b0, vy}) & 8'h1F) < 8'd2) ? 16'h0841 : 16'h0000);

    // the menu backdrop
    reg [15:0] k_col; reg [`TX_W-1:0] k_txt;
    always @(*) begin
        k_col = c_bg; k_txt = {`TX_W{1'b0}};
        if (in_border) k_col = (vx == 8'd29 || vx == 8'd130 || vy == 7'd25 || vy == 7'd94) ?
                               (neon ? `C_CYAN : 16'hFE60) : (neon ? 16'h780F : 16'h8A00);
        else if (in_mlane) begin
            k_col = (vy == 7'd107 || vy == 7'd115) ? 16'h39E8 : 16'hDDD0;
            if (mball) k_col = 16'hA8E7;
            else if (mpin) k_col = W;
        end
        if (in_title && tcol < 4'd10)
            k_txt = tx_s(`S_VTITLE + tcol, 1'b0, tcx[3:1], tly[3:1],
                         neon ? (tly[3] ? `C_MAGENTA : `C_CYAN) : (tly[3] ? 16'hFC00 : 16'hFEA0), 0, 1'b0);
    end

    // the multiplexer: which part draws this pixel
    always @(*) begin
        en = 1'b0; color = `C_BLACK; txt = {`TX_W{1'b0}};
        if (rp_full)       begin en = r_en; color = r_col; txt = r_txt; end    // replay
        else if (v3d) begin
            if (in_panel)  begin en = 1'b1; color = p_col; txt = p_txt; end    // panel
            else           begin en = o_en; color = o_col; txt = o_txt; end    // overlays
        end else if (!u_in) begin en = 1'b1; color = k_col; txt = k_txt; end   // menu backdrop
    end
endmodule
