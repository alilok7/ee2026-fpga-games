`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// pin_physics.v : 10 pins, wobble/topple, pin-pin collisions, pin-setter
//-----------------------------------------------------------------------------
// Owner   : Student C
// Fixed point: position unsigned Q10.12 inches (22 bit), velocity signed
//   Q3.16 in/tick (20 bit). Exported as POS Q10.6 (1/64 in) / VEL Q3.12.
//   Q3.16 so that the friction step v -= v/256 still works for a slow slide.
// Pin shape: a standing pin is one 2.4 in circle at its base. A lying pin is
//   two circles along its fall direction: the belly (3.5 in, 5 in from the
//   base) and the head (2.4 in, 11.5 in from the base); half those offsets
//   while it is still falling. B's ball sees only the belly circle.
// Every physics tick, after B's ball scan (scan_done):
//   1. UPDATE each pin (pipelined, one per clock): wobble / fall timers,
//      slide x += v with friction v -= v >> 8, gutter, kickback, pit.
//   2. PAIRS: walk the 45 pin pairs (forward and backward on alternate
//      ticks) and test every circle of one pin against every circle of the
//      other. When two circles overlap:
//        - the lying pin(s) are pushed apart by the whole overlap
//          (+1/64 in), half / half when both lie;
//        - if they approach, an equal-mass collision along the normal n:
//            dv = (1+e)/2 * (v_i - v_j).n,  v_i -= dv n,  v_j += dv n
//          with (1+e)/2 = 1 - 1/8 - 1/16 (e = 0.625).
//   A standing pin pushed harder than TOPPLE falls in the push direction
//   (faster for a harder push); a softer push only makes it wobble. A hit
//   by a lying pin's head needs only a quarter of TOPPLE.
//   Ball impulses (from B) are applied whenever the FSM is idle.
// Rack commands (D): the rake sweeps fallen pins into the pit (0.55 s),
//   then FULL = 10 pins on their spots, SWEEP = keep the standing pins,
//   LEAVE = exactly rack_mask.
// Timing: record reads and writes are registered (two write ports A / B
//   plus whole-rack operations) and all products go through one pipelined
//   multiplier, so every step of the pair test is its own state.
// Names kept lower case (rec, st, rA, rB, nA, nB) are read by tb_physics
// and tb_carry.
//=============================================================================
module pin_physics #(
    parameter [15:0] R_DOWN   = 16'd224,          // belly radius of a lying pin, 1/64 in (3.5 in)
    parameter [19:0] TOPPLE_P = 20'd2200,         // push that tips a standing pin, Q3.16 (~2 mph)
    parameter        FRIC_SH  = 8,                // sliding friction: v -= v >> FRIC_SH per tick
    parameter        DL_S1    = 3,                // (1+e)/2 = 1 - 2^-DL_S1 - 2^-DL_S2
    parameter        DL_S2    = 4
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_phys,
    input  wire        scan_done,
    input  wire        impulse_valid,
    input  wire [3:0]  impulse_pin,
    input  wire signed [15:0] impulse_vx,
    input  wire signed [15:0] impulse_vy,
    input  wire        rack_go,
    input  wire [1:0]  rack_cmd,
    input  wire [9:0]  rack_mask,
    input  wire        force_settle,     // settle timeout: finish every animation
    // read port for B
    input  wire [3:0]  pin_rd_idx,
    output wire [15:0] pin_rd_x,
    output wire [15:0] pin_rd_y,
    output wire signed [15:0] pin_rd_vx,
    output wire signed [15:0] pin_rd_vy,
    output wire        pin_rd_solid,
    output wire        pin_rd_upright,
    // status
    output wire [239:0] pin_vis,         // 10 x {x[5:0], y[9:0], state[2:0], dir[2:0], stage[1:0]}
    output wire [9:0]  standing,         // STANDING or WOBBLING
    output wire [9:0]  busy,             // wobbling, falling or still sliding
    output wire        rack_busy,
    output reg  [9:0]  rake_y            // rake position (inches), 0 = no rake
);

    // ---------- 1. Constants ----------
    localparam [8:0]  WOB_T  = 9'd410;                               // wobble time, ticks
    localparam [8:0]  FALL_T = 9'd150;                               // slowest fall time, ticks
    localparam integer R_BIG = R_DOWN;                               // circle radii, 1/64 in
    localparam integer R_SML = 154;
    localparam [16:0] NEAR   = 2 * R_BIG + 64;                       // quick reject: 2 bellies + 1 in
    localparam [35:0] R2_BB  = (R_BIG + R_BIG) * (R_BIG + R_BIG);    // contact distance^2
    localparam [35:0] R2_BS  = (R_BIG + R_SML) * (R_BIG + R_SML);
    localparam [35:0] R2_SS  = (R_SML + R_SML) * (R_SML + R_SML);
    // slower than this a slide stops (must be >= 2^FRIC_SH, else v >> FRIC_SH = 0)
    localparam [19:0] STOP_V = (20'd1 << FRIC_SH) + 20'd64;
    localparam [19:0] GUT_V  = 20'd655;                              // slower than this past the lane edge: into the gutter
    localparam [21:0] KICK_L = {`W_KICK_L, 6'd0};
    localparam [21:0] KICK_R = {`W_KICK_R, 6'd0};
    localparam [21:0] LANE_L = {`W_LANE_L, 6'd0};
    localparam [21:0] LANE_R = {`W_LANE_R, 6'd0};
    localparam [21:0] GUT_LX = {`W_GUT_LX, 6'd0};
    localparam [21:0] GUT_RX = {`W_GUT_RX, 6'd0};
    localparam [21:0] BACK_Y = 22'd2_867_200;                        // 700 in: pins cannot slide back further
    localparam [21:0] PIT_Y  = {`W_PIN_PIT, 6'd0};

    // ---------- 2. ROMs ----------
    reg [31:0] SPOT_ROM [0:9];
    reg [7:0]  PAIR_ROM [0:44];
    reg [8:0]  INV_ROM  [0:127];                                     // 2^14 / |d|, indexed by d^2 >> 12
    initial begin
        $readmemh("inv_len.mem", INV_ROM);
        $readmemh("pin_spots.mem", SPOT_ROM);
        $readmemh("pin_pairs.mem", PAIR_ROM);
    end

    // ---------- 3. Pin records ----------
    // {x[21:0], y[21:0], vx[19:0], vy[19:0], state[2:0], dir[2:0], timer[8:0]} = 99 bits
    reg [98:0] rec [0:9];
    function [21:0]        REC_X;     input [98:0] R; REC_X     = R[98:77]; endfunction
    function [21:0]        REC_Y;     input [98:0] R; REC_Y     = R[76:55]; endfunction
    function signed [19:0] REC_VX;    input [98:0] R; REC_VX    = R[54:35]; endfunction
    function signed [19:0] REC_VY;    input [98:0] R; REC_VY    = R[34:15]; endfunction
    function [2:0]         REC_STATE; input [98:0] R; REC_STATE = R[14:12]; endfunction
    function [2:0]         REC_DIR;   input [98:0] R; REC_DIR   = R[11:9];  endfunction
    function [8:0]         REC_TIMER; input [98:0] R; REC_TIMER = R[8:0];   endfunction
    function [15:0]        REC_PX;    input [98:0] R; REC_PX    = R[98:83]; endfunction   // x in 1/64 in
    function [15:0]        REC_PY;    input [98:0] R; REC_PY    = R[76:61]; endfunction   // y in 1/64 in
    function [98:0] MAKE_REC;
        input [21:0] X, Y;
        input [19:0] VX, VY;
        input [2:0]  S, D;
        input [8:0]  T;
        MAKE_REC = {X, Y, VX, VY, S, D, T};
    endfunction

    // ---------- 4. Helper functions ----------
    // direction of (A, B): 0 = +y (toward the pit), clockwise in 45 degree steps
    function [2:0] DIR8;
        input signed [19:0] A, B;
        reg [19:0] AX, AY;
        begin
            AX = A[19] ? -A : A;
            AY = B[19] ? -B : B;
            if (AY > (AX << 1))
                DIR8 = B[19] ? 3'd4 : 3'd0;
            else if (AX > (AY << 1))
                DIR8 = A[19] ? 3'd6 : 3'd2;
            else if (!A[19])
                DIR8 = B[19] ? 3'd3 : 3'd1;
            else
                DIR8 = B[19] ? 3'd5 : 3'd7;
        end
    endfunction

    function IS_UPRIGHT;
        input [2:0] S;
        IS_UPRIGHT = (S == `PS_STANDING) || (S == `PS_WOBBLING);
    endfunction

    // x or y offset of a point along a lying pin's body in fall direction D:
    // S on a straight direction, G (= S / sqrt 2) on a diagonal. 1/64 in.
    function [15:0] BODY_OFF;
        input [2:0] D;
        input       AXIS_Y;
        input [9:0] S_IN, G_IN;
        reg signed [15:0] S, G;
        begin
            S = $signed({6'd0, S_IN});
            G = $signed({6'd0, G_IN});
            case ({AXIS_Y, D})
                4'b0_000: BODY_OFF = 16'sd0; 4'b1_000: BODY_OFF = S;
                4'b0_001: BODY_OFF = G;      4'b1_001: BODY_OFF = G;
                4'b0_010: BODY_OFF = S;      4'b1_010: BODY_OFF = 16'sd0;
                4'b0_011: BODY_OFF = G;      4'b1_011: BODY_OFF = -G;
                4'b0_100: BODY_OFF = 16'sd0; 4'b1_100: BODY_OFF = -S;
                4'b0_101: BODY_OFF = -G;     4'b1_101: BODY_OFF = -G;
                4'b0_110: BODY_OFF = -S;     4'b1_110: BODY_OFF = 16'sd0;
                default:  BODY_OFF = AXIS_Y ? G : -G;
            endcase
        end
    endfunction

    // x or y of a pin's collision circle (HEAD = 0: base / belly, 1: head).
    // Signed: a pin lying toward the gutter can have circles at x < 0.
    function signed [16:0] CIRCLE;
        input [98:0] R;
        input        AXIS_Y;
        input        HEAD;
        reg [9:0] S, G;
        reg signed [15:0] O;
        begin
            S = HEAD ? 10'd736 : 10'd320;                            // 11.5 in / 5 in
            G = HEAD ? 10'd520 : 10'd226;
            if (REC_STATE(R) == `PS_FALLING) begin
                S = S >> 1;
                G = G >> 1;
            end
            O = IS_UPRIGHT(REC_STATE(R)) ? 16'sd0 : BODY_OFF(REC_DIR(R), AXIS_Y, S, G);
            CIRCLE = $signed({1'b0, (AXIS_Y ? REC_PY(R) : REC_PX(R))}) + {O[15], O};
        end
    endfunction

    // a velocity change (HX, HY) hits a pin: topple, wobble, or add to its slide
    function [98:0] HIT;
        input [98:0] R;
        input signed [19:0] HX, HY;
        input        DO_TOPPLE;
        input [2:0]  FALL_DIR;
        input [8:0]  FALL_TICKS;
        begin
            HIT = R;
            if (IS_UPRIGHT(REC_STATE(R))) begin
                if (DO_TOPPLE)
                    HIT = MAKE_REC(REC_X(R), REC_Y(R), HX, HY, `PS_FALLING, FALL_DIR, FALL_TICKS);
                else
                    HIT = MAKE_REC(REC_X(R), REC_Y(R), 20'sd0, 20'sd0, `PS_WOBBLING, REC_DIR(R), WOB_T);
            end
            else if (REC_STATE(R) != `PS_OFF)
                HIT = MAKE_REC(REC_X(R), REC_Y(R), REC_VX(R) + HX, REC_VY(R) + HY,
                               REC_STATE(R), REC_DIR(R), REC_TIMER(R));
        end
    endfunction

    // move a pin's record by (OX, OY) 1/64 in (if EN)
    function [98:0] MOVE;
        input [98:0] R;
        input signed [19:0] OX, OY;
        input        EN;
        begin
            MOVE = R;
            if (EN)
                MOVE = MAKE_REC(REC_X(R) + {OX[15:0], 6'd0}, REC_Y(R) + {OY[15:0], 6'd0},
                                REC_VX(R), REC_VY(R), REC_STATE(R), REC_DIR(R), REC_TIMER(R));
        end
    endfunction

    // fall time: 150 ticks, shorter for a harder push (down to 60)
    function [8:0] CALC_FALL_TIME;
        input [20:0] NRM;
        reg [20:0] EX;
        begin
            EX = (NRM > {1'b0, TOPPLE_P}) ? (NRM - {1'b0, TOPPLE_P}) >> 8 : 21'd0;
            CALC_FALL_TIME = (EX > 21'd90) ? FALL_T - 9'd90 : FALL_T - EX[8:0];
        end
    endfunction

    // One tick of a pin on its own, in two clocked halves.
    // UPDATE_1: timers, move, friction. Result {moving, mx[22:0], my[22:0],
    //   wx[19:0], wy[19:0], s, d, t}, or {3'b000, new record} if not sliding.
    function [101:0] UPDATE_1;
        input [98:0] R;
        reg signed [22:0] MX, MY;
        reg signed [19:0] WX, WY;
        reg [19:0] AX, AY;
        reg [2:0]  S;
        reg [8:0]  T;
        begin
            UPDATE_1 = {3'b000, R};
            S = REC_STATE(R);
            T = REC_TIMER(R);
            if (S == `PS_WOBBLING) begin
                UPDATE_1 = {3'b000, MAKE_REC(REC_X(R), REC_Y(R), REC_VX(R), REC_VY(R),
                                             (T == 0) ? `PS_STANDING : S, REC_DIR(R), T - 9'd1)};
            end
            else if (S == `PS_FALLING || S == `PS_DOWN) begin
                if (S == `PS_FALLING) begin
                    if (T == 0)
                        S = `PS_DOWN;
                    T = T - 9'd1;
                end
                MX = $signed({1'b0, REC_X(R)}) + (REC_VX(R) >>> 4);
                MY = $signed({1'b0, REC_Y(R)}) + (REC_VY(R) >>> 4);
                WX = REC_VX(R) - (REC_VX(R) >>> FRIC_SH);
                WY = REC_VY(R) - (REC_VY(R) >>> FRIC_SH);
                AX = WX[19] ? -WX : WX;
                AY = WY[19] ? -WY : WY;
                if (AX < STOP_V)
                    WX = 0;
                if (AY < STOP_V)
                    WY = 0;
                UPDATE_1 = {1'b1, MX, MY, WX, WY, S, REC_DIR(R), T};
            end
        end
    endfunction

    // UPDATE_2: gutter (a slow pin past the lane edge stays in it), kickback
    //   walls (bounce back with e = 0.75), back of the deck, pit.
    function [98:0] UPDATE_2;
        input [101:0] P;
        reg signed [22:0] MX, MY;
        reg signed [19:0] WX, WY;
        reg [19:0] AX;
        reg [21:0] NEW_X, NEW_Y;
        reg [2:0]  S, D;
        reg [8:0]  T;
        begin
            if (!P[101])
                UPDATE_2 = P[98:0];
            else begin
                MX = P[100:78];
                MY = P[77:55];
                WX = P[54:35];
                WY = P[34:15];
                S  = P[14:12];
                D  = P[11:9];
                T  = P[8:0];
                AX = WX[19] ? -WX : WX;
                NEW_X = MX[21:0];
                NEW_Y = MY[21:0];
                if ((MX < $signed({1'b0, LANE_L}) || MX > $signed({1'b0, LANE_R})) &&
                    AX < GUT_V && S != `PS_FALLING) begin
                    NEW_X = (MX < $signed({1'b0, LANE_L})) ? GUT_LX : GUT_RX;
                    WX = 0;
                end
                else if (MX < $signed({1'b0, KICK_L})) begin
                    NEW_X = KICK_L;
                    WX = -(WX - (WX >>> 2));
                end
                else if (MX > $signed({1'b0, KICK_R})) begin
                    NEW_X = KICK_R;
                    WX = -(WX - (WX >>> 2));
                end
                if (MY < $signed({1'b0, BACK_Y})) begin
                    NEW_Y = BACK_Y;
                    WY = -(WY >>> 1);
                end
                if (MY > $signed({1'b0, PIT_Y})) begin
                    S = `PS_OFF;
                    WX = 0;
                    WY = 0;
                end
                UPDATE_2 = MAKE_REC(NEW_X, NEW_Y, WX, WY, S, D, T);
            end
        end
    endfunction

    // ---------- 5. Read port for B, status buses ----------
    wire [98:0]        READ_REC = rec[pin_rd_idx];
    wire signed [16:0] READ_CX  = CIRCLE(READ_REC, 1'b0, 1'b0);
    wire signed [16:0] READ_CY  = CIRCLE(READ_REC, 1'b1, 1'b0);
    assign pin_rd_x       = READ_CX[15:0];
    assign pin_rd_y       = READ_CY[15:0];
    assign pin_rd_vx      = READ_REC[54:39];
    assign pin_rd_vy      = READ_REC[34:19];
    assign pin_rd_solid   = (REC_STATE(READ_REC) != `PS_OFF);
    assign pin_rd_upright = IS_UPRIGHT(REC_STATE(READ_REC));

    genvar g;
    generate
        for (g = 0; g < 10; g = g + 1) begin : g_vis
            wire [98:0] PIN_REC   = rec[g];
            wire [2:0]  PIN_STATE = REC_STATE(PIN_REC);
            wire [8:0]  PIN_TIMER = REC_TIMER(PIN_REC);
            // fall animation stage: 0 upright, 1 half-way, 2 down
            wire [1:0]  STAGE = (PIN_STATE == `PS_DOWN)    ? 2'd2 :
                                (PIN_STATE != `PS_FALLING) ? 2'd0 :
                                (PIN_TIMER > 9'd100)       ? 2'd0 :
                                (PIN_TIMER > 9'd50)        ? 2'd1 :
                                                             2'd2;
            // a lying pin is reported at the centre of its body (7.5 in from
            // the base, half while falling), where both views draw it
            wire        LYING = (PIN_STATE == `PS_FALLING) || (PIN_STATE == `PS_DOWN);
            wire [9:0]  OFF_S = (PIN_STATE == `PS_FALLING) ? 10'd240 : 10'd480;
            wire [9:0]  OFF_G = (PIN_STATE == `PS_FALLING) ? 10'd170 : 10'd339;
            wire [15:0] VIS_X = REC_PX(PIN_REC) + (LYING ? BODY_OFF(REC_DIR(PIN_REC), 1'b0, OFF_S, OFF_G) : 16'd0);
            wire [15:0] VIS_Y = REC_PY(PIN_REC) + (LYING ? BODY_OFF(REC_DIR(PIN_REC), 1'b1, OFF_S, OFF_G) : 16'd0);
            wire [5:0]  VIS_X6 = VIS_X[15]            ? 6'd0  :
                                 (VIS_X[15:6] > 10'd63) ? 6'd63 :
                                                          VIS_X[11:6];
            assign pin_vis[24*g +: 24] = {VIS_X6, VIS_Y[15:6], PIN_STATE, REC_DIR(PIN_REC), STAGE};   // whole inches
            assign standing[g] = IS_UPRIGHT(PIN_STATE);
            assign busy[g] = (PIN_STATE == `PS_WOBBLING) || (PIN_STATE == `PS_FALLING) ||
                             ((PIN_STATE == `PS_DOWN) && (REC_VX(PIN_REC) != 0 || REC_VY(PIN_REC) != 0));
        end
    endgenerate

    // ---------- 6. FSM states (numbers fixed: tb_physics watches S_PN = 22) ----------
    localparam S_IDLE  = 6'd0,  S_UPD   = 6'd1,  S_RAKE  = 6'd16, S_PLACE = 6'd17,
               S_IMP1  = 6'd18, S_IMP1B = 6'd26, S_IMP2  = 6'd19,                    // ball impulse
               S_PA    = 6'd2,  S_PA2   = 6'd20, S_PA4   = 6'd27, S_PA3   = 6'd21,   // read the pair, reject
               S_PB    = 6'd3,  S_PC    = 6'd4,  S_PD    = 6'd5,  S_PD2   = 6'd28,   // |d|^2, overlap?
               S_PE    = 6'd6,  S_PF    = 6'd7,  S_PG    = 6'd8,                     // normal n
               S_PH    = 6'd9,  S_PI    = 6'd10, S_PJ0   = 6'd29,                    // (v_i - v_j).n
               S_PJ1   = 6'd30, S_PJ2   = 6'd31, S_PJ3   = 6'd32, S_PJ4   = 6'd33,
               S_PJ5   = 6'd34, S_PJ6   = 6'd35,                                     // push-out vector
               S_PJ    = 6'd11, S_PK    = 6'd12, S_PL    = 6'd13, S_PM    = 6'd14,   // dv
               S_PQ    = 6'd24, S_PQ2   = 6'd25, S_PN    = 6'd22, S_PW    = 6'd23,   // topple?, write
               S_PNEXT = 6'd15;
    reg [5:0] st;
    reg [1:0] CIRCLE_PAIR;                   // {circle of pin i, circle of pin j}
    reg       PAIR_REVERSE;                  // this tick walks the pairs 44 -> 0
    reg       RACK_RUN;
    reg [3:0] STEP_COUNT;                    // pin being updated / rake tick count
    reg [5:0] PAIR_INDEX;
    reg [1:0] RACK_CMD_RUN;
    reg [9:0] RACK_MASK_RUN;

    // ---------- 7. Shared multiplier (MUL_P = MUL_A * MUL_B, two clocks later) ----------
    reg  signed [24:0] MUL_A;
    reg  signed [17:0] MUL_B;
    wire signed [42:0] MUL_P;
    mul_s25x18 multiplier_module (.clk(clk), .a(MUL_A), .b(MUL_B), .p(MUL_P));

    // ---------- 8. Registered read ports ----------
    reg  [3:0]  INDEX_A, INDEX_B;
    reg  [3:0]  INDEX_A_DELAY;               // INDEX_A one clock later (the index of rA)
    reg  [98:0] rA, rB;
    always @ (posedge clk) begin
        rA <= rec[INDEX_A];
        rB <= rec[INDEX_B];
        INDEX_A_DELAY <= INDEX_A;
    end
    wire [3:0] PAIR_I = PAIR_ROM[PAIR_INDEX][7:4];
    wire [3:0] PAIR_J = PAIR_ROM[PAIR_INDEX][3:0];

    // ---------- 9. Pair test ----------
    reg  signed [16:0] CIRCLE_AX, CIRCLE_AY, CIRCLE_BX, CIRCLE_BY;   // one clock after rA / rB
    always @ (posedge clk) begin
        CIRCLE_AX <= CIRCLE(rA, 1'b0, CIRCLE_PAIR[1]);
        CIRCLE_AY <= CIRCLE(rA, 1'b1, CIRCLE_PAIR[1]);
        CIRCLE_BX <= CIRCLE(rB, 1'b0, CIRCLE_PAIR[0]);
        CIRCLE_BY <= CIRCLE(rB, 1'b1, CIRCLE_PAIR[0]);
    end
    wire signed [17:0] CIRCLE_DX = {CIRCLE_BX[16], CIRCLE_BX} - {CIRCLE_AX[16], CIRCLE_AX};
    wire signed [17:0] CIRCLE_DY = {CIRCLE_BY[16], CIRCLE_BY} - {CIRCLE_AY[16], CIRCLE_AY};
    wire [17:0]        ABS_DX    = CIRCLE_DX[17] ? -CIRCLE_DX : CIRCLE_DX;
    wire [17:0]        ABS_DY    = CIRCLE_DY[17] ? -CIRCLE_DY : CIRCLE_DY;
    wire signed [16:0] DIFF_X    = CIRCLE_DX[16:0];                 // enough within NEAR
    wire signed [16:0] DIFF_Y    = CIRCLE_DY[16:0];
    wire UPRIGHT_A = IS_UPRIGHT(REC_STATE(rA));
    wire UPRIGHT_B = IS_UPRIGHT(REC_STATE(rB));
    // the pins cannot touch: one is off, both stand, or their bases are more
    // than 30 in apart (11.5 + 11.5 in of body + 6 in of radii + 1)
    wire signed [16:0] BASE_DX = $signed({1'b0, REC_PX(rB)}) - $signed({1'b0, REC_PX(rA)});
    wire signed [16:0] BASE_DY = $signed({1'b0, REC_PY(rB)}) - $signed({1'b0, REC_PY(rA)});
    wire [16:0] ABS_BASE_DX = BASE_DX[16] ? -BASE_DX : BASE_DX;
    wire [16:0] ABS_BASE_DY = BASE_DY[16] ? -BASE_DY : BASE_DY;
    wire PAIR_NONE = (REC_STATE(rA) == `PS_OFF) || (REC_STATE(rB) == `PS_OFF) ||
                     (UPRIGHT_A && UPRIGHT_B) ||
                     ABS_BASE_DX > 17'd1920 || ABS_BASE_DY > 17'd1920;
    // this circle pair cannot touch: a standing pin has only circle 0, or far apart
    wire SKIP_CIRCLE = (CIRCLE_PAIR[1] && UPRIGHT_A) || (CIRCLE_PAIR[0] && UPRIGHT_B) ||
                       ABS_DX > NEAR || ABS_DY > NEAR;
    // the belly circle of a lying pin is the big one
    wire BIG_A = !CIRCLE_PAIR[1] && !UPRIGHT_A;
    wire BIG_B = !CIRCLE_PAIR[0] && !UPRIGHT_B;

    reg               PAIR_NONE_Q;
    reg signed [16:0] DX, DY;
    reg [35:0]        D2, D2_SAVED;          // |d|^2
    reg [35:0]        R2_PAIR;               // (radius A + radius B)^2
    reg [9:0]         R_SUM;                 // radius A + radius B
    reg               LYING_A, LYING_B;      // only lying pins are pushed out
    reg [17:0]        INV_LEN;               // 2^14 / |d|
    reg signed [17:0] NX, NY;                // unit normal, Q.14
    reg signed [42:0] VDOT;                  // (vx_i - vx_j) * nx
    reg signed [24:0] VREL_N;                // (v_i - v_j).n, Q3.16
    reg               APPROACHING;
    reg signed [17:0] DIST, PUSH;            // |d|, push-out distance (1/64 in)
    reg signed [19:0] PUSH_X, PUSH_Y;        // push-out vector (1/64 in)
    reg signed [24:0] DV_LEN;
    reg signed [19:0] DVX, DVY, NDVX, NDVY;
    reg [19:0]        ABS_DVX, ABS_DVY;
    reg               TOPPLE;
    reg [8:0]         FALL_TICKS;
    reg [2:0]         DIR_POS, DIR_NEG;      // fall direction for +dv / -dv
    reg [101:0]       HALF_UPDATE;           // first half of a pin update
    reg [3:0]         HALF_INDEX;

    wire [35:0]        D2_SUM      = D2 + MUL_P[35:0];
    wire signed [42:0] VREL_N_FULL = (VDOT + MUL_P) >>> 14;
    wire signed [24:0] DV_CALC     = VREL_N - (VREL_N >>> DL_S1) - (VREL_N >>> DL_S2);
    wire [20:0]        DV_NORM     = (ABS_DVX > ABS_DVY) ? ABS_DVX + (ABS_DVY >> 1) :      // ~|dv|
                                                           ABS_DVY + (ABS_DVX >> 1);
    wire signed [17:0] OVERLAP_RAW = $signed({8'd0, R_SUM}) - DIST;
    wire signed [17:0] OVERLAP     = (OVERLAP_RAW < 0) ? 18'sd0 : OVERLAP_RAW;

    // ---------- 10. Requests remembered until the FSM takes them ----------
    reg               IMPULSE_PENDING, SCAN_PENDING;
    reg [3:0]         IMP_PIN;
    reg signed [19:0] IMP_VX, IMP_VY;        // Q3.16
    reg               RACK_PENDING, FORCE_PENDING;
    reg [1:0]         RACK_CMD_SAVED;
    reg [9:0]         RACK_MASK_SAVED;

    always @ (posedge clk) begin
        if (rst) begin
            RACK_PENDING <= 1'b0;
            RACK_CMD_SAVED <= `RK_FULL;
            RACK_MASK_SAVED <= 10'h3FF;
        end
        else if (rack_go) begin
            RACK_PENDING <= 1'b1;
            RACK_CMD_SAVED <= rack_cmd;
            RACK_MASK_SAVED <= rack_mask;
        end
        else if (st == S_IDLE)
            RACK_PENDING <= 1'b0;
    end
    assign rack_busy = RACK_RUN | RACK_PENDING | rack_go;

    // ---------- 11. Registered write ports and whole-rack operations ----------
    reg        WRITE_A, WRITE_B;
    reg [3:0]  ADDR_A, ADDR_B;
    reg [98:0] nA, nB;

    localparam B_NONE = 2'd0, B_FORCE = 2'd1, B_RAKE = 2'd2, B_PLACE = 2'd3;
    reg [1:0] BULK;
    always @ (*) begin
        BULK = B_NONE;
        if (st == S_IDLE && FORCE_PENDING && !IMPULSE_PENDING)
            BULK = B_FORCE;
        else if (st == S_RAKE && tick_phys)
            BULK = B_RAKE;
        else if (st == S_PLACE)
            BULK = B_PLACE;
    end

    always @ (posedge clk) begin
        if (rst)
            FORCE_PENDING <= 1'b0;
        else if (force_settle)
            FORCE_PENDING <= 1'b1;
        else if (BULK == B_FORCE)
            FORCE_PENDING <= 1'b0;
    end

    function [98:0] BULK_OP;
        input [98:0] R;
        input [1:0]  OP;
        input [31:0] SPOT;
        input        KEEP;
        input [9:0]  RAKE;
        begin
            BULK_OP = R;
            case (OP)
                B_FORCE:                                             // timeout: finish every animation
                    if (REC_STATE(R) == `PS_WOBBLING)
                        BULK_OP = MAKE_REC(REC_X(R), REC_Y(R), 20'sd0, 20'sd0, `PS_STANDING, REC_DIR(R), 9'd0);
                    else if (REC_STATE(R) == `PS_FALLING || REC_STATE(R) == `PS_DOWN)
                        BULK_OP = MAKE_REC(REC_X(R), REC_Y(R), 20'sd0, 20'sd0, `PS_DOWN, REC_DIR(R), 9'd0);
                B_RAKE:                                              // the rake pushes fallen pins ahead of it
                    if (!IS_UPRIGHT(REC_STATE(R)) && REC_STATE(R) != `PS_OFF && R[76:67] < RAKE)
                        BULK_OP = MAKE_REC(REC_X(R), {RAKE, 12'd0}, 20'sd0, 20'sd0, `PS_DOWN, REC_DIR(R), 9'd0);
                B_PLACE:                                             // set the kept pins on their spots
                    if (KEEP)
                        BULK_OP = MAKE_REC({SPOT[31:16], 6'd0}, {SPOT[15:0], 6'd0}, 20'sd0, 20'sd0,
                                           `PS_STANDING, 3'd0, 9'd0);
                    else
                        BULK_OP = MAKE_REC(REC_X(R), REC_Y(R), 20'sd0, 20'sd0, `PS_OFF, 3'd0, 9'd0);
                default: ;
            endcase
        end
    endfunction

    // ---------- 12. The register file: 4-input mux per record ----------
    integer k;
    always @ (posedge clk) begin
        for (k = 0; k < 10; k = k + 1) begin
            if (rst)
                rec[k] <= MAKE_REC({SPOT_ROM[k][31:16], 6'd0}, {SPOT_ROM[k][15:0], 6'd0},
                                   20'sd0, 20'sd0, `PS_STANDING, 3'd0, 9'd0);
            else if (WRITE_A && ADDR_A == k)
                rec[k] <= nA;
            else if (WRITE_B && ADDR_B == k)
                rec[k] <= nB;
            else if (BULK != B_NONE)
                rec[k] <= BULK_OP(rec[k], BULK, SPOT_ROM[k],
                                  (RACK_CMD_RUN == `RK_FULL) ||
                                  (RACK_CMD_RUN == `RK_LEAVE && RACK_MASK_RUN[k]) ||
                                  (RACK_CMD_RUN == `RK_SWEEP && IS_UPRIGHT(REC_STATE(rec[k]))),
                                  rake_y);
        end
    end

    // ---------- 13. Control FSM ----------
    always @ (posedge clk) begin
        WRITE_A <= 1'b0;
        WRITE_B <= 1'b0;
        if (rst) begin
            st <= S_IDLE; STEP_COUNT <= 0; PAIR_INDEX <= 0; RACK_CMD_RUN <= `RK_FULL; RACK_MASK_RUN <= 10'h3FF;
            RACK_RUN <= 1'b0; rake_y <= 10'd0; INDEX_A <= 0; INDEX_B <= 0;
            ADDR_A <= 0; ADDR_B <= 0; nA <= 0; nB <= 0;
            MUL_A <= 0; MUL_B <= 0; DX <= 0; DY <= 0; D2 <= 0; NX <= 0; NY <= 0; VDOT <= 0; DV_LEN <= 0;
            DVX <= 0; DVY <= 0; NDVX <= 0; NDVY <= 0;
            TOPPLE <= 0; DIR_POS <= 0; DIR_NEG <= 0; FALL_TICKS <= FALL_T; PAIR_REVERSE <= 1'b0;
            IMPULSE_PENDING <= 0; SCAN_PENDING <= 0; IMP_PIN <= 0; IMP_VX <= 0; IMP_VY <= 0;
            CIRCLE_PAIR <= 2'd0; R2_PAIR <= R2_BB; R_SUM <= 2 * R_SML;
            DIST <= 0; PUSH <= 0; PUSH_X <= 0; PUSH_Y <= 0;
            LYING_A <= 0; LYING_B <= 0; PAIR_NONE_Q <= 1'b1;
        end
        else begin
            if (impulse_valid) begin
                IMPULSE_PENDING <= 1'b1;
                IMP_PIN <= impulse_pin;
                IMP_VX <= {impulse_vx, 4'd0};                    // Q3.12 -> Q3.16
                IMP_VY <= {impulse_vy, 4'd0};
            end
            if (scan_done)
                SCAN_PENDING <= 1'b1;

            case (st)
                S_IDLE: begin
                    if (RACK_PENDING) begin
                        RACK_CMD_RUN <= RACK_CMD_SAVED;
                        RACK_MASK_RUN <= RACK_MASK_SAVED;
                        RACK_RUN <= 1'b1;
                        rake_y <= 10'd700;
                        STEP_COUNT <= 4'd0;
                        st <= S_RAKE;
                    end
                    else if (IMPULSE_PENDING && !impulse_valid) begin
                        INDEX_A <= IMP_PIN;
                        st <= S_IMP1;
                    end
                    else if (SCAN_PENDING && !IMPULSE_PENDING && !impulse_valid) begin
                        SCAN_PENDING <= 1'b0;
                        STEP_COUNT <= 4'd0;
                        st <= S_UPD;
                    end
                end

                // ---- ball impulse ----
                S_IMP1: begin
                    ABS_DVX <= IMP_VX[19] ? -IMP_VX : IMP_VX;
                    ABS_DVY <= IMP_VY[19] ? -IMP_VY : IMP_VY;
                    st <= S_IMP1B;
                end
                S_IMP1B: begin                                     // topple? which way? how fast?
                    TOPPLE <= DV_NORM > TOPPLE_P;
                    FALL_TICKS <= CALC_FALL_TIME(DV_NORM);
                    DIR_POS <= DIR8(IMP_VX, IMP_VY);
                    st <= S_IMP2;
                end
                S_IMP2: begin
                    WRITE_A <= 1'b1;
                    ADDR_A <= INDEX_A_DELAY;
                    nA <= HIT(rA, IMP_VX, IMP_VY, TOPPLE, DIR_POS, FALL_TICKS);
                    IMPULSE_PENDING <= impulse_valid;
                    st <= S_IDLE;
                end

                // ---- 1. per-pin update, pipelined: issue j, read j+1, half j+2, write j+3 ----
                S_UPD: begin
                    if (STEP_COUNT <= 4'd9)
                        INDEX_A <= STEP_COUNT;
                    if (STEP_COUNT >= 4'd2 && STEP_COUNT <= 4'd11) begin
                        HALF_UPDATE <= UPDATE_1(rA);
                        HALF_INDEX <= INDEX_A_DELAY;
                    end
                    if (STEP_COUNT >= 4'd3) begin
                        WRITE_A <= 1'b1;
                        ADDR_A <= HALF_INDEX;
                        nA <= UPDATE_2(HALF_UPDATE);
                    end
                    if (STEP_COUNT == 4'd12) begin
                        PAIR_INDEX <= PAIR_REVERSE ? 6'd44 : 6'd0;
                        st <= S_PA;
                    end
                    else
                        STEP_COUNT <= STEP_COUNT + 4'd1;
                end

                // ---- 2. pairs ----
                S_PA: begin
                    INDEX_A <= PAIR_I;
                    INDEX_B <= PAIR_J;
                    st <= S_PA2;
                end
                S_PA2: st <= S_PA4;                                // rA, rB load
                S_PA4: st <= S_PA3;                                // circle centres load
                S_PA3: begin
                    DX <= DIFF_X;
                    DY <= DIFF_Y;
                    R2_PAIR <= (BIG_A && BIG_B) ? R2_BB : (BIG_A || BIG_B) ? R2_BS : R2_SS;
                    R_SUM <= (BIG_A ? R_BIG : R_SML) + (BIG_B ? R_BIG : R_SML);
                    LYING_A <= !UPRIGHT_A;
                    LYING_B <= !UPRIGHT_B;
                    PAIR_NONE_Q <= PAIR_NONE;
                    if (SKIP_CIRCLE || PAIR_NONE)
                        st <= S_PNEXT;
                    else begin
                        MUL_A <= DIFF_X;
                        MUL_B <= DIFF_X;
                        st <= S_PB;
                    end
                end
                S_PB:  begin MUL_A <= DY; MUL_B <= DY; st <= S_PC; end
                S_PC:  begin D2 <= MUL_P[35:0]; st <= S_PD; end
                S_PD:  begin D2_SAVED <= D2_SUM; st <= S_PD2; end
                S_PD2: begin
                    if (D2_SAVED < R2_PAIR) begin                  // overlap: n = d / |d|
                        INV_LEN <= {9'd0, INV_ROM[D2_SAVED[18:12]]};
                        MUL_A <= DX;
                        MUL_B <= {9'd0, INV_ROM[D2_SAVED[18:12]]};
                        st <= S_PE;
                    end
                    else
                        st <= S_PNEXT;
                end
                S_PE:  begin MUL_A <= DY; MUL_B <= INV_LEN; st <= S_PF; end
                S_PF:  begin NX <= MUL_P[17:0]; st <= S_PG; end
                S_PG:  begin NY <= MUL_P[17:0]; MUL_A <= REC_VX(rA) - REC_VX(rB); MUL_B <= NX; st <= S_PH; end
                S_PH:  begin MUL_A <= REC_VY(rA) - REC_VY(rB); MUL_B <= NY; st <= S_PI; end
                S_PI:  begin VDOT <= MUL_P; MUL_A <= D2_SAVED[24:0]; MUL_B <= INV_LEN; st <= S_PJ0; end   // |d| = d^2 / |d|
                S_PJ0: begin VREL_N <= VREL_N_FULL[24:0]; APPROACHING <= (VREL_N_FULL > 0); st <= S_PJ1; end
                S_PJ1: begin DIST <= MUL_P >>> 14; st <= S_PJ2; end
                S_PJ2: begin                                       // whole overlap (+1/64), shared if both lie
                    PUSH <= (LYING_A && LYING_B) ? (OVERLAP >>> 1) + 18'sd1 : OVERLAP + 18'sd1;
                    st <= S_PJ3;
                end
                S_PJ3: begin MUL_A <= PUSH; MUL_B <= NX; st <= S_PJ4; end
                S_PJ4: begin MUL_A <= PUSH; MUL_B <= NY; st <= S_PJ5; end
                S_PJ5: begin PUSH_X <= MUL_P >>> 14; st <= S_PJ6; end
                S_PJ6: begin PUSH_Y <= MUL_P >>> 14; st <= S_PJ; end
                S_PJ: begin
                    if (APPROACHING) begin
                        DV_LEN <= DV_CALC;
                        MUL_A <= DV_CALC;
                        MUL_B <= NX;
                        st <= S_PK;
                    end
                    else begin                                     // touching, not approaching: only push apart
                        WRITE_A <= LYING_A;
                        ADDR_A <= INDEX_A;
                        nA <= MOVE(rA, -PUSH_X, -PUSH_Y, 1'b1);
                        WRITE_B <= LYING_B;
                        ADDR_B <= INDEX_B;
                        nB <= MOVE(rB, PUSH_X, PUSH_Y, 1'b1);
                        st <= S_PW;
                    end
                end
                S_PK:  begin MUL_A <= DV_LEN; MUL_B <= NY; st <= S_PL; end
                S_PL:  begin DVX <= MUL_P >>> 14; st <= S_PM; end
                S_PM:  begin DVY <= MUL_P >>> 14; st <= S_PQ; end
                S_PQ: begin
                    NDVX <= -DVX;
                    NDVY <= -DVY;
                    ABS_DVX <= DVX[19] ? -DVX : DVX;
                    ABS_DVY <= DVY[19] ? -DVY : DVY;
                    st <= S_PQ2;
                end
                S_PQ2: begin                                       // topple? (a head hit needs a quarter)
                    TOPPLE <= (CIRCLE_PAIR != 2'd0) ? (DV_NORM > (TOPPLE_P >> 2)) : (DV_NORM > TOPPLE_P);
                    FALL_TICKS <= CALC_FALL_TIME(DV_NORM);
                    DIR_POS <= DIR8(DVX, DVY);
                    DIR_NEG <= DIR8(NDVX, NDVY);
                    st <= S_PN;
                end
                S_PN: begin                                        // pin i loses dv along n, pin j gains it, plus push-out
                    WRITE_A <= 1'b1;
                    ADDR_A <= INDEX_A;
                    nA <= MOVE(HIT(rA, NDVX, NDVY, TOPPLE, DIR_NEG, FALL_TICKS), -PUSH_X, -PUSH_Y, LYING_A);
                    WRITE_B <= 1'b1;
                    ADDR_B <= INDEX_B;
                    nB <= MOVE(HIT(rB, DVX, DVY, TOPPLE, DIR_POS, FALL_TICKS), PUSH_X, PUSH_Y, LYING_B);
                    st <= S_PW;
                end
                S_PW: st <= S_PNEXT;                               // the write lands now

                // next circle pair of the same two pins (only lying pins
                // have circle 1), else the next pin pair
                S_PNEXT: begin
                    if (!PAIR_NONE_Q && CIRCLE_PAIR == 2'd0 && (LYING_A || LYING_B)) begin
                        CIRCLE_PAIR <= LYING_B ? 2'd1 : 2'd2;
                        st <= S_PA;
                    end
                    else if (!PAIR_NONE_Q && CIRCLE_PAIR == 2'd1 && LYING_A) begin
                        CIRCLE_PAIR <= 2'd2;
                        st <= S_PA;
                    end
                    else if (!PAIR_NONE_Q && CIRCLE_PAIR == 2'd2 && LYING_B) begin
                        CIRCLE_PAIR <= 2'd3;
                        st <= S_PA;
                    end
                    else if (PAIR_INDEX == (PAIR_REVERSE ? 6'd0 : 6'd44)) begin
                        CIRCLE_PAIR <= 2'd0;
                        PAIR_REVERSE <= ~PAIR_REVERSE;
                        st <= S_IDLE;
                    end
                    else begin
                        CIRCLE_PAIR <= 2'd0;
                        PAIR_INDEX <= PAIR_REVERSE ? PAIR_INDEX - 6'd1 : PAIR_INDEX + 6'd1;
                        st <= S_PA;
                    end
                end

                // ---- rake: 1/8 in per tick (0.55 s for 70 in), then place the pins ----
                S_RAKE: begin
                    if (tick_phys) begin
                        if (STEP_COUNT[2:0] == 3'd7)
                            rake_y <= rake_y + 10'd1;
                        STEP_COUNT <= STEP_COUNT + 4'd1;
                        if (rake_y == 10'd770) begin
                            STEP_COUNT <= 4'd0;
                            st <= S_PLACE;
                        end
                    end
                end
                S_PLACE: begin
                    rake_y <= 10'd0;
                    RACK_RUN <= 1'b0;
                    st <= S_IDLE;
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
