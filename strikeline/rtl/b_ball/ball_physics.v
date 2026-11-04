`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// ball_physics.v : skid -> hook -> roll, gutter, ball -> pin collisions
//-----------------------------------------------------------------------------
// Owner   : Student B
// Fixed point (internal): x, y unsigned Q10.20 inches (30 bit)
//                         vx, vy signed, 1 LSB = 2^-20 in/tick (24 bit)
//           Exported as POS Q10.6 (= x[29:14]) and VEL Q3.12 (= v[23:8]).
//           2^-20 in/tick^2 is fine enough for the tiny per-tick friction
//           (0.035 mph per second of oil = 8 LSB).
// Per physics tick (1024 Hz, ~97 600 clocks) one FSM pass does:
//   INTEGRATE  x += vx, y += vy, then the phase rules:
//     SKID  (y < oil length): vy -= dec_oil, vx -= spin * hook_oil / 16 (tiny)
//     HOOK  (dry lane)      : vy -= dec_dry, vx -= spin * hook_dry / 16
//           (spin > 0 hooks LEFT = -x). After HOOK_LEN ticks the spin is
//           "used up" -> ROLL: the ball keeps its final direction.
//     GUTTER if the ball centre passes a lane edge before the deck: straight down the
//           channel, can no longer touch pins.
//     PIT   at y = 760 in. vy never drops below 3 mph, so every ball
//           reaches the pit (no stuck game).
//   SCAN 10 pins (read port from C, one pin at a time), for each:
//     overlap test |d|^2 < (Rb+Rp)^2 with SQUARES -> no square root.
//     normal n = d / (Rb+Rp) with a CONSTANT reciprocal (|d| is within one
//     tick of travel, 6 %, of Rb+Rp at first contact, so no divider).
//     v_rel_n = (v_ball - v_pin) . n   (> 0 means they are approaching)
//     pin  dv = +kp * v_rel_n * n,  kp = (1+e) mb / (mb + mp)   (ROM)
//     ball dv = -kb * v_rel_n * n,  kb = (1+e) mp / (mb + mp)
//     (impulse J = (1+e) mb mp/(mb+mp) v_rel_n divided by each mass.)
//     A per-pin "in contact" flag gives one impulse per contact; it clears
//     when the pin is 0.2 in further away than the contact distance.
//   The pin's velocity change goes to C as an impulse. When the scan is
//   finished scan_done tells C to run its own pin update (fixed order:
//   B then C, so C's pins never change while B reads them).
// Multiplier use: 2 per tick for the hook + 4 per near pin + 10 per hit.
// Cycle budget: worst case 10 hits = ~200 clocks of 97 656 (0.2 %).
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
    input  wire signed [3:0]  throw_spin,
    input  wire [15:0] throw_x0,
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
    output reg  signed [3:0] ball_spin,
    output reg  [15:0] ball_angle,       // finger-hole marker, [15:10] used
    output reg         contact_pulse,    // a pin was hit (debug overlay, D)
    output reg  [15:0] contact_px,
    output reg  [15:0] contact_py
);
    // contact distance: ball 4.3 in + standing pin 2.4 in = 6.7 in, or
    // + lying pin 4.0 in (the same footprint C uses pin to pin) = 8.3 in
    localparam [35:0] R2_HIT_UP = 36'd183869;      // (6.7 in * 64)^2
    localparam [35:0] R2_CLR_UP = 36'd201601;      // (6.9 in * 64)^2
    localparam [35:0] R2_HIT_DN = (R_DOWN + 36'd275) * (R_DOWN + 36'd275);   // (4.3 in + R)^2
    localparam [35:0] R2_CLR_DN = (R_DOWN + 36'd288) * (R_DOWN + 36'd288);   // + 0.2 in
    localparam [16:0] NEAR_UP   = 17'd448;         // 7 in: quick reject box
    localparam [16:0] NEAR_DN   = R_DOWN + 17'd320;           // 4.3 in + R + 0.7 in

    // ---------------- ROM of ball parameters --------------------------------
    reg [63:0] prm_rom [0:7];
    reg [8:0]  inv_rom [0:127];                    // 2^14 / |d|, indexed by d^2 >> 12
    initial begin
        $readmemh("ball_params.mem", prm_rom);
        $readmemh("inv_len.mem", inv_rom);
    end
    wire [63:0] prm      = prm_rom[{settings[`SET_OIL], settings[`SET_LB_HI:`SET_LB_LO]}];
    wire [7:0]  dec_oil  = prm[63:56];
    wire [7:0]  dec_dry  = prm[55:48];
    wire [7:0]  hook_oil = prm[47:40];
    wire [7:0]  hook_dry = prm[39:32];
    wire [17:0] kp       = {2'b00, prm[31:16]};
    wire [17:0] kb       = {2'b00, prm[15:0]};
    wire [15:0] oil_len  = settings[`SET_OIL] ? `W_OIL_L : `W_OIL_S;

    // ---------------- state -------------------------------------------------
    reg [29:0] x, y;
    reg signed [23:0] vx, vy;
    reg [10:0] hook_ticks;
    reg [9:0]  touching;                           // per-pin contact flags
    assign ball_x  = x[29:14];
    assign ball_y  = y[29:14];
    assign ball_vx = vx[23:8];
    assign ball_vy = vy[23:8];

    // ---------------- shared multiplier -------------------------------------
    reg  signed [24:0] ma;
    reg  signed [17:0] mb;
    wire signed [42:0] mp;
    mul_s25x18 u_mul (.clk(clk), .a(ma), .b(mb), .p(mp));

    // ---------------- datapath registers for one pin -----------------------
    reg signed [16:0] dx, dy, relx, rely;
    reg [35:0]        d2;
    reg signed [17:0] nx, ny;
    reg signed [42:0] t;
    reg signed [24:0] vrn, sp, sb;
    reg signed [15:0] dpx;
    reg signed [23:0] dbx;

    // C's read port is latched in S_P0 (timing: index -> C's mux -> here)
    reg [15:0] prx, pry;
    reg signed [15:0] prvx, prvy;
    reg        prs, far_q, prup;
    reg [17:0] inv_q;                              // 1/|d| of this contact
    reg [10:0] hook_len;                           // set at the throw: longer for more spin
    reg [17:0] kb_eff;                             // ball deflection, less for a spinning ball
    wire [35:0] r2_hit = prup ? R2_HIT_UP : R2_HIT_DN;
    wire [35:0] r2_clr = prup ? R2_CLR_UP : R2_CLR_DN;
    wire [16:0] near   = prup ? NEAR_UP   : NEAR_DN;
    reg signed [16:0] pdx_q, pdy_q;
    wire signed [16:0] pdx = $signed({1'b0, prx}) - $signed({1'b0, ball_x});
    wire signed [16:0] pdy = $signed({1'b0, pry}) - $signed({1'b0, ball_y});
    wire [16:0] adx = pdx[16] ? -pdx : pdx;
    wire [16:0] ady = pdy[16] ? -pdy : pdy;
    wire [35:0] d2_full = d2 + mp[35:0];
    wire signed [42:0] vrn_full = (t + mp) >>> 14;

    wire rolling = (ball_phase == `BP_SKID) || (ball_phase == `BP_HOOK) || (ball_phase == `BP_ROLL);

    // ---------------- integration results (combinational) -------------------
    wire signed [31:0] nxp = $signed({2'b00, x}) + vx;
    wire signed [31:0] nyp = $signed({2'b00, y}) + vy;
    wire [15:0] nx16 = nxp[29:14];
    // while hooking, friction turns forward speed into sideways speed: the
    // forward deceleration grows by the size of the hook acceleration
    wire signed [23:0] hacc     = mp[27:4];
    wire [23:0]        hacc_abs = hacc[23] ? -hacc : hacc;
    wire signed [23:0] vy_dec  = vy - $signed({16'd0, (ball_phase == `BP_SKID) ? dec_oil : dec_dry})
                                    - ((ball_phase == `BP_HOOK) ? $signed(hacc_abs) : 24'sd0);
    wire [2:0] spin_abs = throw_spin[3] ? -throw_spin[2:0] : throw_spin[2:0];
    wire signed [23:0] vy_min  = $signed({`W_SPEED_MIN, 8'd0});
    wire signed [23:0] vy_next = (vy_dec < vy_min) ? vy_min : vy_dec;

    localparam S_IDLE = 5'd0, S_HK = 5'd1, S_HW = 5'd2, S_INT = 5'd3, S_P0 = 5'd4, S_P1 = 5'd5,
               S_P2 = 5'd6, S_P3 = 5'd7, S_P4 = 5'd8, S_N1 = 5'd9, S_N2 = 5'd10, S_N3 = 5'd11,
               S_N4 = 5'd12, S_N5 = 5'd13, S_N6 = 5'd14, S_N7 = 5'd15, S_N8 = 5'd16, S_N9 = 5'd17,
               S_N10 = 5'd18, S_N11 = 5'd19, S_N12 = 5'd20, S_N13 = 5'd21, S_N14 = 5'd22,
               S_NEXT = 5'd23, S_DONE = 5'd24, S_PQ = 5'd25;
    reg [4:0] st;

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

    always @(posedge clk) begin
        impulse_valid <= 1'b0; scan_done <= 1'b0; contact_pulse <= 1'b0;
        if (rst) begin
            st <= S_IDLE; ball_phase <= `BP_IDLE; ball_spin <= 0;
            x <= {`W_LANE_CX, 14'd0}; y <= {`W_BALL_Y0, 14'd0}; vx <= 0; vy <= 0;
            hook_ticks <= 0; touching <= 0; pin_rd_idx <= 0; ball_angle <= 0;
            ma <= 0; mb <= 0; dx <= 0; dy <= 0; relx <= 0; rely <= 0; d2 <= 0;
            nx <= 0; ny <= 0; t <= 0; vrn <= 0; sp <= 0; sb <= 0; dpx <= 0; dbx <= 0;
            impulse_pin <= 0; impulse_vx <= 0; impulse_vy <= 0; contact_px <= 0; contact_py <= 0;
            prx <= 0; pry <= 0; prvx <= 0; prvy <= 0; prs <= 0; pdx_q <= 0; pdy_q <= 0; far_q <= 0;
            prup <= 1'b1; inv_q <= 0; hook_len <= 11'd640; kb_eff <= 0;
        end else begin
            // ---- a throw starts the roll (only from the throwing state) ----
            if (throw_pend && st == S_IDLE) begin
                x <= {throw_x0, 14'd0}; y <= {`W_BALL_Y0, 14'd0};
                vx <= {throw_vx, 8'd0}; vy <= {throw_vy, 8'd0};
                ball_spin <= throw_spin; ball_phase <= `BP_SKID;
                hook_ticks <= 0; touching <= 0;
                // more revs take longer to roll out: 256 + 96 ticks per spin level
                hook_len <= 11'd256 + {2'b00, spin_abs, 6'd0} + {3'b000, spin_abs, 5'd0};
                // a spinning ball drives through the pins: kb * (1 - |spin| / 16)
                kb_eff <= kb - ((kb * spin_abs) >> 4);
            end else if (aim_state && st == S_IDLE && !throw_valid) begin
                // waiting on the foul line under the stance pointer
                ball_phase <= `BP_IDLE;
                x <= {stance_x, 14'd0}; y <= {`W_BALL_Y0, 14'd0}; vx <= 0; vy <= 0;
            end
            case (st)
                S_IDLE: if (tick_phys) begin
                    if (rolling || ball_phase == `BP_GUTTER) begin
                        ma <= ball_spin;                          // spin * hook gain
                        mb <= {10'd0, (ball_phase == `BP_SKID) ? hook_oil : hook_dry};
                        st <= S_HK;
                    end else begin
                        st <= S_DONE;                             // C still needs its tick
                    end
                end
                S_HK: st <= S_HW;
                S_HW: st <= S_INT;                                // product ready in S_INT
                S_INT: begin
                    ball_angle <= ball_angle + {1'b0, vy[23:9]} + {{6{ball_spin[3]}}, ball_spin, 6'd0};
                    x <= nxp[29:0];
                    y <= nyp[29:0];
                    if (ball_phase != `BP_PIT) vy <= vy_next;
                    case (ball_phase)
                        `BP_SKID: begin
                            vx <= vx - mp[27:4];                  // gains are in 1/16 LSB
                            if (ball_y >= oil_len) ball_phase <= `BP_HOOK;
                        end
                        `BP_HOOK: begin
                            vx <= vx - mp[27:4];
                            hook_ticks <= hook_ticks + 11'd1;
                            if (hook_ticks == hook_len) ball_phase <= `BP_ROLL;
                        end
                        default: ;                                // ROLL, GUTTER: straight
                    endcase
                    // gutter: only on the lane; on the deck a ball knocked
                    // sideways by pins just carries on into the pit
                    if (rolling && ball_y < `W_DECK_Y && (nx16 < `W_LANE_L || nx16 > `W_LANE_R)) begin
                        ball_phase <= `BP_GUTTER;
                        x  <= {(nx16 < `W_LANE_L) ? `W_GUT_LX : `W_GUT_RX, 14'd0};
                        vx <= 24'sd0;
                    end
                    if (nyp[29:14] >= `W_BALL_PIT) begin
                        ball_phase <= `BP_PIT;
                        vx <= 0; vy <= 0;
                    end
                    pin_rd_idx <= 4'd0;
                    st <= rolling ? S_P0 : S_DONE;
                end
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
                S_P4: begin                                       // B ready -> |d|^2
                    if (d2_full < r2_hit) begin
                        if (touching[pin_rd_idx]) st <= S_NEXT;   // already pushed
                        else begin                                // req C: dx / |d|
                            inv_q <= {9'd0, inv_rom[d2_full[18:12]]};
                            ma <= dx; mb <= {9'd0, inv_rom[d2_full[18:12]]};
                            st <= S_N1;
                        end
                    end else begin
                        if (d2_full > r2_clr) touching[pin_rd_idx] <= 1'b0;
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
                    if (vrn_full <= 0) st <= S_NEXT;              // already separating
                    else begin
                        vrn <= vrn_full[24:0];
                        ma <= vrn_full[24:0]; mb <= kp;           // req G
                        st <= S_N7;
                    end
                end
                S_N7:  begin ma <= vrn; mb <= kb_eff; st <= S_N8; end          // req H
                S_N8:  begin sp <= mp >>> 12; st <= S_N9; end                  // G ready
                S_N9:  begin sb <= mp >>> 12; ma <= sp; mb <= nx; st <= S_N10; end // H, req I
                S_N10: begin ma <= sp; mb <= ny; st <= S_N11; end              // req J
                S_N11: begin dpx <= mp >>> 14; ma <= sb; mb <= nx; st <= S_N12; end // I, req K
                S_N12: begin                                                   // J ready
                    impulse_valid <= 1'b1;
                    impulse_pin   <= pin_rd_idx;
                    impulse_vx    <= dpx;
                    impulse_vy    <= mp >>> 14;
                    contact_pulse <= 1'b1;
                    contact_px    <= prx;
                    contact_py    <= pry;
                    ma <= sb; mb <= ny;                                        // req L
                    st <= S_N13;
                end
                S_N13: begin dbx <= mp >>> 6; st <= S_N14; end    // K ready (Q3.12 -> 2^-20: <<8, >>14)
                S_N14: begin                                      // L ready: deflect the ball
                    vx <= vx - dbx;
                    vy <= ((vy - (mp >>> 6)) < vy_min) ? vy_min : vy - (mp >>> 6);
                    st <= S_NEXT;
                end
                S_NEXT: begin
                    if (pin_rd_idx == 4'd9) st <= S_DONE;
                    else begin pin_rd_idx <= pin_rd_idx + 4'd1; st <= S_P0; end
                end
                S_DONE: begin
                    scan_done <= 1'b1;
                    st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
