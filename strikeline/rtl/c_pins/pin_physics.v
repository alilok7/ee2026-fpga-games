`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// pin_physics.v : 10 pins, wobble/topple, pin-pin collisions, pin-setter
//-----------------------------------------------------------------------------
// Owner   : Student C
// Fixed point: position unsigned Q10.12 inches (22 bit), velocity signed
//              Q3.16 in/tick (20 bit). Exported as POS Q10.6 / VEL Q3.12.
//              Q3.16 because the friction step v -= v/256 must keep working
//              down to a slow slide (in Q3.12 it would stall at 0.06 in/tick).
// Per physics tick, AFTER B's ball scan (scan_done):
//   1. UPDATE every pin (one per clock):
//        WOBBLING counts down 0.4 s, then STANDING again (a "wobbler")
//        FALLING  counts down 0.15 s (fall animation), then DOWN
//        FALLING/DOWN slide: x += v, v -= v >> 8 (friction), tiny v -> 0,
//        kickback walls reflect with half speed, past the deck end -> OFF
//   2. PAIRS: a pair-iterator FSM walks all 45 pairs from a pair ROM.
//        Overlap test with squared distances (see contact distances below), normal from a
//        constant reciprocal, equal-mass collision ALONG THE NORMAL:
//          dv = (1+e)/2 * (v_i - v_j).n,  v_i -= dv n,  v_j += dv n
//        with e = 0.625, so (1+e)/2 = 0.8125 = 1 - 1/8 - 1/16 (shift-add).
//        A standing pin hit harder than TOPPLE starts FALLING in the push
//        direction; a softer hit only makes it wobble (its base friction
//        absorbs the push).
//        Overlapping pins that are not approaching are pushed apart by
//        1/64 in per tick, so pins can never lock together.
//   Ball impulses (from B) arrive while this FSM is idle and are applied
//   at once with the same topple rule.
// v3 (advanced pin action):
//   - a lying pin collides where its body is: its collision circle sits 5 in
//     along its fall direction (2.5 in while still falling), for B's ball
//     scan (read port) and for the pairs
//   - a harder push makes a pin fall faster (fall time 150 -> 60 ticks)
//   - a slow pin that slides off the lane edge drops into the gutter and
//     stays there; a fast one reaches the kickback, which now returns it
//     livelier (e = 0.75 instead of 0.5)
//   - the 45 pairs are walked forward and backward on alternate ticks, so
//     the left and right sides of the rack are treated alike
// v3.4 (footprint): pin vs pin, a lying pin is TWO circles along its body,
//     matching the 15 in pin that is drawn: the belly at 5 in from the base
//     (radius 3.5 in, see R_BIG) and the neck / head at 11.5 in (2.4 in; a
//     head hit tips a standing pin with a quarter of the push); half
//     those offsets while it is still falling. A standing pin is one 2.4 in
//     circle. Each pair tests every circle of one pin against every circle
//     of the other (up to 4 tests). When two circles overlap, the lying
//     pin(s) are moved apart by the WHOLE overlap in the same tick (+1/64 in;
//     shared half / half when both lie; a standing pin never slides), so pins
//     can no longer sit inside each other. pin_vis now reports a lying pin at
//     the centre of its body (7.5 in from the base), where both views draw it.
//     (B's ball still sees one circle, as tuned in v3.)
// Structure: the 10 pin records are written through exactly TWO write ports
//   (A, B: at most two pins change per clock) plus whole-rack operations
//   (rake, placement, settle timeout), so each record bit has a 4-input mux.
// Cycle budget: update 10 + pairs 45 x 4 (far) .. 45 x 17 (all touching)
//   = at most ~800 clocks of the 97 656 in a tick.
// Rack commands (D): every command first runs the rake (0.55 s sweep that
//   pushes fallen pins into the pit), then FULL = 10 pins on their spots,
//   SWEEP = keep only the standing pins, LEAVE = exactly rack_mask.
//=============================================================================
module pin_physics #(
    // ---- tuning knobs (feel), defaults = the tuned values, see C_DESIGN.md ----
    parameter [15:0] R_DOWN   = 16'd224,          // footprint of a lying pin, 1/64 in (3.5 in)
    parameter [19:0] TOPPLE_P = 20'd2200,         // push that tips a standing pin, Q3.16 (~0.034 in/tick, 2 mph)
    parameter        FRIC_SH  = 8,                // sliding friction: v -= v >> FRIC_SH per tick
    parameter        DL_S1    = 3,                // (1+e)/2 = 1 - 2^-DL_S1 - 2^-DL_S2 (e = 0.625)
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
    localparam [8:0]  WOB_T = 9'd410, FALL_T = 9'd150;
    // Contact distance of a pair. A standing pin is a 2.4 in circle, but a
    // falling / fallen pin is 15 in long and sweeps a much bigger area, so
    // it collides as a 4.0 in circle ("messenger" pins carry the action).
    //   upright + fallen : 6.4 in      fallen + fallen : 8.0 in
    // v3.4 circle radii (1/64 in): a standing pin and the head of a lying pin
    // 2.4 in (the pin's real belly radius); the belly of a lying pin keeps
    // v3's tuned "messenger" circle: 3.5 in at 5 in from the base.
    // (Tried and measured with tb_carry: true-size 2.4 / 3.0 in bellies at
    //  4.5 in -> 0 strikes from 8 pocket hits: in this flat 2-D model the
    //  messenger pins must reach their neighbours as in v3.)
    localparam [9:0]  R_BIG = 10'd224, R_SML = 10'd154;
    localparam [16:0] NEAR    = 17'd512;                           // 2 x 3.5 in + 1 in quick reject
    localparam [35:0] R2_BB   = 36'd200704;                        // (3.5 + 3.5 in)^2
    localparam [35:0] R2_BS   = 36'd142884;                        // (3.5 + 2.4 in)^2
    localparam [35:0] R2_SS   = 36'd94864;                         // (2.4 + 2.4 in)^2
    localparam [19:0] TOPPLE  = TOPPLE_P;
    // below this a slide stops. Must be >= 2^FRIC_SH: for smaller v the
    // friction step v >> FRIC_SH is 0 and a pin would slide forever (tb_top)
    localparam [19:0] STOP_V   = (20'd1 << FRIC_SH) + 20'd64;
    localparam [21:0] KICK_L = {`W_KICK_L, 6'd0}, KICK_R = {`W_KICK_R, 6'd0};
    localparam [21:0] BACK_Y = 22'd2867200;           // 700 in: pins cannot slide back further
    localparam [21:0] PIT_Y  = {`W_PIN_PIT, 6'd0};
    localparam [21:0] LANE_L = {`W_LANE_L, 6'd0}, LANE_R = {`W_LANE_R, 6'd0};
    localparam [21:0] GUT_LX = {`W_GUT_LX, 6'd0}, GUT_RX = {`W_GUT_RX, 6'd0};
    localparam [19:0] GUT_V  = 20'd655;               // 0.01 in/tick: slower than this drops in


    // ---------------- ROMs --------------------------------------------------
    reg [31:0] spot_rom [0:9];
    reg [7:0]  pair_rom [0:44];
    reg [8:0]  inv_rom  [0:127];                  // 2^14 / |d|, indexed by d^2 >> 12
    initial begin
        $readmemh("inv_len.mem", inv_rom);
        $readmemh("pin_spots.mem", spot_rom);
        $readmemh("pin_pairs.mem", pair_rom);
    end

    // ---------------- pin records -------------------------------------------
    // {x[21:0], y[21:0], vx[19:0], vy[19:0], state[2:0], dir[2:0], timer[8:0]} = 99 bits
    reg [98:0] rec [0:9];
    function [21:0] fx;  input [98:0] r; fx = r[98:77]; endfunction
    function [21:0] fy;  input [98:0] r; fy = r[76:55]; endfunction
    function signed [19:0] fvx; input [98:0] r; fvx = r[54:35]; endfunction
    function signed [19:0] fvy; input [98:0] r; fvy = r[34:15]; endfunction
    function [2:0] fs;   input [98:0] r; fs = r[14:12]; endfunction
    function [2:0] fd;   input [98:0] r; fd = r[11:9];  endfunction
    function [8:0] ft;   input [98:0] r; ft = r[8:0];   endfunction
    function [98:0] mk;
        input [21:0] x, y; input [19:0] vx, vy; input [2:0] s, d; input [8:0] t;
        mk = {x, y, vx, vy, s, d, t};
    endfunction

    // ---------------- helpers ----------------------------------------------
    function [20:0] oct_norm;                         // max + min/2 ~ |v| (+-12 %)
        input signed [20:0] a, b;
        reg [20:0] aa, bb;
        begin
            aa = a[20] ? -a : a;
            bb = b[20] ? -b : b;
            oct_norm = (aa > bb) ? aa + (bb >> 1) : bb + (aa >> 1);
        end
    endfunction
    function [2:0] dir8;                              // 0 = N (toward pit), clockwise
        input signed [19:0] a, b;
        reg [19:0] ax, ay;
        begin
            ax = a[19] ? -a : a;
            ay = b[19] ? -b : b;
            if (ay > (ax << 1))      dir8 = b[19] ? 3'd4 : 3'd0;
            else if (ax > (ay << 1)) dir8 = a[19] ? 3'd6 : 3'd2;
            else if (!a[19])         dir8 = b[19] ? 3'd3 : 3'd1;
            else                     dir8 = b[19] ? 3'd5 : 3'd7;
        end
    endfunction
    function upright;
        input [2:0] s;
        upright = (s == `PS_STANDING) || (s == `PS_WOBBLING);
    endfunction
    // v3: where a pin COLLIDES. A standing pin is its base circle; a lying
    // pin is 15 in long, so its collision circle sits 5 in along its body
    // (2.5 in while it is still falling), in its fall direction dir:
    // 0 = +y (toward the pit), clockwise in steps of 45 degrees.
    function [15:0] coff;                             // signed offset, 1/64 in
        input [2:0] d; input axis_y; input half;
        reg signed [15:0] o;
        begin
            case ({axis_y, d})
                4'b0_000: o = 16'sd0;    4'b1_000: o = 16'sd320;
                4'b0_001: o = 16'sd226;  4'b1_001: o = 16'sd226;
                4'b0_010: o = 16'sd320;  4'b1_010: o = 16'sd0;
                4'b0_011: o = 16'sd226;  4'b1_011: o = -16'sd226;
                4'b0_100: o = 16'sd0;    4'b1_100: o = -16'sd320;
                4'b0_101: o = -16'sd226; 4'b1_101: o = -16'sd226;
                4'b0_110: o = -16'sd320; 4'b1_110: o = 16'sd0;
                default:  o = axis_y ? 16'sd226 : -16'sd226;   // 7: -x, +y
            endcase
            coff = half ? (o >>> 1) : o;
        end
    endfunction
    function [15:0] ccx;                              // collision centre x, POS
        input [98:0] r;
        ccx = upright(fs(r)) ? r[98:83] : r[98:83] + coff(fd(r), 1'b0, fs(r) == `PS_FALLING);
    endfunction
    function [15:0] ccy;
        input [98:0] r;
        ccy = upright(fs(r)) ? r[76:61] : r[76:61] + coff(fd(r), 1'b1, fs(r) == `PS_FALLING);
    endfunction
    // v3.4: offset of a point `dist` along the body in fall direction d
    // (straight: dist, diagonal: dist / sqrt 2 given as dg), signed, 1/64 in
    function [15:0] boff;
        input [2:0] d; input axis_y; input [9:0] dist; input [9:0] dg;
        reg signed [15:0] s, g;
        begin
            s = $signed({6'd0, dist}); g = $signed({6'd0, dg});
            case ({axis_y, d})
                4'b0_000: boff = 16'sd0; 4'b1_000: boff = s;
                4'b0_001: boff = g;      4'b1_001: boff = g;
                4'b0_010: boff = s;      4'b1_010: boff = 16'sd0;
                4'b0_011: boff = g;      4'b1_011: boff = -g;
                4'b0_100: boff = 16'sd0; 4'b1_100: boff = -s;
                4'b0_101: boff = -g;     4'b1_101: boff = -g;
                4'b0_110: boff = -s;     4'b1_110: boff = 16'sd0;
                default:  boff = axis_y ? g : -g;                     // 7: -x, +y
            endcase
        end
    endfunction
    // pin-pin collision circle `sub` (0 = belly 5 in, 1 = head 11.5 in).
    // SIGNED 17 bit: a pin lying toward the gutter has circles at x < 0
    // (found by tb_physics: unsigned, -0.25 in wrapped to 1023 in and the
    // overlap was never seen)
    function signed [16:0] pcc;
        input [98:0] r; input axis_y; input sub;
        reg half; reg [9:0] ds, dg; reg signed [15:0] o;
        begin
            half = (fs(r) == `PS_FALLING);
            ds = sub ? 10'd736 : 10'd320;  dg = sub ? 10'd520 : 10'd226;   // head 11.5 in, belly 5 in
            if (half) begin ds = ds >> 1; dg = dg >> 1; end
            o = upright(fs(r)) ? 16'sd0 : boff(fd(r), axis_y, ds, dg);
            pcc = $signed({1'b0, (axis_y ? r[76:61] : r[98:83])}) + {o[15], o};
        end
    endfunction
    // a velocity change (Q3.16) hits a pin: topple, wobble, or add to its slide
    // (the topple decision, the fall direction and the fall time are worked
    //  out one clock earlier and passed in: timing). v3: a harder hit makes
    // the pin fall faster (fall_t 150 ticks down to 60).
    function [98:0] hit;
        input [98:0] r; input signed [19:0] hx, hy; input topple; input [2:0] dir; input [8:0] fall_t;
        begin
            hit = r;
            if (upright(fs(r))) begin
                if (topple) hit = mk(fx(r), fy(r), hx, hy, `PS_FALLING, dir, fall_t);
                else        hit = mk(fx(r), fy(r), 20'sd0, 20'sd0, `PS_WOBBLING, fd(r), WOB_T);
            end else if (fs(r) != `PS_OFF)
                hit = mk(fx(r), fy(r), fvx(r) + hx, fvy(r) + hy, fs(r), fd(r), ft(r));
        end
    endfunction
    // one tick of a pin on its own: timers, slide, friction, walls, pit.
    // v3 (timing): in two clocked halves. upd1 = timers, move, friction;
    // upd2 = gutter, kickback walls, back of the deck, pit. Between them:
    //   {moving, mx[22:0], my[22:0], wx[19:0], wy[19:0], s, d, t}  (102 bit)
    // or, for a pin that does not slide, {0, 2'b00, its new record}.
    function [101:0] upd1;
        input [98:0] r;
        reg signed [22:0] mx, my;
        reg signed [19:0] wx, wy;
        reg [19:0] ax, ay;
        reg [2:0] s; reg [8:0] t;
        begin
            upd1 = {3'b000, r}; s = fs(r); t = ft(r);
            if (s == `PS_WOBBLING) begin
                upd1 = {3'b000, mk(fx(r), fy(r), fvx(r), fvy(r), (t == 0) ? `PS_STANDING : s, fd(r), t - 9'd1)};
            end else if (s == `PS_FALLING || s == `PS_DOWN) begin
                if (s == `PS_FALLING) begin
                    if (t == 0) s = `PS_DOWN;
                    t = t - 9'd1;
                end
                mx = $signed({1'b0, fx(r)}) + (fvx(r) >>> 4);
                my = $signed({1'b0, fy(r)}) + (fvy(r) >>> 4);
                wx = fvx(r) - (fvx(r) >>> FRIC_SH);
                wy = fvy(r) - (fvy(r) >>> FRIC_SH);
                ax = wx[19] ? -wx : wx;
                ay = wy[19] ? -wy : wy;
                if (ax < STOP_V) wx = 0;
                if (ay < STOP_V) wy = 0;
                upd1 = {1'b1, mx, my, wx, wy, s, fd(r), t};
            end
        end
    endfunction
    function [98:0] upd2;
        input [101:0] p;
        reg signed [22:0] mx, my;
        reg signed [19:0] wx, wy;
        reg [19:0] ax;
        reg [21:0] nx_, ny_;
        reg [2:0] s, d; reg [8:0] t;
        begin
            if (!p[101]) upd2 = p[98:0];
            else begin
                mx = p[100:78]; my = p[77:55]; wx = p[54:35]; wy = p[34:15];
                s = p[14:12]; d = p[11:9]; t = p[8:0];
                ax = wx[19] ? -wx : wx;
                nx_ = mx[21:0]; ny_ = my[21:0];
                // v3: a slow pin that slides off the lane edge drops into the
                // gutter channel and stays in it; a fast one flies on to the
                // kickback, which now throws it back livelier (e = 0.75)
                if ((mx < $signed({1'b0, LANE_L}) || mx > $signed({1'b0, LANE_R})) &&
                    ax < GUT_V && s != `PS_FALLING) begin
                    nx_ = (mx < $signed({1'b0, LANE_L})) ? GUT_LX : GUT_RX; wx = 0;
                end
                else if (mx < $signed({1'b0, KICK_L})) begin nx_ = KICK_L; wx = -(wx - (wx >>> 2)); end
                else if (mx > $signed({1'b0, KICK_R})) begin nx_ = KICK_R; wx = -(wx - (wx >>> 2)); end
                if (my < $signed({1'b0, BACK_Y}))      begin ny_ = BACK_Y; wy = -(wy >>> 1); end
                if (my > $signed({1'b0, PIT_Y}))       begin s = `PS_OFF; wx = 0; wy = 0; end
                upd2 = mk(nx_, ny_, wx, wy, s, d, t);
            end
        end
    endfunction

    // ---------------- read port, status buses ------------------------------
    wire [98:0] rr = rec[pin_rd_idx];
    assign pin_rd_x     = ccx(rr);                // collision centre (v3)
    assign pin_rd_y     = ccy(rr);
    assign pin_rd_vx    = rr[54:39];
    assign pin_rd_vy    = rr[34:19];
    assign pin_rd_solid = (rr[14:12] != `PS_OFF);
    assign pin_rd_upright = upright(rr[14:12]);
    genvar g;
    generate
        for (g = 0; g < 10; g = g + 1) begin : g_vis
            wire [98:0] r = rec[g];
            wire [2:0]  s = r[14:12];
            wire [8:0]  t = r[8:0];
            wire [1:0] stage = (s == `PS_DOWN) ? 2'd2 : (s != `PS_FALLING) ? 2'd0 :
                               (t > 9'd100) ? 2'd0 : (t > 9'd50) ? 2'd1 : 2'd2;
            // v3.4: a lying / falling pin is reported at the centre of its body
            // (7.5 in from the base; half while falling), where it is drawn
            wire        lie = (s == `PS_FALLING) || (s == `PS_DOWN);
            wire [9:0]  vs  = (s == `PS_FALLING) ? 10'd240 : 10'd480;
            wire [9:0]  vg  = (s == `PS_FALLING) ? 10'd170 : 10'd339;
            wire [15:0] vxp = r[98:83] + (lie ? boff(r[11:9], 1'b0, vs, vg) : 16'd0);
            wire [15:0] vyp = r[76:61] + (lie ? boff(r[11:9], 1'b1, vs, vg) : 16'd0);
            wire [5:0]  vx6 = vxp[15] ? 6'd0 : (vxp[15:6] > 10'd63) ? 6'd63 : vxp[11:6];
            assign pin_vis[24*g +: 24] = {vx6, vyp[15:6], s, r[11:9], stage};      // whole inches
            assign standing[g] = upright(s);
            assign busy[g] = (s == `PS_WOBBLING) || (s == `PS_FALLING) ||
                             ((s == `PS_DOWN) && (r[54:35] != 0 || r[34:15] != 0));
        end
    endgenerate

    // ---------------- FSM ---------------------------------------------------
    // Timing: a record read is REGISTERED (index register ia_q -> rA one clock
    // later) and the new record is REGISTERED before it is written (nA_q ->
    // rec one clock later), so no clock path goes index -> 99-bit mux ->
    // physics -> register file. The FSM waits the extra clocks (the tick has
    // ~97 000 to spare).
    localparam S_IDLE = 6'd0, S_UPD = 6'd1, S_PA = 6'd2, S_PB = 6'd3, S_PC = 6'd4,
               S_PD = 6'd5, S_PE = 6'd6, S_PF = 6'd7, S_PG = 6'd8, S_PH = 6'd9,
               S_PI = 6'd10, S_PJ = 6'd11, S_PK = 6'd12, S_PL = 6'd13, S_PM = 6'd14,
               S_PNEXT = 6'd15, S_RAKE = 6'd16, S_PLACE = 6'd17, S_IMP1 = 6'd18, S_IMP2 = 6'd19,
               S_PA2 = 6'd20, S_PA3 = 6'd21, S_PN = 6'd22, S_PW = 6'd23, S_PQ = 6'd24, S_PQ2 = 6'd25,
               S_IMP1B = 6'd26, S_PA4 = 6'd27, S_PD2 = 6'd28, S_PJ0 = 6'd29,
               S_PJ1 = 6'd30, S_PJ2 = 6'd31, S_PJ3 = 6'd32, S_PJ4 = 6'd33, S_PJ5 = 6'd34, S_PJ6 = 6'd35;
    reg [5:0] st;
    reg [1:0] sp;                            // v3.4: circle pair {circle of i, circle of j}
    reg       rack_run;
    reg [3:0] ui;
    reg [5:0] pk;
    reg [1:0] cmd;
    reg [9:0] mask;

    reg  signed [24:0] ma;
    reg  signed [17:0] mb;
    wire signed [42:0] mp;
    mul_s25x18 u_mul (.clk(clk), .a(ma), .b(mb), .p(mp));

    reg signed [16:0] dx, dy;
    reg [35:0]        d2;
    reg signed [17:0] nx, ny;
    reg signed [42:0] t;
    reg signed [24:0] dl;
    reg signed [19:0] dvx, dvy, ndvx, ndvy;
    reg               mixed, topple_q;
    reg [17:0]        inv_q;
    reg [19:0]        hax, hay;                  // |dv| components (registered)
    reg [2:0]         dir_p, dir_n;              // fall direction for +dv / -dv

    // ---------------- registered read ports --------------------------------
    reg  [3:0]  ia_q, ib_q, ia_d;            // ia_d = ia_q one clock later (index of rA)
    reg  [98:0] rA, rB;
    always @(posedge clk) begin
        rA <= rec[ia_q]; rB <= rec[ib_q]; ia_d <= ia_q;
    end
    wire [3:0] ri = pair_rom[pk][7:4];
    wire [3:0] rj = pair_rom[pk][3:0];

    // collision centres of the pair, registered one clock after rA / rB (timing)
    reg  signed [16:0] cAx, cAy, cBx, cBy;
    always @(posedge clk) begin
        cAx <= pcc(rA, 1'b0, sp[1]); cAy <= pcc(rA, 1'b1, sp[1]);
        cBx <= pcc(rB, 1'b0, sp[0]); cBy <= pcc(rB, 1'b1, sp[0]);
    end
    wire signed [17:0] pdx18 = {cBx[16], cBx} - {cAx[16], cAx};
    wire signed [17:0] pdy18 = {cBy[16], cBy} - {cAy[16], cAy};
    wire [17:0] adx18 = pdx18[17] ? -pdx18 : pdx18;
    wire [17:0] ady18 = pdy18[17] ? -pdy18 : pdy18;
    // (only pairs within NEAR are used further, so 17 bits are enough there)
    wire signed [16:0] pdx = pdx18[16:0], pdy = pdy18[16:0];
    wire [17:0] adx = adx18, ady = ady18;
    // a standing pin has only circle 0
    wire sub_bad   = (sp[1] && upright(fs(rA))) || (sp[0] && upright(fs(rB)));
    // whole-pair reject from the BASES: two pins whose bases are more than
    // 30 in apart (11.5 + 11.5 in of body + 6 in of radii + 1) cannot touch,
    // so their other circle pairs are not even read (keeps the pass short)
    wire signed [16:0] bpx = $signed({1'b0, rB[98:83]}) - $signed({1'b0, rA[98:83]});
    wire signed [16:0] bpy = $signed({1'b0, rB[76:61]}) - $signed({1'b0, rA[76:61]});
    wire [16:0] abpx = bpx[16] ? -bpx : bpx, abpy = bpy[16] ? -bpy : bpy;
    wire pair_none = (fs(rA) == `PS_OFF) || (fs(rB) == `PS_OFF) ||
                     (upright(fs(rA)) && upright(fs(rB))) || abpx > 17'd1920 || abpy > 17'd1920;
    reg  pair_none_q;
    wire skip_pair = (fs(rA) == `PS_OFF) || (fs(rB) == `PS_OFF) || sub_bad ||
                     (upright(fs(rA)) && upright(fs(rB))) || adx > NEAR || ady > NEAR;
    // the radii of the two circles: big = the belly circle of a lying pin
    wire bgA = !sp[1] && !upright(fs(rA)), bgB = !sp[0] && !upright(fs(rB));
    reg  [35:0] r2_q;                         // (rA + rB)^2 of this circle pair
    reg  [9:0]  rs_q;                         // rA + rB
    reg  signed [17:0] dmag, cmag;            // |d|, push-out distance (1/64 in)
    reg  signed [19:0] cvx, cvy;              // push-out vector (1/64 in)
    reg         lyA, lyB;                     // which pins may be pushed (not standing)
    // move a lying pin's record by (ox, oy) 1/64 in
    function [98:0] mv;
        input [98:0] r; input signed [19:0] ox, oy; input en;
        begin
            mv = r;
            // (1/64 in -> Q10.12: << 6; the 22-bit two's-complement add wraps correctly)
            if (en) mv = mk(fx(r) + {ox[15:0], 6'd0}, fy(r) + {oy[15:0], 6'd0},
                            fvx(r), fvy(r), fs(r), fd(r), ft(r));
        end
    endfunction
    // v3: fall time from the size of the push (registered with topple_q)
    function [8:0] fall_time;
        input [20:0] nrm;
        reg [20:0] ex;
        begin
            ex = (nrm > {1'b0, TOPPLE}) ? (nrm - {1'b0, TOPPLE}) >> 8 : 21'd0;
            fall_time = (ex > 21'd90) ? FALL_T - 9'd90 : FALL_T - ex[8:0];
        end
    endfunction
    wire [20:0] hnorm = (hax > hay) ? hax + (hay >> 1) : hay + (hax >> 1);
    reg  [8:0]  fall_q;
    reg         pair_rev;                    // this tick walks the pairs 44 -> 0
    wire [35:0] d2_full  = d2 + mp[35:0];
    wire [35:0] r2_pair  = r2_q;
    wire signed [42:0] vrn = (t + mp) >>> 14;          // (v_i - v_j) . n, Q3.16
    reg  signed [24:0] vrn_q;                          // v_rel_n, registered (timing)
    reg         vgt;
    reg  [35:0] d2s;
    reg  [101:0] u1;                                   // first half of a pin update
    reg  [3:0]  u1_i;
    wire signed [24:0] vrn25 = vrn_q;
    wire signed [24:0] dl_calc = vrn25 - (vrn25 >>> DL_S1) - (vrn25 >>> DL_S2);

    // v3.4: overlap depth -> push-out distance (registered steps S_PJ1, S_PJ2)
    wire signed [17:0] pen_w = $signed({8'd0, rs_q}) - dmag;
    wire signed [17:0] pen_p = (pen_w < 0) ? 18'sd0 : pen_w;

    // ball impulses and scan_done are remembered until the FSM takes them
    reg        imp_pend, scan_pend;
    reg [3:0]  imp_pin;
    reg signed [19:0] imp_vx, imp_vy;        // Q3.16
    reg        rack_pend, force_pend;

    // ---------------- registered write ports -------------------------------
    reg        weA, weB;
    reg [3:0]  waA, waB;
    reg [98:0] nA, nB;

    // whole-rack operations (each pin on its own record: a short path)
    localparam B_NONE = 2'd0, B_FORCE = 2'd1, B_RAKE = 2'd2, B_PLACE = 2'd3;
    reg [1:0] bulk;
    always @(*) begin
        bulk = B_NONE;
        if (st == S_IDLE && force_pend && !imp_pend) bulk = B_FORCE;
        else if (st == S_RAKE && tick_phys)          bulk = B_RAKE;
        else if (st == S_PLACE)                      bulk = B_PLACE;
    end
    function [98:0] bulk_op;
        input [98:0] r; input [1:0] op; input [31:0] spot; input keep; input [9:0] rk;
        begin
            bulk_op = r;
            case (op)
                B_FORCE: if (fs(r) == `PS_WOBBLING) bulk_op = mk(fx(r), fy(r), 20'sd0, 20'sd0, `PS_STANDING, fd(r), 9'd0);
                         else if (fs(r) == `PS_FALLING || fs(r) == `PS_DOWN)
                             bulk_op = mk(fx(r), fy(r), 20'sd0, 20'sd0, `PS_DOWN, fd(r), 9'd0);
                B_RAKE:  if (!upright(fs(r)) && fs(r) != `PS_OFF && r[76:67] < rk)
                             bulk_op = mk(fx(r), {rk, 12'd0}, 20'sd0, 20'sd0, `PS_DOWN, fd(r), 9'd0);
                B_PLACE: bulk_op = keep ? mk({spot[31:16], 6'd0}, {spot[15:0], 6'd0}, 20'sd0, 20'sd0, `PS_STANDING, 3'd0, 9'd0)
                                        : mk(fx(r), fy(r), 20'sd0, 20'sd0, `PS_OFF, 3'd0, 9'd0);
                default: ;
            endcase
        end
    endfunction

    // ---------------- the register file: 4-input mux per record -------------
    integer k;
    always @(posedge clk) begin
        for (k = 0; k < 10; k = k + 1) begin
            if (rst)                          rec[k] <= mk({spot_rom[k][31:16], 6'd0}, {spot_rom[k][15:0], 6'd0}, 20'sd0, 20'sd0, `PS_STANDING, 3'd0, 9'd0);
            else if (weA && waA == k)         rec[k] <= nA;
            else if (weB && waB == k)         rec[k] <= nB;
            else if (bulk != B_NONE)          rec[k] <= bulk_op(rec[k], bulk, spot_rom[k],
                                                      (cmd == `RK_FULL) || (cmd == `RK_LEAVE && mask[k]) ||
                                                      (cmd == `RK_SWEEP && upright(fs(rec[k]))), rake_y);
        end
    end

    // requests remembered until the FSM is idle
    reg [1:0] rack_cmd_l;
    reg [9:0] rack_mask_l;
    always @(posedge clk)
        if (rst) begin rack_pend <= 1'b0; rack_cmd_l <= `RK_FULL; rack_mask_l <= 10'h3FF; end
        else if (rack_go) begin rack_pend <= 1'b1; rack_cmd_l <= rack_cmd; rack_mask_l <= rack_mask; end
        else if (st == S_IDLE) rack_pend <= 1'b0;
    assign rack_busy = rack_run | rack_pend | rack_go;
    always @(posedge clk)
        if (rst) force_pend <= 1'b0;
        else if (force_settle) force_pend <= 1'b1;
        else if (bulk == B_FORCE) force_pend <= 1'b0;

    // ---------------- control FSM ---------------------------------------------
    always @(posedge clk) begin
        weA <= 1'b0; weB <= 1'b0;
        if (rst) begin
            st <= S_IDLE; ui <= 0; pk <= 0; cmd <= `RK_FULL; mask <= 10'h3FF;
            rack_run <= 1'b0; rake_y <= 10'd0; ia_q <= 0; ib_q <= 0; waA <= 0; waB <= 0; nA <= 0; nB <= 0;
            ma <= 0; mb <= 0; dx <= 0; dy <= 0; d2 <= 0; nx <= 0; ny <= 0; t <= 0; dl <= 0; dvx <= 0; dvy <= 0;
            ndvx <= 0; ndvy <= 0; topple_q <= 0; dir_p <= 0; dir_n <= 0; fall_q <= FALL_T; pair_rev <= 1'b0;
            mixed <= 0; imp_pend <= 0; scan_pend <= 0; imp_pin <= 0; imp_vx <= 0; imp_vy <= 0;
            sp <= 2'd0; r2_q <= R2_BB; rs_q <= 10'd308; dmag <= 0; cmag <= 0; cvx <= 0; cvy <= 0;
            lyA <= 0; lyB <= 0; pair_none_q <= 1'b1;
        end else begin
            if (impulse_valid) begin
                imp_pend <= 1'b1; imp_pin <= impulse_pin;
                imp_vx <= {impulse_vx, 4'd0}; imp_vy <= {impulse_vy, 4'd0};   // Q3.12 -> Q3.16
            end
            if (scan_done) scan_pend <= 1'b1;
            case (st)
                S_IDLE: begin
                    if (rack_pend) begin
                        cmd <= rack_cmd_l; mask <= rack_mask_l;
                        rack_run <= 1'b1; rake_y <= 10'd700; ui <= 4'd0;
                        st <= S_RAKE;
                    end else if (imp_pend && !impulse_valid) begin
                        ia_q <= imp_pin; st <= S_IMP1;
                    end else if (scan_pend && !imp_pend && !impulse_valid) begin
                        scan_pend <= 1'b0; ui <= 4'd0; st <= S_UPD;
                    end
                end
                S_IMP1: begin                                      // |dv| parts first (timing)
                    hax <= imp_vx[19] ? -imp_vx : imp_vx;
                    hay <= imp_vy[19] ? -imp_vy : imp_vy;
                    st <= S_IMP1B;
                end
                S_IMP1B: begin                                     // topple? which way? how fast?
                    topple_q <= hnorm > TOPPLE;
                    fall_q   <= fall_time(hnorm);
                    dir_p    <= dir8(imp_vx, imp_vy);
                    st <= S_IMP2;
                end
                S_IMP2: begin
                    weA <= 1'b1; waA <= ia_d; nA <= hit(rA, imp_vx, imp_vy, topple_q, dir_p, fall_q);
                    imp_pend <= impulse_valid;                     // (a new one cannot come this soon)
                    st <= S_IDLE;
                end
                // ---- 1. per-pin update, pipelined: issue j, read j+1, half j+2, write j+3 --
                S_UPD: begin
                    if (ui <= 4'd9) ia_q <= ui;
                    if (ui >= 4'd2 && ui <= 4'd11) begin u1 <= upd1(rA); u1_i <= ia_d; end
                    if (ui >= 4'd3) begin weA <= 1'b1; waA <= u1_i; nA <= upd2(u1); end
                    if (ui == 4'd12) begin pk <= pair_rev ? 6'd44 : 6'd0; st <= S_PA; end
                    else ui <= ui + 4'd1;
                end
                // ---- 2. pair iterator (v3: forward / backward on alternate ticks) --
                S_PA:  begin ia_q <= ri; ib_q <= rj; st <= S_PA2; end
                S_PA2: st <= S_PA4;                                // rA, rB load
                S_PA4: st <= S_PA3;                                // collision centres load
                S_PA3: begin
                    dx <= pdx; dy <= pdy;
                    // v3.4: this circle pair's contact distance, who may be pushed
                    r2_q <= (bgA && bgB) ? R2_BB : (bgA || bgB) ? R2_BS : R2_SS;
                    rs_q <= (bgA ? R_BIG : R_SML) + (bgB ? R_BIG : R_SML);
                    lyA <= !upright(fs(rA)); lyB <= !upright(fs(rB));
                    pair_none_q <= pair_none;
                    if (skip_pair || pair_none) st <= S_PNEXT;
                    else begin ma <= pdx; mb <= pdx; st <= S_PB; end
                end
                S_PB: begin ma <= dy; mb <= dy; st <= S_PC; end
                S_PC: begin d2 <= mp[35:0]; st <= S_PD; end
                S_PD: begin d2s <= d2_full; st <= S_PD2; end      // |d|^2 registered (timing)
                S_PD2: if (d2s < r2_pair) begin                   // unit normal: d / |d| (ROM)
                          inv_q <= {9'd0, inv_rom[d2s[18:12]]};
                          ma <= dx; mb <= {9'd0, inv_rom[d2s[18:12]]}; st <= S_PE;
                      end
                      else st <= S_PNEXT;
                S_PE: begin ma <= dy; mb <= inv_q; st <= S_PF; end
                S_PF: begin nx <= mp[17:0]; st <= S_PG; end
                S_PG: begin ny <= mp[17:0]; ma <= fvx(rA) - fvx(rB); mb <= nx; st <= S_PH; end
                S_PH: begin ma <= fvy(rA) - fvy(rB); mb <= ny; st <= S_PI; end
                S_PI: begin t <= mp; ma <= d2s[24:0]; mb <= inv_q; st <= S_PJ0; end   // |d| = d^2 / |d|
                S_PJ0: begin vrn_q <= vrn[24:0]; vgt <= (vrn > 0); st <= S_PJ1; end   // (timing)
                // ---- v3.4: push the overlap out, in this tick ----
                S_PJ1: begin dmag <= mp >>> 14; st <= S_PJ2; end
                S_PJ2: begin                                       // whole overlap (+1/64), shared if both lie
                    cmag <= (lyA && lyB) ? (pen_p >>> 1) + 18'sd1 : pen_p + 18'sd1;
                    st <= S_PJ3;
                end
                S_PJ3: begin ma <= cmag; mb <= nx; st <= S_PJ4; end
                S_PJ4: begin ma <= cmag; mb <= ny; st <= S_PJ5; end
                S_PJ5: begin cvx <= mp >>> 14; st <= S_PJ6; end
                S_PJ6: begin cvy <= mp >>> 14; st <= S_PJ; end
                S_PJ: begin
                    if (vgt) begin dl <= dl_calc; ma <= dl_calc; mb <= nx; st <= S_PK; end
                    else begin
                        // touching but not approaching: only push apart (written next clock)
                        weA <= lyA; waA <= ia_q; nA <= mv(rA, -cvx, -cvy, 1'b1);
                        weB <= lyB; waB <= ib_q; nB <= mv(rB,  cvx,  cvy, 1'b1);
                        st <= S_PW;
                    end
                end
                S_PK: begin ma <= dl; mb <= ny; st <= S_PL; end
                S_PL: begin dvx <= mp >>> 14; st <= S_PM; end
                S_PM: begin dvy <= mp >>> 14; st <= S_PQ; end
                S_PQ: begin                                        // |dv| parts first (timing)
                    ndvx <= -dvx; ndvy <= -dvy;
                    hax <= dvx[19] ? -dvx : dvx;
                    hay <= dvy[19] ? -dvy : dvy;
                    st <= S_PQ2;
                end
                S_PQ2: begin                                       // decide: topple? which way?
                    // v3.4: a hit by a lying pin's HEAD circle strikes a standing
                    // pin high up, so a quarter of the push tips it over
                    topple_q <= (sp != 2'd0) ? (hnorm > (TOPPLE >> 2)) : (hnorm > TOPPLE);
                    fall_q   <= fall_time(hnorm);
                    dir_p <= dir8(dvx, dvy); dir_n <= dir8(ndvx, ndvy);
                    st <= S_PN;
                end
                S_PN: begin                                        // pin i loses dv along n, pin j gains it
                    // (v3.4: plus the push-out, for a pin that was already lying)
                    weA <= 1'b1; waA <= ia_q; nA <= mv(hit(rA, ndvx, ndvy, topple_q, dir_n, fall_q), -cvx, -cvy, lyA);
                    weB <= 1'b1; waB <= ib_q; nB <= mv(hit(rB, dvx,  dvy,  topple_q, dir_p, fall_q),  cvx,  cvy, lyB);
                    st <= S_PW;
                end
                S_PW: st <= S_PNEXT;                               // the write lands now
                // v3.4: the next circle pair that exists (a standing pin has only
                // circle 0) of the same two pins, re-read; then the next pin pair
                S_PNEXT: if (!pair_none_q && sp == 2'd0 && (lyA || lyB)) begin
                             sp <= lyB ? 2'd1 : 2'd2; st <= S_PA;
                         end else if (!pair_none_q && sp == 2'd1 && lyA) begin
                             sp <= 2'd2; st <= S_PA;
                         end else if (!pair_none_q && sp == 2'd2 && lyB) begin
                             sp <= 2'd3; st <= S_PA;
                         end else if (pk == (pair_rev ? 6'd0 : 6'd44)) begin
                             sp <= 2'd0; pair_rev <= ~pair_rev; st <= S_IDLE;
                         end else begin
                             sp <= 2'd0; pk <= pair_rev ? pk - 6'd1 : pk + 6'd1; st <= S_PA;
                         end
                S_RAKE: if (tick_phys) begin
                    // the rake moves 1/8 in per tick (0.55 s for 70 in)
                    if (ui[2:0] == 3'd7) rake_y <= rake_y + 10'd1;
                    ui <= ui + 4'd1;
                    if (rake_y == 10'd770) begin ui <= 4'd0; st <= S_PLACE; end
                end
                S_PLACE: begin rake_y <= 10'd0; rack_run <= 1'b0; st <= S_IDLE; end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
