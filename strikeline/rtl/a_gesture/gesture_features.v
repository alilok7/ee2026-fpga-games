`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// gesture_features.v : turn a recorded swipe into a throw
//-----------------------------------------------------------------------------
// Owner   : Student A
// Purpose : Runs once per release, walking the ring buffer with ONE
//           multiplier and ONE divider (about 900 clocks = 9 us in total).
//   TRIM   (v3) the swipe is first cut to the part where the hand really
//          moves: the first and the last filtered step with |dx|+|df| >= 3
//          counts. Tremor while holding the button, and the pause before
//          letting go, no longer change speed, aim or spin.
//   SPEED  peak forward motion over 16 samples (80 ms) during the last
//          ~120 ms of the (trimmed) swipe. Peak instead of "last 80 ms"
//          because people often slow down a moment before letting go.
//          index = motion >> 3 (0..63) -> speed ROM -> ball speed + mph.
//   AIM    whole-swipe ratio r = |dx| * 256 / forward (divider).
//          A dead zone of r < 26 (about 6 degrees) counts as straight, and
//          vx = vy * (r - 26) / 8192, so a 45-degree swipe gives only a
//          1.6-degree launch: wobbly human swipes still go straight.
//   SPIN   (v3) curvature of the WHOLE stroke, not of its two ends:
//          S = sum over the path of cross(p(j-1), p(j)), p = f - f(start),
//          is twice the signed area between the path and its chord L.
//          For an arc that turns by t radians, area = L^2 * t / 12, so
//              t = 6 * S / L^2      (turn256 = 1536 * S / L^2)
//          Noisy first / last steps hardly change the area, so the same
//          curve always gives the same spin. S > 0 means the swipe curved
//          LEFT, and the ball then hooks left (what you draw is what you get).
//          spin = (turn256 - 8) scaled by the spin-sensitivity setting
//          (NORMAL /4, HIGH /2, MAX /1, SOFT /8), clamped to 31: 31 levels,
//          a 1.8-degree dead zone.
//   CHECK  forward <= 0 or sideways > forward -> "SWIPE FORWARD";
//          forward < 32 counts or speed index < 4 -> "SWIPE FASTER".
// Fixed point: ring values are mouse counts (16-bit signed).
//=============================================================================
module gesture_features (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,            // swipe_done
    input  wire [6:0]  wp,
    input  wire [7:0]  n_samples,
    input  wire [15:0] stance_x,
    input  wire [1:0]  spin_sens,        // settings[SET_SPIN]: 0 normal 1 high 2 max 3 soft
    output reg  [6:0]  rd_addr,
    input  wire [63:0] rd_data,
    output wire        busy,
    output reg         throw_valid,
    output reg  signed [15:0] throw_vy,
    output reg  signed [15:0] throw_vx,
    output reg  signed [`SPIN_W-1:0] throw_spin,
    output reg  [15:0] throw_x0,
    output reg  [7:0]  throw_mph10,
    output reg         reject,           // 1-cycle with reject_msg
    output reg  [1:0]  reject_msg,
    output reg  [2:0]  aim_level,        // 0..7 for the labels
    output reg         aim_right
);
    localparam [16:0] TRIM_TH = 17'd3;   // |dx|+|df| per 5 ms sample that counts as moving (~6 cm/s)

    // ---------------- shared multiplier and divider -------------------------
    reg  signed [24:0] ma;
    reg  signed [17:0] mb;
    wire signed [42:0] mp;
    mul_s25x18 u_mul (.clk(clk), .a(ma), .b(mb), .p(mp));

    reg         dv_start;
    reg  [39:0] dv_num, dv_den;
    wire [39:0] dv_quo;
    wire        dv_done, dv_busy;
    div_seq #(.W(40)) u_div (.clk(clk), .rst(rst), .start(dv_start), .num(dv_num),
        .den(dv_den), .quo(dv_quo), .done(dv_done), .busy(dv_busy));

    // speed ROM: {vy Q3.12, mph x 10}
    reg [23:0] speed_rom [0:63];
    initial $readmemh("speed_curve.mem", speed_rom);

    // ring fields of the entry being read
    wire signed [15:0] r_fx = rd_data[31:16];
    wire signed [15:0] r_ff = rd_data[15:0];

    // ---------------- state register ----------------------------------------
    localparam S_IDLE = 5'd0,  S_FIRST = 5'd1, S_LAST = 5'd2, S_PK_A = 5'd3, S_PK_B = 5'd4,
               S_SP0 = 5'd5,   S_SP_RD = 5'd6, S_M1 = 5'd7,   S_M2 = 5'd8,  S_M3 = 5'd9,
               S_M4 = 5'd10,   S_PRE = 5'd11,  S_CHECK = 5'd12, S_AIM_W = 5'd13, S_AIM_M = 5'd14,
               S_AIM_X = 5'd15, S_AIM_P = 5'd16, S_L1 = 5'd17,  S_L2 = 5'd18, S_SPN_P = 5'd19,
               S_SPN_W = 5'd20, S_OUT = 5'd21, S_TR0 = 5'd22, S_TR1 = 5'd23, S_TR2 = 5'd24, S_TR1B = 5'd25, S_TR1C = 5'd26;
    reg [4:0] st;
    assign busy = (st != S_IDLE);

    reg [6:0]  base;                    // oldest sample slot
    reg [7:0]  n, j, jmin, js, je;
    reg        found;
    reg signed [15:0] fx0, ff0, fxn, ffn, tmp_f;
    reg signed [16:0] peak;
    reg signed [15:0] f1x, f1f;             // trim pass: f(j-1)
    reg signed [16:0] p1x, p1f, p2x, p2f;   // area pass: p(j-1), p(j)
    reg signed [39:0] csum;                 // 2 x signed area
    reg [39:0] l2;                          // chord length ^2
    reg [5:0]  sidx;
    reg [8:0]  r_eff;
    reg [15:0] vy_mag;

    reg  signed [16:0] dxs_q, dfs_q;
    reg  [16:0] adx_q;
    wire signed [16:0] dxs = fxn - fx0;
    wire signed [16:0] dfs = ffn - ff0;
    wire [16:0] adx = dxs[16] ? -dxs : dxs;
    wire signed [16:0] pk_d = tmp_f - r_ff;
    // trim pass: size of one filtered step
    reg  signed [15:0] t_x, t_f;
    reg         t_mv;
    wire signed [16:0] tdx = t_x - f1x;
    wire signed [16:0] tdf = t_f - f1f;
    wire [16:0] tstep = (tdx[16] ? -tdx : tdx) + (tdf[16] ? -tdf : tdf);
    // spin: |S| (clamped to 28 bits) * 1536 = |S| * 1024 + |S| * 512
    wire [39:0] acs   = csum[39] ? -csum : csum;
    wire [27:0] acs_c = (acs > 40'h000FFFFFFF) ? 28'hFFFFFFF : acs[27:0];
    wire [39:0] spin_num = {2'b00, acs_c, 10'd0} + {3'b000, acs_c, 9'd0};
    // turn (rad * 256) -> spin magnitude
    wire [39:0] t_raw = (dv_quo > 40'd8) ? dv_quo - 40'd8 : 40'd0;
    wire [39:0] t_scl = (spin_sens == 2'd1) ? (t_raw >> 1) :
                        (spin_sens == 2'd2) ?  t_raw       :
                        (spin_sens == 2'd3) ? (t_raw >> 3) : (t_raw >> 2);
    wire [4:0]  s_mag = (t_scl > 40'd31) ? 5'd31 : t_scl[4:0];

    always @(posedge clk) begin
        throw_valid <= 1'b0; reject <= 1'b0; dv_start <= 1'b0;
        if (rst) begin
            st <= S_IDLE; rd_addr <= 0; ma <= 0; mb <= 0;
            throw_vy <= 0; throw_vx <= 0; throw_spin <= 0; throw_x0 <= `W_LANE_CX;
            throw_mph10 <= 0; reject_msg <= 0; aim_level <= 0; aim_right <= 0;
            base <= 0; n <= 0; j <= 0; jmin <= 0; js <= 0; je <= 0; found <= 0;
            fx0 <= 0; ff0 <= 0; fxn <= 0; ffn <= 0;
            tmp_f <= 0; peak <= 0; f1x <= 0; f1f <= 0;
            p1x <= 0; p1f <= 0; p2x <= 0; p2f <= 0; csum <= 0; l2 <= 0;
            sidx <= 0; r_eff <= 0; vy_mag <= 0; dv_num <= 0; dv_den <= 0;
            dxs_q <= 0; dfs_q <= 0; adx_q <= 0;
        end else begin
            case (st)
                S_IDLE: if (start) begin
                    base    <= wp - n_samples[6:0];   // 64 samples: wraps to wp
                    n       <= n_samples;
                    rd_addr <= wp - n_samples[6:0];
                    throw_x0 <= stance_x;
                    st <= S_TR0;
                end
                // ---- trim: first / last sample where the hand moves -------
                S_TR0: begin
                    f1x <= r_fx; f1f <= r_ff;
                    j <= 8'd1; found <= 1'b0; js <= 8'd1; je <= 8'd1;
                    rd_addr <= base + 7'd1;
                    st <= S_TR1;
                end
                S_TR1: begin                           // ring read registered first (timing)
                    t_x <= r_fx; t_f <= r_ff;
                    st <= S_TR1B;
                end
                S_TR1B: begin                          // step size, registered (timing)
                    t_mv <= (tstep >= TRIM_TH);
                    f1x <= t_x; f1f <= t_f;
                    st  <= S_TR1C;
                end
                S_TR1C: begin
                    st  <= S_TR1;
                    if (t_mv) begin
                        if (!found) js <= j;
                        found <= 1'b1;
                        je <= j;
                    end
                    if (j == n - 8'd1) st <= S_TR2;
                    else begin
                        j <= j + 8'd1;
                        rd_addr <= base + j[6:0] + 7'd1;
                    end
                end
                S_TR2: begin
                    if (!found) begin                  // the hand never moved
                        reject <= 1'b1; reject_msg <= `GM_FASTER; st <= S_IDLE;
                    end else begin
                        // keep sample js-1 (last still point) .. je (last move)
                        base    <= base + js[6:0] - 7'd1;
                        n       <= je - js + 8'd2;
                        rd_addr <= base + js[6:0] - 7'd1;
                        st <= S_FIRST;
                    end
                end
                S_FIRST: begin                         // oldest sample
                    fx0 <= r_fx; ff0 <= r_ff;
                    rd_addr <= base + n[6:0] - 7'd1;
                    st <= S_LAST;
                end
                S_LAST: begin                          // newest sample
                    fxn <= r_fx; ffn <= r_ff;
                    peak <= 17'sd0;
                    j    <= n - 8'd1;
                    jmin <= (n < 8'd17) ? 8'd16 : (n > 8'd41) ? n - 8'd25 : 8'd16;
                    if (n < 8'd17) begin               // short swipe: whole motion
                        peak <= r_ff - ff0;
                        rd_addr <= base + 7'd1;
                        st <= S_SP0;
                    end else begin
                        rd_addr <= base + n[6:0] - 7'd1;
                        st <= S_PK_A;
                    end
                end
                // ---- peak speed: max over j of f(j) - f(j-16) -------------
                S_PK_A: begin
                    tmp_f <= r_ff;
                    rd_addr <= base + j[6:0] - 7'd16;
                    st <= S_PK_B;
                end
                S_PK_B: begin
                    if (pk_d > peak) peak <= pk_d;
                    if (j == jmin) begin
                        rd_addr <= base + 7'd1;
                        st <= S_SP0;
                    end else begin
                        j <= j - 8'd1;
                        rd_addr <= base + j[6:0] - 7'd1;
                        st <= S_PK_A;
                    end
                end
                // ---- spin: signed area between the path and its chord ------
                S_SP0: begin                               // p(0) = 0
                    p1x <= 0; p1f <= 0; csum <= 0;
                    j <= 8'd1;                             // rd_addr = base + 1 already
                    st <= S_SP_RD;
                end
                S_SP_RD: begin                             // p(j) = f(j) - f(0)
                    p2x <= r_fx - fx0; p2f <= r_ff - ff0;
                    st <= S_M1;
                end
                S_M1: begin ma <= p1x; mb <= p2f; st <= S_M2; end
                S_M2: begin ma <= p1f; mb <= p2x; st <= S_M3; end
                S_M3: begin csum <= csum + mp[39:0]; st <= S_M4; end          // p1x * p2f
                S_M4: begin                                                  // p1f * p2x
                    csum <= csum - mp[39:0];
                    p1x  <= p2x; p1f <= p2f;
                    j    <= j + 7'd1;
                    rd_addr <= base + j[6:0] + 7'd1;
                    st <= (j == n - 8'd1) ? S_PRE : S_SP_RD;
                end
                // ---- validation + speed ROM ---------------------------------
                S_PRE: begin                            // swipe totals, registered (timing)
                    dxs_q <= dxs; dfs_q <= dfs; adx_q <= adx;
                    st <= S_CHECK;
                end
                S_CHECK: begin
                    sidx <= (peak > 17'sd511) ? 6'd63 : peak[8:3];
                    if (dfs_q <= 0 || adx_q > dfs_q) begin
                        reject <= 1'b1; reject_msg <= `GM_FORWARD; st <= S_IDLE;
                    end else if (dfs_q < 17'sd32 || peak < 17'sd32) begin
                        reject <= 1'b1; reject_msg <= `GM_FASTER;  st <= S_IDLE;
                    end else begin
                        dv_num <= {16'd0, adx_q[15:0], 8'd0};   // |dx| * 256
                        dv_den <= {24'd0, dfs_q[15:0]};
                        dv_start <= 1'b1;
                        st <= S_AIM_W;
                    end
                end
                S_AIM_W: begin
                    vy_mag      <= speed_rom[sidx][23:8];
                    throw_mph10 <= speed_rom[sidx][7:0];
                    if (dv_done) begin
                        r_eff <= (dv_quo > 40'd256) ? 9'd230 :
                                 (dv_quo > 40'd26)  ? dv_quo[8:0] - 9'd26 : 9'd0;
                        st <= S_AIM_M;
                    end
                end
                S_AIM_M: begin ma <= {9'd0, vy_mag}; mb <= {9'd0, r_eff}; st <= S_AIM_X; end
                S_AIM_X: begin ma <= dxs_q; mb <= dxs_q; st <= S_AIM_P; end   // next: dx^2
                S_AIM_P: begin                          // vx = vy * r_eff >> 13
                    throw_vx  <= dxs_q[16] ? -$signed(mp[28:13]) : $signed(mp[28:13]);
                    aim_level <= (r_eff[8:5] > 4'd7) ? 3'd7 : r_eff[7:5];
                    aim_right <= ~dxs_q[16] && (r_eff != 0);
                    ma <= dfs_q; mb <= dfs_q;           // next: df^2
                    st <= S_L1;
                end
                S_L1: begin l2 <= {5'd0, mp[34:0]}; st <= S_L2; end          // dx^2
                S_L2: begin l2 <= l2 + {5'd0, mp[34:0]}; st <= S_SPN_P; end  // + df^2
                S_SPN_P: begin
                    dv_num   <= spin_num;               // 1536 * |S|
                    dv_den   <= (l2 == 0) ? 40'd1 : l2;
                    dv_start <= 1'b1;
                    st <= S_SPN_W;
                end
                S_SPN_W: if (dv_done) begin
                    st <= S_OUT;
                    throw_spin <= csum[39] ? -$signed({1'b0, s_mag}) : $signed({1'b0, s_mag});
                end
                S_OUT: begin
                    throw_vy    <= vy_mag;
                    throw_valid <= 1'b1;
                    st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
