`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// persp_proj.v : where the ball and the pins appear in the first-person view
//-----------------------------------------------------------------------------
// Owner   : Student B
// Camera  : fixed height and tilt, horizon on screen row 12. A point on the
//           lane `dz` inches ahead of the camera appears on screen row
//             row = 12 + r,  r = 1530 / dz        (r = 1..51)
//           and one inch across the lane is r / 51 px wide there, so
//             x = 30 + (wx - 30) * r / 51  ~  30 + ((wx - 30) * r * 5) >> 8
// Method  : once per frame (tick_frame) a small FSM projects the 11 objects
//           (ball + 10 pins) one after another; the only division (1530 / dz)
//           uses a shared 1-bit-per-clock divider: ~11 x 20 = 220 clocks per
//           frame. The renderers then only compare pixel positions.
// Output  : ball {visible, x, base row, radius px}; per pin {visible, x,
//           base row, size class 0..7 (pin height 2..15 px)}. Only standing
//           pins are projected (pin action is shown by the overhead camera).
//=============================================================================
(* use_dsp = "yes" *)
module persp_proj (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire signed [10:0] cam_fp,     // world y of the camera (inches)
    input  wire        ball_visible,
    input  wire [15:0] ball_x,           // POS
    input  wire [15:0] ball_y,
    input  wire [239:0] pin_vis,          // C: 10 x {x6, y10, state3, dir3, stage2}
    output reg         b_vis,
    output reg  signed [7:0] b_x,
    output reg  [5:0]  b_row,            // row of the floor contact
    output reg  [2:0]  b_rad,
    output wire [179:0] pins_fp          // 10 x {vis, x[7:0], row[5:0], cls[2:0]}
);
    localparam [15:0] K = 16'd1530;

    // one projection at a time
    reg  [3:0]  k;                        // 0 = ball, 1..10 = pins
    reg         busy, dv_go;
    reg  signed [11:0] wx, dz;
    reg  [15:0] num, den;
    wire [15:0] quo;
    wire        dv_done, dv_busy;
    div_seq #(.W(16)) u_div (.clk(clk), .rst(rst), .start(dv_go), .num(num), .den(den),
                             .quo(quo), .done(dv_done), .busy(dv_busy));

    // the object k (combinational select)
    wire [23:0] pv = pin_vis[24 * (k - 4'd1) +: 24];
    wire        pin_up = (pv[7:5] == `PS_STANDING) || (pv[7:5] == `PS_WOBBLING);
    wire signed [11:0] o_wx = (k == 0) ? $signed({2'b00, ball_x[15:6]}) : $signed({6'd0, pv[23:18]});
    wire signed [11:0] o_wy = (k == 0) ? $signed({2'b00, ball_y[15:6]}) : $signed({2'b00, pv[17:8]});
    wire        o_on = (k == 0) ? ball_visible : pin_up;

    // results of the division (registered in S_RES, timing)
    reg  [5:0]  r_q;
    wire [5:0]  r    = r_q;
    wire signed [15:0] xo = ((wx - 12'sd30) * $signed({1'b0, r, 2'b00} + {3'b000, r})) >>> 8;  // * r * 5 / 256
    wire [11:0] h75  = r * 7'd75;                     // pin height px * 256
    wire [7:0]  h    = h75[11:8];
    wire [2:0]  cls  = (h <= 2) ? 3'd0 : (h == 3) ? 3'd1 : (h == 4) ? 3'd2 : (h <= 6) ? 3'd3 :
                       (h <= 8) ? 3'd4 : (h <= 10) ? 3'd5 : (h <= 12) ? 3'd6 : 3'd7;
    wire [10:0] rad22 = r * 5'd22;                    // ball radius px * 256

    reg [17:0] pf [0:9];
    genvar g;
    generate for (g = 0; g < 10; g = g + 1) begin : g_o
        assign pins_fp[18*g +: 18] = pf[g];
    end endgenerate

    // (timing) the selected object and the division result are registered
    // before use: S_SEL latches object k, S_RES latches r, S_OUT projects
    localparam S_IDLE = 3'd0, S_DIV = 3'd1, S_WAIT = 3'd2, S_SEL = 3'd3, S_RES = 3'd4, S_OUT = 3'd5, S_MUL = 3'd6;
    reg signed [15:0] xo_q;                       // registered product (timing)
    reg [2:0] st;
    reg signed [11:0] s_wx, s_wy;
    reg               s_on;
    integer q;
    always @(posedge clk) begin
        dv_go <= 1'b0;
        if (rst) begin
            st <= S_IDLE; k <= 0; busy <= 0; wx <= 0; dz <= 0; num <= 0; den <= 1;
            s_wx <= 0; s_wy <= 0; s_on <= 0; r_q <= 0; xo_q <= 0;
            b_vis <= 0; b_x <= 0; b_row <= 0; b_rad <= 0;
            for (q = 0; q < 10; q = q + 1) pf[q] <= 18'd0;
        end else case (st)
            S_IDLE: if (tick_frame) begin k <= 4'd0; st <= S_SEL; end
            S_SEL: begin                                   // latch object k
                s_wx <= o_wx; s_wy <= o_wy - $signed({cam_fp[10], cam_fp}); s_on <= o_on;
                st <= S_DIV;
            end
            S_DIV: begin
                dz <= s_wy;
                wx <= s_wx;
                // visible only between 30 in (bottom row) and 1530 in (horizon)
                if (!s_on || s_wy < 12'sd30 || s_wy > 12'sd1530) begin
                    if (k == 0) b_vis <= 1'b0; else pf[k - 4'd1] <= 18'd0;
                    if (k == 4'd10) st <= S_IDLE; else begin k <= k + 4'd1; st <= S_SEL; end
                end else begin
                    num <= K; den <= {4'd0, s_wy};
                    dv_go <= 1'b1;
                    st <= S_WAIT;
                end
            end
            S_WAIT: if (dv_done) st <= S_RES;
            S_RES:  begin r_q <= (quo > 16'd51) ? 6'd51 : quo[5:0]; st <= S_MUL; end
            S_MUL:  begin xo_q <= xo; st <= S_OUT; end
            S_OUT:  begin
                if (k == 0) begin
                    b_vis <= 1'b1; b_x <= 8'sd30 + xo_q[7:0]; b_row <= 6'd12 + r;
                    b_rad <= (rad22[10:8] == 0) ? 3'd1 : rad22[10:8];
                end else
                    pf[k - 4'd1] <= {1'b1, 8'sd30 + xo_q[7:0], 6'd12 + r, cls};
                if (k == 4'd10) st <= S_IDLE;
                else begin k <= k + 4'd1; st <= S_SEL; end
            end
            default: st <= S_IDLE;
        endcase
    end
endmodule
