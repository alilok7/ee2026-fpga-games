`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// ball_physics.v : skid -> hook -> roll, gutter, ball -> pin collisions
//-----------------------------------------------------------------------------
// Owner   : Student B
// Fixed point (internal): x, y unsigned Q10.20 inches (30 bit)
//                         vx, vy signed, 1 LSB = 2^-20 in/tick (24 bit)
//           Exported as POS Q10.6 (= x[29:14]) and VEL Q3.12 (= v[23:8]).
// Per physics tick (1024 Hz, ~97 600 clocks) one FSM pass does:
//   FRICTION (v3, slip model). At release the spin becomes a store of side
//     slip REV = spin * rev_k (2^-20 in/tick, the sideways speed the ball's
//     side rotation "wants"). Every tick the lane takes at most mu out of it:
//         a = min(mu(x, y), |REV|),  REV -= a,  vx -= a  (REV > 0 hooks LEFT)
//     mu comes from an OIL PATTERN ROM (oil_pattern.mem, by 16 in of length
//     and 4 in of distance from the centre): ~0 in the oil, rising through a
//     transition zone, high on the dry back end; the oil is shorter on the
//     outside boards. So the ball skids, reads the lane where the oil thins,
//     hooks hardest on the dry wood and ROLLS once its slip is used up - the
//     "breakpoint" comes out of the physics, and a faster ball (fewer ticks in
//     the oil) hooks later. Magnitudes only, so +spin and -spin are exact
//     mirror images (v2 used a floor shift: left hooks were ~1 LSB stronger).
//     vy -= dec (oil / dry) + a/2 (friction turns forward speed into hook).
//   STEER (v3) for 0.5 s after release, sideways mouse motion (A's steer_dx)
//     nudges vx, with a total budget of +-STEER_MAX ("body English").
//   GUTTER if the ball centre passes a lane edge before the deck.
//   PIT   at y = 760 in. vy never drops below 3 mph on the lane (1 mph on
//         the deck), so every ball reaches the pit.
//   SCAN 10 pins (read port from C), forward on even ticks and backward on
//     odd ticks, so neither side of the rack is always resolved first.
//     overlap test |d|^2 < (Rb+Rp)^2 with SQUARES -> no square root.
//     normal n = d * inv_len[|d|^2] (ROM, Q1.14).
//     v_rel_n = (v_ball - v_pin) . n   (> 0 means they are approaching)
//     pin  dv = +kp * v_rel_n * n,  kp = (1+e) mb / (mb + mp)   (ROM)
//     ball dv = -kb * v_rel_n * n,  kb = (1+e) mp / (mb + mp)   (momentum kept)
//     + (v3) a TANGENTIAL friction kick on the pin, |spin| * 6/4096 of the
//       normal one, along t = (-ny, nx) signed by the spin: a hook ball drags
//       the pins it hits toward its hook side ("mixing").
//     An UPRIGHT pin gets one impulse per contact (flag clears 0.2 in out);
//     a lying pin gets one every tick the ball still drives into it.
//   scan_done then tells C to run its own pin update.
// Multiplier use: 2 per near pin + 15 per hit (the hook needs none now).
// Cycle budget: worst case 10 hits = ~300 clocks of 97 656 (0.3 %).
//=============================================================================
module ball_physics #(
    parameter [15:0] R_DOWN = 16'd224             // lying-pin footprint (same as C), 1/64 in (3.5 in)
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_phys,
    input  wire [`GS_W-1:0]  game_state,
    input  wire [`SET_W-1:0] settings,
    input  wire [15:0] stance_x,
    input  wire        throw_valid,
    input  wire signed [15:0] throw_vy,
    input  wire signed [15:0] throw_vx,
    input  wire signed [`SPIN_W-1:0] throw_spin,
    input  wire [15:0] throw_x0,
    input  wire        steer_valid,      // v3: A, a mouse packet while rolling
    input  wire signed [11:0] steer_dx,
    // pin read port (combinational in C)
    output reg  [3:0]  pin_rd_idx,
    input  wire [15:0] pin_rd_x,
    input  wire [15:0] pin_rd_y,
    input  wire signed [15:0] pin_rd_vx,
    input  wire signed [15:0] pin_rd_vy,
    input  wire        pin_rd_solid,
    input  wire        pin_rd_upright,   // standing or wobbling (else lying: bigger footprint)
    // impulse to C
    output reg         impulse_valid,
    output reg  [3:0]  impulse_pin,
    output reg  signed [15:0] impulse_vx,
    output reg  signed [15:0] impulse_vy,
    output reg         scan_done,
    // ball state
    output wire [15:0] ball_x,
    output wire [15:0] ball_y,
    output wire signed [15:0] ball_vx,
    output wire signed [15:0] ball_vy,
    output reg  [`BP_W-1:0] ball_phase,
    output reg  signed [`SPIN_W-1:0] ball_spin,
    output wire [7:0]  ball_rev,         // v3: remaining slip, 0..255 (for the rev meter)
    output reg  [15:0] ball_angle,       // finger-hole marker, [15:10] used
    output reg         contact_pulse,    // a pin was hit (debug overlay, D)
    output reg  [15:0] contact_px,
    output reg  [15:0] contact_py
);
    // contact distance: ball 4.3 in + standing pin 2.4 in = 6.7 in, or
    // + lying pin R_DOWN (the same footprint C uses pin to pin) = 7.8 in
    localparam [35:0] R2_HIT_UP = 36'd183869;      // (6.7 in * 64)^2
    localparam [35:0] R2_CLR_UP = 36'd201601;      // (6.9 in * 64)^2
    localparam [35:0] R2_HIT_DN = (R_DOWN + 36'd275) * (R_DOWN + 36'd275);   // (4.3 in + R)^2
    localparam [35:0] R2_CLR_DN = (R_DOWN + 36'd288) * (R_DOWN + 36'd288);   // + 0.2 in
    localparam [16:0] NEAR_UP   = 17'd448;         // 7 in: quick reject box
    localparam [16:0] NEAR_DN   = R_DOWN + 17'd320;           // 4.3 in + R + 0.7 in
    localparam [7:0]  MU_DRY_TH = 8'd16;           // mu above this = the ball is "reading" dry wood
    localparam signed [23:0] STEER_MAX = 24'sd1536; // total steer budget (2^-20 in/tick): <= ~3.5 boards
    localparam [17:0] KT_PER_SPIN = 18'd6;         // tangential kick per spin level, Q12 (31 -> 4.5 %)

    // ---------------- ROMs ---------------------------------------------------
    reg [63:0] prm_rom [0:7];
    reg [8:0]  inv_rom [0:127];                    // 2^14 / |d|, indexed by d^2 >> 12
    reg [7:0]  oil_rom [0:1023];                   // mu, {long, y/16 in, |x-30|/4 in}
    initial begin
        $readmemh("ball_params.mem", prm_rom);
        $readmemh("inv_len.mem", inv_rom);
        $readmemh("oil_pattern.mem", oil_rom);
    end
    wire [63:0] prm      = prm_rom[{settings[`SET_OIL], settings[`SET_LB_HI:`SET_LB_LO]}];
    wire [7:0]  dec_oil  = prm[63:56];
    wire [7:0]  dec_dry  = prm[55:48];
    wire [15:0] rev_k    = prm[47:32];
    wire [17:0] kp       = {2'b00, prm[31:16]};
    wire [17:0] kb       = {2'b00, prm[15:0]};

    // ---------------- state -------------------------------------------------
    reg [29:0] x, y;
    reg signed [23:0] vx, vy;
    reg [23:0] rev;                                // |slip| left (2^-20 in/tick)
    reg        rev_left;                           // slip pushes left (spin > 0)
    reg [10:0] roll_ticks;                         // ticks since release (saturates)
    reg signed [23:0] steer_q, steer_used;         // nudge waiting for the next tick, total so far
    reg [9:0]  touching;                           // per-pin contact flags (upright pins)
    reg        scan_rev;                           // this tick scans 9 -> 0
    assign ball_x  = x[29:14];
    assign ball_y  = y[29:14];
    assign ball_vx = vx[23:8];
    assign ball_vy = vy[23:8];
    assign ball_rev = (rev[23:8] > 16'd255) ? 8'd255 : rev[15:8];

    // ---------------- oil pattern read (block RAM, 1 clock) ------------------
    wire [9:0]  y_in = ball_y[15:6];
    wire signed [10:0] xc = $signed({1'b0, ball_x[15:6]}) - 11'sd30;
    wire [10:0] axc = xc[10] ? -xc : xc;
    wire [2:0]  xb  = (axc[10:2] > 9'd7) ? 3'd7 : axc[4:2];
    wire [9:0]  oil_addr = {settings[`SET_OIL], (y_in[9:4] > 6'd47) ? 6'd47 : y_in[9:4], xb};
    reg  [7:0]  mu_q;
    always @(posedge clk) mu_q <= oil_rom[oil_addr];

    // ---------------- shared multiplier -------------------------------------
    reg  signed [24:0] ma;
    reg  signed [17:0] mb;
    wire signed [42:0] mp;
    mul_s25x18 u_mul (.clk(clk), .a(ma), .b(mb), .p(mp));

    // arithmetic shift that rounds toward ZERO (mirror-symmetric, v3)
    function signed [42:0] sra0;
        input signed [42:0] v; input [4:0] s;
        sra0 = v[42] ? -((-v) >>> s) : (v >>> s);
    endfunction

    // ---------------- datapath registers for one pin -----------------------
    reg signed [16:0] dx, dy, relx, rely;
    reg [35:0]        d2;
    reg signed [17:0] nx, ny;
    reg signed [42:0] t;
    reg signed [24:0] vrn, sp, sb, tq;
    reg signed [15:0] dpx, dpy, tdx;
    reg signed [23:0] dbx;

    // C's read port is latched in S_P0 (timing: index -> C's mux -> here)
    reg [15:0] prx, pry;
    reg signed [15:0] prvx, prvy;
    reg        prs, far_q, prup;
    reg [17:0] inv_q;
    reg [17:0] kt;                                 // tangential kick, Q12 (set at the throw)
    wire [35:0] r2_hit = prup ? R2_HIT_UP : R2_HIT_DN;
    wire [35:0] r2_clr = prup ? R2_CLR_UP : R2_CLR_DN;
    wire [16:0] near   = prup ? NEAR_UP   : NEAR_DN;
    reg signed [16:0] pdx_q, pdy_q;
    wire signed [16:0] pdx = $signed({1'b0, prx}) - $signed({1'b0, ball_x});
    wire signed [16:0] pdy = $signed({1'b0, pry}) - $signed({1'b0, ball_y});
    wire [16:0] adx = pdx[16] ? -pdx : pdx;
    wire [16:0] ady = pdy[16] ? -pdy : pdy;
    wire [35:0] d2_full = d2 + mp[35:0];
    wire signed [42:0] vrn_full = sra0(t + mp, 5'd14);

    wire rolling = (ball_phase == `BP_SKID) || (ball_phase == `BP_HOOK) || (ball_phase == `BP_ROLL);

    // ---------------- integration results (combinational) -------------------
    wire signed [31:0] nxp = $signed({2'b00, x}) + vx;
    wire signed [31:0] nyp = $signed({2'b00, y}) + vy;
    wire [15:0] nx16 = nxp[29:14];
    // slip friction this tick
    // (timing) the friction of this tick is worked out in S_HW and registered
    wire [23:0] hook_c  = (rev < {16'd0, mu_q}) ? rev : {16'd0, mu_q};
    reg  [23:0] hook_a;
    reg         in_oil;
    wire signed [23:0] vy_dec  = vy - $signed({16'd0, in_oil ? dec_oil : dec_dry})
                                    - $signed({1'b0, hook_a[23:1]});
    wire [`SPIN_W-2:0] spin_abs = throw_spin[`SPIN_W-1] ? -throw_spin[`SPIN_W-2:0] : throw_spin[`SPIN_W-2:0];
    wire signed [23:0] vy_min  = (ball_y >= `W_DECK_Y) ? $signed({`W_SPEED_MIN_DECK, 8'd0})
                                                       : $signed({`W_SPEED_MIN, 8'd0});
    wire signed [23:0] vy_next = (vy_dec < vy_min) ? vy_min : vy_dec;
    // steer: clamp each packet to +-64 counts, 8 LSB per count, budget STEER_MAX
    wire signed [11:0] sdx_c = (steer_dx > 12'sd64) ? 12'sd64 : (steer_dx < -12'sd64) ? -12'sd64 : steer_dx;
    wire signed [23:0] steer_new = steer_q + {{9{sdx_c[11]}}, sdx_c, 3'b000};
    wire signed [23:0] steer_tot = steer_used + steer_q;
    wire signed [23:0] steer_c   = (steer_tot > STEER_MAX)  ? STEER_MAX - steer_used :
                                   (steer_tot < -STEER_MAX) ? -STEER_MAX - steer_used : steer_q;
    reg  signed [23:0] steer_ok;                   // registered in S_HW (timing)
    reg  [35:0] d2s;                               // |d|^2, registered (timing)
    reg         vpos;                              // v_rel_n > 0, registered (timing)

    localparam S_IDLE = 5'd0, S_HK = 5'd1, S_HW = 5'd2, S_INT = 5'd3, S_P0 = 5'd4, S_P1 = 5'd5,
               S_P2 = 5'd6, S_P3 = 5'd7, S_P4 = 5'd8, S_N1 = 5'd9, S_N2 = 5'd10, S_N3 = 5'd11,
               S_N4 = 5'd12, S_N5 = 5'd13, S_N6 = 5'd14, S_N7 = 5'd15, S_N8 = 5'd16, S_N9 = 5'd17,
               S_N10 = 5'd18, S_N11 = 5'd19, S_N12 = 5'd20, S_N13 = 5'd21, S_N14 = 5'd22,
               S_NEXT = 5'd23, S_DONE = 5'd24, S_PQ = 5'd25, S_T1 = 5'd26, S_T2 = 5'd27,
               S_T3 = 5'd28, S_T4 = 5'd29, S_T5 = 5'd30, S_PW = 5'd31;
    localparam S_P5 = 6'd32, S_N6B = 6'd33, S_N14B = 6'd34;
    reg signed [23:0] dby;                         // ball's forward deflection (registered, timing)
    reg [5:0] st;

    // The ball waits under the stance pointer while aiming. Not during the
    // swipe itself (GS_THROW): the stance is locked then, and a late state
    // change could otherwise reset a ball that was just thrown.
    wire aim_state = (game_state == `GS_AIM) || (game_state == `GS_PRACTICE_SWIPE);

    // A throw can arrive while the FSM is busy with a tick (~30 clocks), so it
    // is remembered until the FSM is idle: a throw is never lost.
    reg throw_pend;
    always @(posedge clk) begin
        if (rst || (throw_pend && st == S_IDLE)) throw_pend <= 1'b0;
        else if (throw_valid && game_state == `GS_THROW) throw_pend <= 1'b1;
    end

    wire [3:0] scan_first = scan_rev ? 4'd9 : 4'd0;
    wire [3:0] scan_last  = scan_rev ? 4'd0 : 4'd9;

    always @(posedge clk) begin
        impulse_valid <= 1'b0; scan_done <= 1'b0; contact_pulse <= 1'b0;
        if (rst) begin
            st <= S_IDLE; ball_phase <= `BP_IDLE; ball_spin <= 0;
            x <= {`W_LANE_CX, 14'd0}; y <= {`W_BALL_Y0, 14'd0}; vx <= 0; vy <= 0;
            rev <= 0; rev_left <= 0; roll_ticks <= 0; steer_q <= 0; steer_used <= 0; scan_rev <= 0;
            touching <= 0; pin_rd_idx <= 0; ball_angle <= 0;
            ma <= 0; mb <= 0; dx <= 0; dy <= 0; relx <= 0; rely <= 0; d2 <= 0;
            nx <= 0; ny <= 0; t <= 0; vrn <= 0; sp <= 0; sb <= 0; tq <= 0; dpx <= 0; dpy <= 0; tdx <= 0; dbx <= 0;
            impulse_pin <= 0; impulse_vx <= 0; impulse_vy <= 0; contact_px <= 0; contact_py <= 0;
            prx <= 0; pry <= 0; prvx <= 0; prvy <= 0; prs <= 0; pdx_q <= 0; pdy_q <= 0; far_q <= 0;
            prup <= 1'b1; inv_q <= 0; kt <= 0; hook_a <= 0; in_oil <= 1'b1; steer_ok <= 0; d2s <= 0; vpos <= 0;
        end else begin
            // ---- steer packets collect until the next tick ----
            if (steer_valid && rolling && roll_ticks < `STEER_TICKS && st != S_INT)
                steer_q <= steer_new;
            // ---- a throw starts the roll (only from the throwing state) ----
            if (throw_pend && st == S_IDLE) begin
                x <= {throw_x0, 14'd0}; y <= {`W_BALL_Y0, 14'd0};
                vx <= {throw_vx, 8'd0}; vy <= {throw_vy, 8'd0};
                ball_spin <= throw_spin; ball_phase <= `BP_SKID;
                rev <= spin_abs * rev_k;              // side slip store
                rev_left <= ~throw_spin[`SPIN_W-1];
                kt  <= spin_abs * KT_PER_SPIN;
                roll_ticks <= 0; steer_q <= 0; steer_used <= 0;
                touching <= 0;
            end else if (aim_state && st == S_IDLE && !throw_valid) begin
                // waiting on the foul line under the stance pointer
                ball_phase <= `BP_IDLE;
                x <= {stance_x, 14'd0}; y <= {`W_BALL_Y0, 14'd0}; vx <= 0; vy <= 0;
                rev <= 0; steer_q <= 0;
            end
            case (st)
                S_IDLE: if (tick_phys) begin
                    // the oil ROM is addressed from the current position now
                    st <= (rolling || ball_phase == `BP_GUTTER) ? S_HK : S_DONE;
                end
                S_HK: st <= S_HW;
                S_HW: begin                                       // mu_q valid: this tick's friction
                    hook_a   <= hook_c;
                    in_oil   <= (mu_q < MU_DRY_TH);
                    steer_ok <= steer_c;
                    st <= S_INT;
                end
                S_INT: begin
                    ball_angle <= ball_angle + {1'b0, vy[23:9]} +
                                  {{6{ball_spin[`SPIN_W-1]}}, ball_spin, 4'd0};
                    x <= nxp[29:0];
                    y <= nyp[29:0];
                    if (ball_phase != `BP_PIT) vy <= vy_next;
                    if (roll_ticks != 11'h7FF) roll_ticks <= roll_ticks + 11'd1;
                    if (rolling) begin
                        // slip friction + steer nudge
                        vx  <= vx + (rev_left ? -$signed({1'b0, hook_a}) : $signed({1'b0, hook_a})) + steer_ok;
                        rev <= rev - hook_a;
                        steer_used <= steer_used + steer_ok;
                        steer_q <= 0;
                        // SKID in the oil, HOOK while slip is left on the
                        // dry wood, ROLL once the slip is used up
                        if (in_oil)                  ball_phase <= `BP_SKID;
                        else if (rev != hook_a)      ball_phase <= `BP_HOOK;
                        else                         ball_phase <= `BP_ROLL;
                    end
                    // gutter: only on the lane; on the deck a ball knocked
                    // sideways by pins just carries on into the pit
                    if (rolling && ball_y < `W_DECK_Y && (nx16 < `W_LANE_L || nx16 > `W_LANE_R)) begin
                        ball_phase <= `BP_GUTTER;
                        x  <= {(nx16 < `W_LANE_L) ? `W_GUT_LX : `W_GUT_RX, 14'd0};
                        vx <= 24'sd0; rev <= 0;
                    end
                    if (nyp[29:14] >= `W_BALL_PIT) begin
                        ball_phase <= `BP_PIT;
                        vx <= 0; vy <= 0;
                    end
                    pin_rd_idx <= scan_first;
                    st <= rolling ? S_PW : S_DONE;
                end
                S_PW: st <= S_P0;                                 // C's read port settles (2 clocks, XDC)
                // ---------------- pin scan ----------------------------------
                S_P0: begin                                       // latch C's read port
                    prx <= pin_rd_x; pry <= pin_rd_y; prvx <= pin_rd_vx; prvy <= pin_rd_vy; prs <= pin_rd_solid;
                    prup <= pin_rd_upright;
                    st <= S_PQ;
                end
                S_PQ: begin                                       // offsets, registered (timing)
                    pdx_q <= pdx; pdy_q <= pdy; far_q <= (adx > near) || (ady > near);
                    st <= S_P1;
                end
                S_P1: begin
                    dx <= pdx_q; dy <= pdy_q;
                    // (a part-select is UNSIGNED in Verilog: without $signed a
                    //  ball moving left read as a huge positive speed and slid
                    //  through the pins - found by the carry-map trace)
                    relx <= $signed(vx[23:8]) - prvx;
                    rely <= $signed(vy[23:8]) - prvy;
                    if (!prs || far_q) begin
                        touching[pin_rd_idx] <= 1'b0;
                        st <= S_NEXT;
                    end else begin
                        ma <= pdx_q; mb <= pdx_q;                 // req A: dx^2
                        st <= S_P2;
                    end
                end
                S_P2: begin ma <= dy; mb <= dy; st <= S_P3; end    // req B: dy^2
                S_P3: begin d2 <= mp[35:0]; st <= S_P4; end        // A ready
                S_P4: begin d2s <= d2_full; st <= S_P5; end       // B ready -> |d|^2 (registered)
                S_P5: begin
                    if (d2s < r2_hit) begin
                        if (touching[pin_rd_idx] && prup) st <= S_NEXT;   // already pushed
                        else begin                                // req C: dx / |d|
                            inv_q <= {9'd0, inv_rom[d2s[18:12]]};
                            ma <= dx; mb <= {9'd0, inv_rom[d2s[18:12]]};
                            st <= S_N1;
                        end
                    end else begin
                        if (d2s > r2_clr) touching[pin_rd_idx] <= 1'b0;
                        st <= S_NEXT;
                    end
                end
                S_N1:  begin ma <= dy; mb <= inv_q; st <= S_N2; end           // req D: dy / |d|
                S_N2:  begin nx <= mp[17:0]; st <= S_N3; end                   // C ready
                S_N3:  begin ny <= mp[17:0]; ma <= relx; mb <= nx; st <= S_N4; end // D, req E
                S_N4:  begin ma <= rely; mb <= ny; st <= S_N5; end             // req F
                S_N5:  begin t <= mp; st <= S_N6; end                          // E ready
                S_N6:  begin                                                   // F ready
                    touching[pin_rd_idx] <= 1'b1;
                    vrn  <= vrn_full[24:0];                       // registered (timing)
                    vpos <= (vrn_full > 0);
                    st <= S_N6B;
                end
                S_N6B: begin
                    if (!vpos) st <= S_NEXT;                      // already separating
                    else begin
                        ma <= vrn; mb <= kp;                      // req G
                        st <= S_N7;
                    end
                end
                S_N7:  begin ma <= vrn; mb <= kb; st <= S_N8; end              // req H
                S_N8:  begin sp <= mp >>> 12; st <= S_N9; end                  // G ready (vrn, kp > 0)
                S_N9:  begin sb <= mp >>> 12; ma <= sp; mb <= nx; st <= S_N10; end // H, req I
                S_N10: begin ma <= sp; mb <= ny; st <= S_N11; end              // req J
                S_N11: begin dpx <= sra0(mp, 5'd14); ma <= sb; mb <= nx; st <= S_N12; end // I, req K
                S_N12: begin                                                   // J ready
                    dpy <= sra0(mp, 5'd14);
                    contact_pulse <= 1'b1;
                    contact_px    <= prx;
                    contact_py    <= pry;
                    ma <= sb; mb <= ny;                                        // req L
                    st <= S_N13;
                end
                S_N13: begin                                      // K ready (Q3.12 -> 2^-20: <<8, >>14)
                    dbx <= sra0(mp, 5'd6);
                    ma <= sp; mb <= kt;                           // req T: tangential size
                    st <= S_N14;
                end
                S_N14: begin                                      // L ready: deflect the ball
                    vx <= vx - dbx;
                    dby <= sra0(mp, 5'd6);                        // registered (timing)
                    st <= S_N14B;
                end
                S_N14B: begin                                     // T ready (>= 0)
                    vy <= ((vy - dby) < vy_min) ? vy_min : vy - dby;
                    tq <= mp >>> 12;
                    st <= S_T2;
                end
                S_T1: begin tq <= mp >>> 12; st <= S_T2; end                  // (not used since v3)
                S_T2: begin ma <= tq; mb <= ny; st <= S_T3; end               // req U
                S_T3: begin ma <= tq; mb <= nx; st <= S_T4; end               // req V
                S_T4: begin tdx <= sra0(mp, 5'd14); st <= S_T5; end           // U ready: tq*ny
                S_T5: begin                                                   // V ready: tq*nx
                    // t = (-ny, nx): a left-hook ball (spin > 0) drags the pin left
                    impulse_valid <= 1'b1;
                    impulse_pin   <= pin_rd_idx;
                    impulse_vx    <= ball_spin[`SPIN_W-1] ? dpx + tdx : dpx - tdx;
                    impulse_vy    <= ball_spin[`SPIN_W-1] ? dpy - sra0(mp, 5'd14) : dpy + sra0(mp, 5'd14);
                    st <= S_NEXT;
                end
                S_NEXT: begin
                    if (pin_rd_idx == scan_last) st <= S_DONE;
                    else begin
                        pin_rd_idx <= scan_rev ? pin_rd_idx - 4'd1 : pin_rd_idx + 4'd1;
                        st <= S_PW;
                    end
                end
                S_DONE: begin
                    scan_done <= 1'b1;
                    scan_rev  <= ~scan_rev;
                    st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
