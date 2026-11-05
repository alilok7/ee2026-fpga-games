`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// persp_proj.v : where the ball and the pins appear in the first-person view
//-----------------------------------------------------------------------------
// Owner   : Student B
// Camera  : fixed height and tilt. v3.2: in the 320 x 240 picture the horizon
//           is on row H_HOR = 60 and the lane centre on column H_CX = 160
//           (v3.3: the view is the full screen width).
//           A point on the lane `dz` inches ahead of the camera appears on row
//             row = 60 + r,   r = 2K / dz      (K = 3060 unzoomed; r = 1..179)
//           and one inch across the lane is r / 51 px wide there:
//             x = 160 + (wx - 30) * r / 51  ~  160 + ((wx - 30) * r * 5) >> 8
//           (the v3 160 x 120 camera with every pixel split in four: the same
//           formulas with r doubled)
// Method  : once per frame (tick_frame) a small FSM projects the 11 objects
//           (ball + 10 pins) one after another; the only division (2K / dz)
//           uses a 1-bit-per-clock divider: ~11 x 30 = 330 clocks per frame.
//           The renderers then only compare pixel positions.
// Zoom    : (v3.1) K = k_fp from the camera. Every size below is in units of r
//           (one inch is r / 51 px at any zoom), so only the division changes.
// Pins    : every pin on the deck is projected, so the 3-D view can show the
//           pin action:
//             upright / wobbling / just hit : a silhouette, size class 0..31
//                                             (height 2..53 px), from pin_fp.mem
//             falling (half) / down         : a "bar" = the lying pin, centred
//                                             on its body (C's pin_vis gives
//                                             that centre, v3.4), half-width hw (across
//                                             the screen) and half-height hh
//                                             (depth r^2/6120 + thickness),
//                                             with the red neck toward the head
// Output  : ball {visible, x, floor row, radius px};
//           per pin {vis, bar, x[9:0], row[7:0], cls|hw[4:0], hh[4:0], neck[4:0], 1'b0}
//=============================================================================
(* use_dsp = "yes" *)
module persp_proj (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire signed [10:0] cam_fp,     // world y of the camera (inches)
    input  wire [15:0] k_fp,             // v3.1: lens constant K (3060, x1 .. x8 while zoomed)
    input  wire        ball_visible,
    input  wire [15:0] ball_x,           // POS
    input  wire [15:0] ball_y,
    input  wire [239:0] pin_vis,          // C: 10 x {x6, y10, state3, dir3, stage2}
    output reg         b_vis,
    output reg  signed [9:0] b_x,
    output reg  [7:0]  b_row,            // row of the floor contact
    output reg  [3:0]  b_rad,
    output wire [359:0] pins_fp          // 10 x 36 bit (see above)
);
    // one projection at a time
    reg  [3:0]  k;                        // 0 = ball, 1..10 = pins
    reg         dv_go;
    reg  [15:0] num, den;
    wire [15:0] quo;
    wire        dv_done, dv_busy;
    div_seq #(.W(16)) u_div (.clk(clk), .rst(rst), .start(dv_go), .num(num), .den(den),
                             .quo(quo), .done(dv_done), .busy(dv_busy));

    // the object k: its pin_vis word is registered first (S_PRE, timing)
    reg  [23:0] pv;
    wire [2:0]  ps = pv[7:5];
    wire [2:0]  pd = pv[4:2];
    wire [1:0]  pg = pv[1:0];
    wire        p_up  = (ps == `PS_STANDING) || (ps == `PS_WOBBLING) || (ps == `PS_FALLING && pg == 2'd0);
    wire        p_bar = (ps == `PS_DOWN) || (ps == `PS_FALLING && pg != 2'd0);
    wire        p_half = (ps == `PS_FALLING);              // half way down
    // fall direction: 0 = +y (away), clockwise. ax/ay = -1, 0, +1 per axis
    wire signed [1:0] dsx = (pd == 3'd1 || pd == 3'd2 || pd == 3'd3) ? 2'sd1 :
                            (pd == 3'd5 || pd == 3'd6 || pd == 3'd7) ? -2'sd1 : 2'sd0;
    wire signed [1:0] dsy = (pd == 3'd7 || pd == 3'd0 || pd == 3'd1) ? 2'sd1 :
                            (pd == 3'd3 || pd == 3'd4 || pd == 3'd5) ? -2'sd1 : 2'sd0;
    wire        diag = (pd[0] == 1'b1);
    // centre offset of a lying pin (inches): 7.5 straight, 5.3 diagonal; half while falling
    wire [3:0]  c_off = diag ? (p_half ? 4'd3 : 4'd5) : (p_half ? 4'd4 : 4'd7);
    // extents in quarter inches: along the body (+1.2 in of radius) and across it (1.2 in)
    wire [5:0]  e_long = diag ? (p_half ? 6'd15 : 6'd26) : (p_half ? 6'd20 : 6'd35);
    wire [5:0]  e_x = (dsx == 0) ? 6'd5 : e_long;            // across the screen
    wire [5:0]  e_y = (dsy == 0) ? 6'd5 : e_long;            // in depth
    // (timing) offsets by selection, not multiplication; registered in S_SEL0
    wire signed [11:0] offx = (!p_bar || dsx == 0) ? 12'sd0 : (dsx > 0) ? $signed({8'd0, c_off}) : -$signed({8'd0, c_off});
    wire signed [11:0] offy = (!p_bar || dsy == 0) ? 12'sd0 : (dsy > 0) ? $signed({8'd0, c_off}) : -$signed({8'd0, c_off});
    reg  signed [11:0] base_x, base_y, offx_q, offy_q;
    reg         on_q, bar_q, fall0_q;
    reg  signed [1:0] dsx_q;
    reg  [5:0]  ex_q, ey_q;
    wire signed [11:0] o_wx = base_x + offx_q;
    wire signed [11:0] o_wy = base_y + offy_q;
    wire        o_on = on_q;

    // ---------------- per-object registers -------------------------------
    reg  [7:0]  r_q;                          // 1..179
    reg  signed [11:0] s_wx, s_wy;
    reg         s_on, s_bar, s_fall0;
    reg  signed [1:0] s_dsx;
    reg  [5:0]  s_ex, s_ey;
    reg  signed [21:0] xo_q;
    reg  [15:0] rr_q;                         // r^2
    reg  [15:0] hw_q;                         // ex * r * 5 (>> 10 = px)
    reg  [26:0] dep_q;                        // ey * r^2 * 21 (>> 19 = rows)
    reg  [4:0]  cls_q;                        // registered size values (timing)
    reg  [3:0]  brad_q, th_q;
    reg  [35:0] word_q;                       // the finished pin word, written in S_WR
    wire [7:0]  r = r_q;
    wire [9:0]  r5 = {r, 2'b00} + {2'b00, r};
    wire signed [21:0] xo = ((s_wx - 12'sd30) * $signed({1'b0, r5})) >>> 8;
    wire [14:0] h75  = r * 7'd75;                 // pin height px * 256
    wire [6:0]  h    = h75[14:8];                 // 0..52
    // 32 size classes; the heights match PIN_H in tools/gen_tables.py
    wire [4:0]  cls  = (h >= 7'd53) ? 5'd31 : (h >= 7'd50) ? 5'd30 : (h >= 7'd48) ? 5'd29 : (h >= 7'd46) ? 5'd28 :
                       (h >= 7'd44) ? 5'd27 : (h >= 7'd42) ? 5'd26 : (h >= 7'd40) ? 5'd25 : (h >= 7'd38) ? 5'd24 :
                       (h >= 7'd36) ? 5'd23 : (h >= 7'd34) ? 5'd22 : (h >= 7'd32) ? 5'd21 : (h >= 7'd30) ? 5'd20 :
                       (h >= 7'd28) ? 5'd19 : (h >= 7'd26) ? 5'd18 : (h >= 7'd24) ? 5'd17 : (h >= 7'd22) ? 5'd16 :
                       (h >= 7'd20) ? 5'd15 : (h >= 7'd18) ? 5'd14 : (h >= 7'd16) ? 5'd13 : (h >= 7'd14) ? 5'd12 :
                       (h >= 7'd13) ? 5'd11 : (h >= 7'd12) ? 5'd10 : (h >= 7'd11) ? 5'd9  : (h >= 7'd10) ? 5'd8  :
                       (h >= 7'd9)  ? 5'd7  : (h >= 7'd8)  ? 5'd6  : (h >= 7'd7)  ? 5'd5  : (h >= 7'd6)  ? 5'd4  :
                       (h >= 7'd5)  ? 5'd3  : (h >= 7'd4)  ? 5'd2  : (h >= 7'd3)  ? 5'd1  : 5'd0;
    wire [12:0] rad22 = r * 5'd22;                // ball radius px * 256
    wire [11:0] th12  = r * 4'd12;                // thickness of a lying pin, rows * 256
    // bar sizes (registered products -> small px values)
    wire [9:0]  dep_r = dep_q[26:19] > 8'd200 ? 10'd200 : {2'b00, dep_q[26:19]};
    wire [9:0]  th_r  = {6'd0, th_q};

    reg [35:0] pf [0:9];
    genvar g;
    generate for (g = 0; g < 10; g = g + 1) begin : g_o
        assign pins_fp[36*g +: 36] = pf[g];
    end endgenerate

    localparam S_IDLE = 4'd0, S_DIV = 4'd1, S_WAIT = 4'd2, S_SEL = 4'd3, S_RES = 4'd4,
               S_MUL = 4'd5, S_MUL2 = 4'd6, S_OUT = 4'd7, S_PRE = 4'd8, S_MUL3 = 4'd9, S_WR = 4'd10,
               S_SEL0 = 4'd11, S_MUL4 = 4'd12;
    reg [4:0]  hw5_q, hh5_q, neck_q;               // final small values (registered, timing)
    reg signed [9:0] xpos_q, xlean_q;
    reg [7:0]  row_q;
    reg [3:0] st;
    integer q;
    // final bar values
    wire [9:0]  hw_full = {4'd0, hw_q[15:10]};                     // ex*r*5 >> 10
    wire [4:0]  hw5  = (hw_full > 10'd31) ? 5'd31 : (hw_full == 0) ? 5'd1 : hw_full[4:0];
    wire [9:0]  hh_s = (th_r + dep_r + 10'd1) >> 1;
    wire [4:0]  hh5  = (hh_s > 10'd31) ? 5'd31 : (hh_s == 0) ? 5'd1 : hh_s[4:0];
    wire [4:0]  nk_m = (hw5 >> 1);
    wire [4:0]  neck = (s_dsx == 0) ? 5'd0 : (s_dsx > 0) ? {1'b0, nk_m[3:0]} : -{1'b0, nk_m[3:0]};
    wire signed [9:0] xpos = $signed({1'b0, `H_CX}) + xo_q[9:0];
    // a pin that has just been hit leans 2-4 px toward its fall direction
    wire signed [9:0] xlean = s_fall0 ? (s_dsx * $signed({6'd0, r[7], ~r[7], 1'b0})) : 10'sd0;
    always @(posedge clk) begin
        dv_go <= 1'b0;
        if (rst) begin
            st <= S_IDLE; k <= 0; num <= 0; den <= 1;
            s_wx <= 0; s_wy <= 0; s_on <= 0; s_bar <= 0; s_fall0 <= 0; s_dsx <= 0; s_ex <= 0; s_ey <= 0;
            r_q <= 0; xo_q <= 0; rr_q <= 0; hw_q <= 0; dep_q <= 0; pv <= 0; cls_q <= 0; brad_q <= 1; th_q <= 0; word_q <= 0;
            b_vis <= 0; b_x <= 0; b_row <= 0; b_rad <= 0;
            for (q = 0; q < 10; q = q + 1) pf[q] <= 36'd0;
        end else case (st)
            S_IDLE: if (tick_frame) begin k <= 4'd0; st <= S_PRE; end
            S_PRE: begin                                   // object k's pin word (timing)
                pv <= pin_vis[24 * (k - 4'd1) +: 24];
                st <= S_SEL0;
            end
            S_SEL0: begin                                  // decode object k (timing)
                base_x <= (k == 0) ? $signed({2'b00, ball_x[15:6]}) : $signed({6'd0, pv[23:18]});
                base_y <= (k == 0) ? $signed({2'b00, ball_y[15:6]}) : $signed({2'b00, pv[17:8]});
                // v3.4: C's pin_vis already gives a lying pin's body centre
                offx_q <= 12'sd0;
                offy_q <= 12'sd0;
                on_q   <= (k == 0) ? ball_visible : (p_up || p_bar);
                bar_q  <= (k != 0) && p_bar;
                fall0_q <= (k != 0) && (ps == `PS_FALLING) && (pg == 2'd0);
                dsx_q <= dsx; ex_q <= e_x; ey_q <= e_y;
                st <= S_SEL;
            end
            S_SEL: begin                                   // latch object k
                s_wx <= o_wx; s_wy <= o_wy - $signed({cam_fp[10], cam_fp}); s_on <= o_on;
                s_bar <= bar_q; s_fall0 <= fall0_q;
                s_dsx <= dsx_q; s_ex <= ex_q; s_ey <= ey_q;
                st <= S_DIV;
            end
            S_DIV: begin
                // visible only beyond 35 in (the bottom row). (The horizon is
                // far beyond anything on the lane: no far test. v3 bug found
                // by tb_screens: 12'sd3060 does not fit in 12 signed bits and
                // culled every object.)
                if (!s_on || s_wy < 12'sd35) begin
                    if (k == 0) b_vis <= 1'b0; else pf[k - 4'd1] <= 36'd0;
                    if (k == 4'd10) st <= S_IDLE; else begin k <= k + 4'd1; st <= S_PRE; end
                end else begin
                    num <= {k_fp[14:0], 1'b0}; den <= {4'd0, s_wy};      // 2K / dz
                    dv_go <= 1'b1;
                    st <= S_WAIT;
                end
            end
            S_WAIT: if (dv_done) st <= S_RES;
            S_RES:  begin
                // (v3.1) below the bottom row: with a long lens an object can be
                // more than 35 in away and still too near to be on screen
                if (quo > 16'd180) begin
                    if (k == 0) b_vis <= 1'b0; else pf[k - 4'd1] <= 36'd0;
                    if (k == 4'd10) st <= S_IDLE; else begin k <= k + 4'd1; st <= S_PRE; end
                end else begin
                    r_q <= (quo > 16'd179) ? 8'd179 : quo[7:0]; st <= S_MUL;
                end
            end
            S_MUL:  begin
                xo_q <= xo;
                rr_q <= r * r;
                hw_q <= s_ex * r5;                         // ex * r * 5
                st <= S_MUL2;
            end
            S_MUL2: begin dep_q <= s_ey * rr_q * 5'd21; st <= S_MUL3; end
            S_MUL3: begin                                  // small sizes from r (registered, timing)
                cls_q  <= cls;
                brad_q <= (rad22[12:8] == 0) ? 4'd1 : (rad22[12:8] > 5'd15) ? 4'd15 : rad22[11:8];
                th_q   <= th12[11:8];
                st <= S_MUL4;
            end
            S_MUL4: begin                                  // the pin word's fields (registered, timing)
                hw5_q <= hw5; hh5_q <= hh5; neck_q <= neck;
                xpos_q <= xpos; xlean_q <= xlean;
                row_q <= 8'd60 + r - (s_bar ? {5'd0, th_q[3:1]} : 8'd0);
                st <= S_OUT;
            end
            S_OUT:  begin
                if (k == 0) begin
                    b_vis <= 1'b1; b_x <= xpos_q; b_row <= row_q;
                    b_rad <= brad_q;
                end else if (s_bar)
                    word_q <= {1'b1, 1'b1, xpos_q, row_q, hw5_q, hh5_q, neck_q, 1'b0};
                else
                    word_q <= {1'b1, 1'b0, xpos_q + xlean_q, row_q, cls_q, 5'd0, 5'd0, 1'b0};
                st <= S_WR;
            end
            S_WR: begin                                    // write the pin word (timing)
                if (k != 0) pf[k - 4'd1] <= word_q;
                if (k == 4'd10) st <= S_IDLE;
                else begin k <= k + 4'd1; st <= S_PRE; end
            end
            default: st <= S_IDLE;
        endcase
    end
endmodule
