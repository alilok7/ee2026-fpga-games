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
// Structure: the 10 pin records are written through exactly TWO write ports
//   (A, B: at most two pins change per clock) plus whole-rack operations
//   (rake, placement, settle timeout), so each record bit has a 4-input mux.
// Cycle budget: update 10 + pairs 45 x 4 (far) .. 45 x 17 (all touching)
//   = at most ~800 clocks of the 97 656 in a tick.
// Rack commands (D): every command first runs the rake (0.55 s sweep that
//   pushes fallen pins into the pit), then FULL = 10 pins on their spots,
//   SWEEP = keep only the standing pins, LEAVE = exactly rack_mask.
//=============================================================================
module pin_physics (
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
    localparam [16:0] NEAR    = 17'd576;              // 9 in quick reject
    localparam [35:0] R2_MIX  = 36'd167772;           // (6.4 in * 64)^2
    localparam [17:0] INV_MIX = 18'd40;               // 2^14 / (6.4 * 64)
    localparam [35:0] R2_DD   = 36'd262144;           // (8.0 in * 64)^2
    localparam [17:0] INV_DD  = 18'd32;               // 2^14 / (8.0 * 64)
    localparam [19:0] TOPPLE   = 20'd1300;            // Q3.16, ~0.02 in/tick (ball and pin hits)
    // below this a slide stops. Must be >= 256: for 0 < v < 256 the friction
    // step v >> 8 is 0, so a slower pin would slide forever (found by tb_top)
    localparam [19:0] STOP_V   = 20'd320;
    localparam [21:0] KICK_L = {`W_KICK_L, 6'd0}, KICK_R = {`W_KICK_R, 6'd0};
    localparam [21:0] BACK_Y = 22'd2867200;           // 700 in: pins cannot slide back further
    localparam [21:0] PIT_Y  = {`W_PIN_PIT, 6'd0};


    // ---------------- ROMs --------------------------------------------------
    reg [31:0] spot_rom [0:9];
    reg [7:0]  pair_rom [0:44];
    initial begin
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
    // a velocity change (Q3.16) hits a pin: topple, wobble, or add to its slide
    // (the topple decision and the fall direction are worked out one clock
    //  earlier and passed in: timing)
    function [98:0] hit;
        input [98:0] r; input signed [19:0] hx, hy; input topple; input [2:0] dir;
        begin
            hit = r;
            if (upright(fs(r))) begin
                if (topple) hit = mk(fx(r), fy(r), hx, hy, `PS_FALLING, dir, FALL_T);
                else        hit = mk(fx(r), fy(r), 20'sd0, 20'sd0, `PS_WOBBLING, fd(r), WOB_T);
            end else if (fs(r) != `PS_OFF)
                hit = mk(fx(r), fy(r), fvx(r) + hx, fvy(r) + hy, fs(r), fd(r), ft(r));
        end
    endfunction
    // one tick of a pin on its own: timers, slide, friction, walls, pit
    function [98:0] upd;
        input [98:0] r;
        reg signed [22:0] mx, my;
        reg signed [19:0] wx, wy;
        reg [19:0] ax, ay;
        reg [21:0] nx_, ny_;
        reg [2:0] s; reg [8:0] t;
        begin
            upd = r; s = fs(r); t = ft(r);
            if (s == `PS_WOBBLING) begin
                upd = mk(fx(r), fy(r), fvx(r), fvy(r), (t == 0) ? `PS_STANDING : s, fd(r), t - 9'd1);
            end else if (s == `PS_FALLING || s == `PS_DOWN) begin
                if (s == `PS_FALLING) begin
                    if (t == 0) s = `PS_DOWN;
                    t = t - 9'd1;
                end
                mx = $signed({1'b0, fx(r)}) + (fvx(r) >>> 4);
                my = $signed({1'b0, fy(r)}) + (fvy(r) >>> 4);
                wx = fvx(r) - (fvx(r) >>> 8);
                wy = fvy(r) - (fvy(r) >>> 8);
                ax = wx[19] ? -wx : wx;
                ay = wy[19] ? -wy : wy;
                if (ax < STOP_V) wx = 0;
                if (ay < STOP_V) wy = 0;
                nx_ = mx[21:0]; ny_ = my[21:0];
                if (mx < $signed({1'b0, KICK_L}))      begin nx_ = KICK_L; wx = -(wx >>> 1); end
                else if (mx > $signed({1'b0, KICK_R})) begin nx_ = KICK_R; wx = -(wx >>> 1); end
                if (my < $signed({1'b0, BACK_Y}))      begin ny_ = BACK_Y; wy = -(wy >>> 1); end
                if (my > $signed({1'b0, PIT_Y}))       begin s = `PS_OFF; wx = 0; wy = 0; end
                upd = mk(nx_, ny_, wx, wy, s, fd(r), t);
            end
        end
    endfunction

    // ---------------- read port, status buses ------------------------------
    wire [98:0] rr = rec[pin_rd_idx];
    assign pin_rd_x     = rr[98:83];
    assign pin_rd_y     = rr[76:61];
    assign pin_rd_vx    = rr[54:39];
    assign pin_rd_vy    = rr[34:19];
    assign pin_rd_solid = (rr[14:12] != `PS_OFF);
    genvar g;
    generate
        for (g = 0; g < 10; g = g + 1) begin : g_vis
            wire [98:0] r = rec[g];
            wire [2:0]  s = r[14:12];
            wire [8:0]  t = r[8:0];
            wire [1:0] stage = (s == `PS_DOWN) ? 2'd2 : (s != `PS_FALLING) ? 2'd0 :
                               (t > 9'd100) ? 2'd0 : (t > 9'd50) ? 2'd1 : 2'd2;
            assign pin_vis[24*g +: 24] = {r[94:89], r[76:67], s, r[11:9], stage};   // x[17:12], y[21:12]
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
    localparam S_IDLE = 5'd0, S_UPD = 5'd1, S_PA = 5'd2, S_PB = 5'd3, S_PC = 5'd4,
               S_PD = 5'd5, S_PE = 5'd6, S_PF = 5'd7, S_PG = 5'd8, S_PH = 5'd9,
               S_PI = 5'd10, S_PJ = 5'd11, S_PK = 5'd12, S_PL = 5'd13, S_PM = 5'd14,
               S_PNEXT = 5'd15, S_RAKE = 5'd16, S_PLACE = 5'd17, S_IMP1 = 5'd18, S_IMP2 = 5'd19,
               S_PA2 = 5'd20, S_PA3 = 5'd21, S_PN = 5'd22, S_PW = 5'd23, S_PQ = 5'd24;
    reg [4:0] st;
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
    reg [2:0]         dir_p, dir_n;              // fall direction for +dv / -dv

    // ---------------- registered read ports --------------------------------
    reg  [3:0]  ia_q, ib_q, ia_d;            // ia_d = ia_q one clock later (index of rA)
    reg  [98:0] rA, rB;
    always @(posedge clk) begin
        rA <= rec[ia_q]; rB <= rec[ib_q]; ia_d <= ia_q;
    end
    wire [3:0] ri = pair_rom[pk][7:4];
    wire [3:0] rj = pair_rom[pk][3:0];

    wire signed [16:0] pdx = $signed({1'b0, rB[98:83]}) - $signed({1'b0, rA[98:83]});
    wire signed [16:0] pdy = $signed({1'b0, rB[76:61]}) - $signed({1'b0, rA[76:61]});
    wire [16:0] adx = pdx[16] ? -pdx : pdx;
    wire [16:0] ady = pdy[16] ? -pdy : pdy;
    wire skip_pair = (fs(rA) == `PS_OFF) || (fs(rB) == `PS_OFF) ||
                     (upright(fs(rA)) && upright(fs(rB))) || adx > NEAR || ady > NEAR;
    wire [35:0] d2_full  = d2 + mp[35:0];
    wire [35:0] r2_pair  = mixed ? R2_MIX  : R2_DD;
    wire [17:0] inv_pair = mixed ? INV_MIX : INV_DD;
    wire signed [42:0] vrn = (t + mp) >>> 14;          // (v_i - v_j) . n, Q3.16
    wire signed [24:0] vrn25 = vrn[24:0];
    wire signed [24:0] dl_calc = vrn25 - (vrn25 >>> 3) - (vrn25 >>> 4);

    // separation steps: n (Q1.14) >> 8 = 1/64 in, >> 7 = 1/32 in
    wire signed [17:0] n1x = nx >>> 8, n1y = ny >>> 8, n2x = nx >>> 7, n2y = ny >>> 7;
    wire [21:0] sep1x = {{4{n1x[17]}}, n1x}, sep1y = {{4{n1y[17]}}, n1y};
    wire [21:0] sep2x = {{4{n2x[17]}}, n2x}, sep2y = {{4{n2y[17]}}, n2y};
    wire [21:0] sAx = upright(fs(rB)) ? sep2x : sep1x, sAy = upright(fs(rB)) ? sep2y : sep1y;
    wire [21:0] sBx = upright(fs(rA)) ? sep2x : sep1x, sBy = upright(fs(rA)) ? sep2y : sep1y;

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
            ndvx <= 0; ndvy <= 0; topple_q <= 0; dir_p <= 0; dir_n <= 0;
            mixed <= 0; imp_pend <= 0; scan_pend <= 0; imp_pin <= 0; imp_vx <= 0; imp_vy <= 0;
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
                S_IMP1: begin                                      // rA = rec[imp_pin] next
                    topple_q <= oct_norm(imp_vx, imp_vy) > {1'b0, TOPPLE};
                    dir_p    <= dir8(imp_vx, imp_vy);
                    st <= S_IMP2;
                end
                S_IMP2: begin
                    weA <= 1'b1; waA <= ia_d; nA <= hit(rA, imp_vx, imp_vy, topple_q, dir_p);
                    imp_pend <= impulse_valid;                     // (a new one cannot come this soon)
                    st <= S_IDLE;
                end
                // ---- 1. per-pin update, pipelined: issue j, read j+1, write j+2 --
                S_UPD: begin
                    if (ui <= 4'd9) ia_q <= ui;
                    if (ui >= 4'd2) begin weA <= 1'b1; waA <= ia_d; nA <= upd(rA); end
                    if (ui == 4'd11) begin pk <= 6'd0; st <= S_PA; end
                    else ui <= ui + 4'd1;
                end
                // ---- 2. pair iterator --------------------------------------
                S_PA:  begin ia_q <= ri; ib_q <= rj; st <= S_PA2; end
                S_PA2: st <= S_PA3;                                // rA, rB load
                S_PA3: begin
                    dx <= pdx; dy <= pdy;
                    mixed <= upright(fs(rA)) || upright(fs(rB));
                    if (skip_pair) st <= S_PNEXT;
                    else begin ma <= pdx; mb <= pdx; st <= S_PB; end
                end
                S_PB: begin ma <= dy; mb <= dy; st <= S_PC; end
                S_PC: begin d2 <= mp[35:0]; st <= S_PD; end
                S_PD: if (d2_full < r2_pair) begin ma <= dx; mb <= inv_pair; st <= S_PE; end
                      else st <= S_PNEXT;
                S_PE: begin ma <= dy; mb <= inv_pair; st <= S_PF; end
                S_PF: begin nx <= mp[17:0]; st <= S_PG; end
                S_PG: begin ny <= mp[17:0]; ma <= fvx(rA) - fvx(rB); mb <= nx; st <= S_PH; end
                S_PH: begin ma <= fvy(rA) - fvy(rB); mb <= ny; st <= S_PI; end
                S_PI: begin t <= mp; st <= S_PJ; end
                S_PJ: begin
                    if (vrn > 0) begin dl <= dl_calc; ma <= dl_calc; mb <= nx; st <= S_PK; end
                    else begin
                        // touching but not approaching: separate (written next clock)
                        weA <= !upright(fs(rA)); waA <= ia_q;
                        nA  <= mk(fx(rA) - sAx, fy(rA) - sAy, fvx(rA), fvy(rA), fs(rA), fd(rA), ft(rA));
                        weB <= !upright(fs(rB)); waB <= ib_q;
                        nB  <= mk(fx(rB) + sBx, fy(rB) + sBy, fvx(rB), fvy(rB), fs(rB), fd(rB), ft(rB));
                        st <= S_PW;
                    end
                end
                S_PK: begin ma <= dl; mb <= ny; st <= S_PL; end
                S_PL: begin dvx <= mp >>> 14; st <= S_PM; end
                S_PM: begin dvy <= mp >>> 14; st <= S_PQ; end
                S_PQ: begin                                        // decide: topple? which way?
                    ndvx <= -dvx; ndvy <= -dvy;
                    topple_q <= oct_norm(dvx, dvy) > {1'b0, TOPPLE};
                    dir_p <= dir8(dvx, dvy); dir_n <= dir8(-dvx, -dvy);
                    st <= S_PN;
                end
                S_PN: begin                                        // pin i loses dv along n, pin j gains it
                    weA <= 1'b1; waA <= ia_q; nA <= hit(rA, ndvx, ndvy, topple_q, dir_n);
                    weB <= 1'b1; waB <= ib_q; nB <= hit(rB, dvx,  dvy,  topple_q, dir_p);
                    st <= S_PW;
                end
                S_PW: st <= S_PNEXT;                               // the write lands now
                S_PNEXT: if (pk == 6'd44) st <= S_IDLE; else begin pk <= pk + 6'd1; st <= S_PA; end
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
