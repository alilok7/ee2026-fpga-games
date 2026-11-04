`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// gesture_features.v : turn a recorded swipe into a throw
//-----------------------------------------------------------------------------
// Owner   : Student A
// Purpose : Runs once per release, walking the ring buffer with ONE
//           multiplier and ONE divider (about 600 clocks = 6 us in total).
//   SPEED  peak forward motion over 16 samples (80 ms) during the last
//          ~120 ms of the swipe. Peak instead of "last 80 ms" because
//          people often stop the mouse a moment before letting go.
//          index = motion >> 3 (0..63) -> speed ROM -> ball speed + mph.
//   AIM    whole-swipe ratio r = |dx| * 256 / forward (divider).
//          A dead zone of r < 26 (about 6 degrees) counts as straight, and
//          vx = vy * (r - 26) / 8192, so a 45-degree swipe gives only a
//          1.6-degree launch: wobbly human swipes still go straight.
//   SPIN   curvature = signed sum of cross products of successive velocity
//          vectors  C = sum(v1.x*v2.y - v1.y*v2.x). For a constant speed |v|
//          and a turn of t radians per step, each term is |v|^2 * sin(t),
//          so dividing by the mean |v|^2 (E / N) gives the total turn in
//          radians: turn = C * N / E (scaled by 256), N = moving steps. C > 0 means the swipe
//          curved LEFT, and the ball then hooks left (what you draw is what
//          you get). |turn| < 0.125 rad is a straight swipe, then one spin
//          level per 0.0625 rad, up to 7.
//   CHECK  forward <= 0 or sideways > forward -> "SWIPE FORWARD";
//          forward < 32 counts or speed index < 4 -> "SWIPE FASTER".
// Fixed point: ring values are mouse counts (16-bit signed).
//=============================================================================
module gesture_features (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,            // swipe_done
    input  wire [5:0]  wp,
    input  wire [6:0]  n_samples,
    input  wire [15:0] stance_x,
    output reg  [5:0]  rd_addr,
    input  wire [63:0] rd_data,
    output wire        busy,
    output reg         throw_valid,
    output reg  signed [15:0] throw_vy,
    output reg  signed [15:0] throw_vx,
    output reg  signed [3:0]  throw_spin,
    output reg  [15:0] throw_x0,
    output reg  [7:0]  throw_mph10,
    output reg         reject,           // 1-cycle with reject_msg
    output reg  [1:0]  reject_msg,
    output reg  [2:0]  aim_level,        // 0..7 for the labels
    output reg         aim_right
);
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
               S_SP0 = 5'd5,   S_SP_CHK = 5'd6,   S_SP_RD = 5'd7, S_M1 = 5'd8,  S_M2 = 5'd9,
               S_M3 = 5'd10,   S_M4 = 5'd11,   S_M5 = 5'd12,  S_CHECK = 5'd13, S_M6 = 5'd22, S_AIM_X = 5'd23, S_PRE = 5'd24,
               S_AIM_D = 5'd14, S_AIM_W = 5'd15, S_AIM_M = 5'd16, S_AIM_P = 5'd17,
               S_SPN_P = 5'd19, S_SPN_W = 5'd20, S_OUT = 5'd21;
    reg [4:0] st;
    assign busy = (st != S_IDLE);

    reg [5:0]  base;                    // oldest sample slot
    reg [6:0]  n, j, jmin, m;           // m = number of non-zero velocity steps
    reg signed [15:0] fx0, ff0, fxn, ffn, tmp_f;
    reg signed [16:0] peak;
    reg signed [15:0] f1x, f1f;             // f(j-1)
    reg signed [16:0] v1x, v1f, v2x, v2f;
    reg signed [31:0] csum, esum;
    reg [5:0]  sidx;
    reg [8:0]  r_eff;
    reg [15:0] vy_mag;

    reg  signed [16:0] dxs_q, dfs_q;
    reg  [16:0] adx_q;
    wire signed [16:0] dxs = fxn - fx0;
    wire signed [16:0] dfs = ffn - ff0;
    wire [16:0] adx = dxs[16] ? -dxs : dxs;
    wire [31:0] acsum = csum[31] ? -csum : csum;
    wire [23:0] acs_c = (acsum > 32'h00FF_FFFF) ? 24'hFF_FFFF : acsum[23:0];
    wire signed [16:0] pk_d = tmp_f - r_ff;
    // spin levels 1..6 for 32 <= turn < 128: ((turn - 32) >> 4) + 1
    wire [6:0] turn_m32 = dv_quo[6:0] - 7'd32;
    wire [2:0] spin_mid = turn_m32[6:4] + 3'd1;

    always @(posedge clk) begin
        throw_valid <= 1'b0; reject <= 1'b0; dv_start <= 1'b0;
        if (rst) begin
            st <= S_IDLE; rd_addr <= 0; ma <= 0; mb <= 0;
            throw_vy <= 0; throw_vx <= 0; throw_spin <= 0; throw_x0 <= `W_LANE_CX;
            throw_mph10 <= 0; reject_msg <= 0; aim_level <= 0; aim_right <= 0;
            base <= 0; n <= 0; j <= 0; jmin <= 0; fx0 <= 0; ff0 <= 0; fxn <= 0; ffn <= 0;
            tmp_f <= 0; peak <= 0; f1x <= 0; f1f <= 0; m <= 0;
            v1x <= 0; v1f <= 0; v2x <= 0; v2f <= 0; csum <= 0; esum <= 0;
            sidx <= 0; r_eff <= 0; vy_mag <= 0; dv_num <= 0; dv_den <= 0;
        end else begin
            case (st)
                S_IDLE: if (start) begin
                    base    <= wp - n_samples[5:0];   // 64 samples: wraps to wp
                    n       <= n_samples;
                    rd_addr <= wp - n_samples[5:0];
                    throw_x0 <= stance_x;
                    st <= S_FIRST;
                end
                S_FIRST: begin                         // oldest sample
                    fx0 <= r_fx; ff0 <= r_ff;
                    rd_addr <= base + n[5:0] - 6'd1;
                    st <= S_LAST;
                end
                S_LAST: begin                          // newest sample
                    fxn <= r_fx; ffn <= r_ff;
                    peak <= 17'sd0;
                    j    <= n - 7'd1;
                    jmin <= (n < 7'd17) ? 7'd16 : (n > 7'd41) ? n - 7'd25 : 7'd16;
                    if (n < 7'd17) begin               // short swipe: whole motion
                        peak <= r_ff - ff0;
                        rd_addr <= base;
                        st <= S_SP0;
                    end else begin
                        rd_addr <= base + n[5:0] - 6'd1;
                        st <= S_PK_A;
                    end
                end
                // ---- peak speed: max over j of f(j) - f(j-16) -------------
                S_PK_A: begin
                    tmp_f <= r_ff;
                    rd_addr <= base + j[5:0] - 6'd16;
                    st <= S_PK_B;
                end
                S_PK_B: begin
                    if (pk_d > peak) peak <= pk_d;
                    if (j == jmin) begin
                        rd_addr <= base;
                        st <= S_SP0;
                    end else begin
                        j <= j - 7'd1;
                        rd_addr <= base + j[5:0] - 6'd1;
                        st <= S_PK_A;
                    end
                end
                // ---- spin: cross products of successive velocities --------
                S_SP0: begin                               // f(0)
                    f1x <= r_fx; f1f <= r_ff;
                    v1x <= 0; v1f <= 0;                    // no previous velocity yet
                    csum <= 0; esum <= 0; m <= 0;
                    j <= 7'd1;
                    rd_addr <= base + 6'd1;
                    st <= (n < 7'd3) ? S_PRE : S_SP_RD;
                end
                S_SP_RD: begin                             // v2 = f(j) - f(j-1)
                    v2x <= r_fx - f1x; v2f <= r_ff - f1f;
                    f1x <= r_fx; f1f <= r_ff;
                    st <= S_SP_CHK;
                end
                S_SP_CHK: begin
                    // MouseCtl reports every 25 ms, so 1 sample in 5 does not
                    // move. A zero vector would break the chain of turns (and
                    // leave the rounding of the filter un-cancelled), so it is
                    // skipped: the cross product is always taken against the
                    // last NON-ZERO velocity (v1).
                    if (v2x == 0 && v2f == 0) begin
                        j <= j + 7'd1;
                        rd_addr <= base + j[5:0] + 6'd1;
                        st <= (j == n - 7'd1) ? S_PRE : S_SP_RD;
                    end else begin
                        m  <= m + 7'd1;
                        st <= S_M1;
                    end
                end
                S_M1: begin ma <= v1x; mb <= v2f; st <= S_M2; end
                S_M2: begin ma <= v1f; mb <= v2x; st <= S_M3; end
                S_M3: begin csum <= csum + mp[31:0]; ma <= v2x; mb <= v2x; st <= S_M4; end
                S_M4: begin csum <= csum - mp[31:0]; ma <= v2f; mb <= v2f; st <= S_M5; end
                S_M5: begin esum <= esum + mp[31:0]; st <= S_M6; end      // v2x^2
                S_M6: begin                                               // v2f^2
                    esum <= esum + mp[31:0];
                    v1x  <= v2x; v1f <= v2f;                              // last non-zero
                    j    <= j + 7'd1;
                    rd_addr <= base + j[5:0] + 6'd1;
                    st <= (j == n - 7'd1) ? S_PRE : S_SP_RD;
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
                S_AIM_X: begin                          // DSP is multiplying
                    ma <= {1'b0, acs_c};                // next: |C| * number of terms
                    mb <= {11'd0, m};
                    st <= S_AIM_P;
                end
                S_AIM_P: begin                          // vx = vy * r_eff >> 13
                    throw_vx  <= dxs_q[16] ? -$signed(mp[28:13]) : $signed(mp[28:13]);
                    aim_level <= (r_eff[8:5] > 4'd7) ? 3'd7 : r_eff[7:5];
                    aim_right <= ~dxs_q[16] && (r_eff != 0);
                    st <= S_SPN_P;
                end
                S_SPN_P: begin                          // |C| * N is ready now
                    dv_num   <= {mp[31:0], 8'd0};       // * 256
                    dv_den   <= (esum == 0) ? 40'd1 : {8'd0, esum};
                    dv_start <= 1'b1;
                    st <= S_SPN_W;
                end
                S_SPN_W: if (dv_done) begin
                    st <= S_OUT;
                    // |turn| (rad * 256): < 32 straight, then 1 level per 16, max 7
                    if (esum == 0 || dv_quo < 40'd32) throw_spin <= 4'sd0;
                    else if (dv_quo >= 40'd128)        throw_spin <= csum[31] ? -4'sd7 : 4'sd7;
                    else throw_spin <= csum[31] ? -$signed({1'b0, spin_mid}) : $signed({1'b0, spin_mid});
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
