`timescale 1ns / 1ps
`include "strike_defs.vh"
// ball_physics.v : skid -> hook -> roll, gutter, ball -> pin collisions
// Owner: Student B

module ball_physics #(
    parameter [15:0] R_DOWN = 16'd224
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
    input  wire        steer_valid,
    input  wire signed [11:0] steer_dx,
    output reg  [3:0]  pin_rd_idx,
    input  wire [15:0] pin_rd_x,
    input  wire [15:0] pin_rd_y,
    input  wire signed [15:0] pin_rd_vx,
    input  wire signed [15:0] pin_rd_vy,
    input  wire        pin_rd_solid,
    input  wire        pin_rd_upright,
    output wire        impulse_valid,
    output wire [3:0]  impulse_pin,
    output wire signed [15:0] impulse_vx,
    output wire signed [15:0] impulse_vy,
    output reg         scan_done,
    output wire [15:0] ball_x,
    output wire [15:0] ball_y,
    output wire signed [15:0] ball_vx,
    output wire signed [15:0] ball_vy,
    output reg  [`BP_W-1:0] ball_phase,
    output reg  signed [`SPIN_W-1:0] ball_spin,
    output wire [7:0]  ball_rev,
    output reg  [15:0] ball_angle,
    output wire        contact_pulse,
    output wire [15:0] contact_px,
    output wire [15:0] contact_py
);

    // ---------- 1. Constants and states ----------
    localparam [16:0] NEAR_UP   = 17'd448;
    localparam [16:0] NEAR_DOWN = R_DOWN + 17'd320;
    localparam [7:0]  MU_DRY    = 8'd16;
    localparam [17:0] KICK_STEP = 18'd6;

    localparam [3:0] S_IDLE  = 4'd0;
    localparam [3:0] S_OIL   = 4'd1;
    localparam [3:0] S_CALC  = 4'd2;
    localparam [3:0] S_MOVE  = 4'd3;
    localparam [3:0] S_WAIT  = 4'd4;
    localparam [3:0] S_READ  = 4'd5;
    localparam [3:0] S_DIST  = 4'd6;
    localparam [3:0] S_CHECK = 4'd7;
    localparam [3:0] S_HIT   = 4'd8;
    localparam [3:0] S_NEXT  = 4'd9;
    localparam [3:0] S_DONE  = 4'd10;

    reg [3:0] st;

    // ---------- 2. Ball state: position Q10.20 inches, speed 2^-20 inches per tick ----------
    reg [29:0] x, y;
    reg signed [23:0] vx, vy;
    reg [23:0] slip;
    reg        slip_left;
    reg [10:0] roll_ticks;
    reg signed [23:0] steer_q, steer_used, steer_ok;
    reg        scan_rev;
    reg [17:0] kick;
    reg [23:0] hook;
    reg        in_oil;
    reg [15:0] roll_step, roll_pos;

    // the XDC finds these by name, so they keep the "pr" start
    reg [15:0] prx, pry;
    reg signed [15:0] prvx, prvy;
    reg        prs, prup;

    reg signed [16:0] dx_q, dy_q;
    reg        far;

    // Ball position and speed for the other parts, in the shared POS Q10.6 and VEL Q3.12
    assign ball_x  = x[29:14];
    assign ball_y  = y[29:14];
    assign ball_vx = vx[23:8];
    assign ball_vy = vy[23:8];
    assign ball_rev = (slip[23:8] > 16'd255) ? 8'd255 : slip[15:8];

    // ---------- 3. Helper modules ----------
    wire [7:0]  dec_oil, dec_dry, mu;
    wire [15:0] rev_k;
    wire [17:0] kp, kb;
    wire        throw_pend;
    wire [23:0] hook_now;
    wire signed [23:0] vy_min, vy_next;
    wire signed [23:0] steer_new, steer_max_ok;
    wire        hit_done, vx_wr, vy_wr;
    wire signed [23:0] dbx, vy_hit;

    // What the ball and the FSM are doing right now
    wire rolling  = (ball_phase == `BP_SKID) || (ball_phase == `BP_HOOK) || (ball_phase == `BP_ROLL);
    wire aiming   = (game_state == `GS_AIM);
    wire idle     = (st == S_IDLE);
    wire throw_go = throw_pend && idle;
    wire check    = (st == S_CHECK);
    reg  hit_go, pin_skip;

    // At S_CHECK decide once: skip this pin or start the hit maths.
    // One decision, so the FSM and u_hit can never disagree
    always @ (*) begin
        hit_go = 1'b0;
        pin_skip = 1'b0;
        if (check) begin
            if (!prs || far)
                pin_skip = 1'b1;
            else
                hit_go = 1'b1;
        end
    end

    ball_settings u_settings (
        .long_oil(settings[`SET_OIL]),
        .ball_lb(settings[`SET_LB_HI:`SET_LB_LO]),
        .dec_oil(dec_oil),
        .dec_dry(dec_dry),
        .rev_k(rev_k),
        .kp(kp),
        .kb(kb)
    );

    ball_oil u_oil (
        .clk(clk),
        .long_oil(settings[`SET_OIL]),
        .ball_x(ball_x),
        .ball_y(ball_y),
        .mu(mu)
    );

    ball_throw_latch u_throw (
        .clk(clk),
        .rst(rst),
        .throw_valid(throw_valid),
        .throwing(game_state == `GS_THROW),
        .idle(idle),
        .pending(throw_pend)
    );

    ball_friction u_friction (
        .slip(slip),
        .mu(mu),
        .hook_now(hook_now),
        .vy(vy),
        .ball_y(ball_y),
        .in_oil(in_oil),
        .dec_oil(dec_oil),
        .dec_dry(dec_dry),
        .hook(hook),
        .vy_min(vy_min),
        .vy_next(vy_next)
    );

    ball_steer u_steer (
        .steer_dx(steer_dx),
        .steer_q(steer_q),
        .steer_used(steer_used),
        .steer_new(steer_new),
        .steer_ok(steer_max_ok)
    );

    ball_hit #(.R_DOWN(R_DOWN)) u_hit (
        .clk(clk),
        .rst(rst),
        .load(check),
        .start(hit_go),
        .pin_skip(pin_skip),
        .clear_all(throw_go),
        .pin(pin_rd_idx),
        .pin_x(prx),
        .pin_y(pry),
        .pin_vx(prvx),
        .pin_vy(prvy),
        .pin_up(prup),
        .dx_in(dx_q),
        .dy_in(dy_q),
        .vx(vx),
        .vy(vy),
        .vy_min(vy_min),
        .spin_neg(ball_spin[`SPIN_W-1]),
        .kick(kick),
        .kp(kp),
        .kb(kb),
        .done(hit_done),
        .vx_wr(vx_wr),
        .dbx(dbx),
        .vy_wr(vy_wr),
        .vy_hit(vy_hit),
        .impulse_valid(impulse_valid),
        .impulse_pin(impulse_pin),
        .impulse_vx(impulse_vx),
        .impulse_vy(impulse_vy),
        .contact_pulse(contact_pulse),
        .contact_px(contact_px),
        .contact_py(contact_py)
    );

    // ---------- 4. Next position, and the distance to the current pin ----------
    wire [`SPIN_W-2:0] spin_abs = throw_spin[`SPIN_W-1] ? -throw_spin[`SPIN_W-2:0] : throw_spin[`SPIN_W-2:0];

    // Where the ball will be after this tick
    wire signed [31:0] nx = $signed({2'b00, x}) + vx;
    wire signed [31:0] ny = $signed({2'b00, y}) + vy;
    wire [15:0] nx_pos = nx[29:14];

    // Roll position and spin amount for the ball animation in ball_render
    wire [15:0] roll_next = roll_pos + roll_step;
    wire [1:0]  spin_look = (slip >= 24'd20000) ? 2'd3 : (slip >= 24'd8000) ? 2'd2 : (slip != 0) ? 2'd1 : 2'd0;

    // Pins are scanned 0 to 9 and 9 to 0 on alternate ticks, so no pin is always first
    wire [3:0] first_pin = scan_rev ? 4'd9 : 4'd0;
    wire [3:0] last_pin  = scan_rev ? 4'd0 : 4'd9;

    // Quick reject: a pin further than this in x or y needs no multiply
    wire [16:0] near = prup ? NEAR_UP : NEAR_DOWN;
    wire signed [16:0] pdx = $signed({1'b0, prx}) - $signed({1'b0, ball_x});
    wire signed [16:0] pdy = $signed({1'b0, pry}) - $signed({1'b0, ball_y});
    wire [16:0] adx = pdx[16] ? -pdx : pdx;
    wire [16:0] ady = pdy[16] ? -pdy : pdy;

    // ---------- 5. Main FSM: one pass per physics tick ----------
    always @ (posedge clk) begin
        scan_done <= 1'b0;
        if (rst) begin
            st <= S_IDLE;
            ball_phase <= `BP_IDLE;
            ball_spin <= 0;
            x <= {`W_LANE_CX, 14'd0};
            y <= {`W_BALL_Y0, 14'd0};
            vx <= 0;
            vy <= 0;
            slip <= 0;
            slip_left <= 0;
            roll_ticks <= 0;
            steer_q <= 0;
            steer_used <= 0;
            steer_ok <= 0;
            scan_rev <= 0;
            pin_rd_idx <= 0;
            ball_angle <= 0;
            roll_step <= 0;
            roll_pos <= 0;
            prx <= 0;
            pry <= 0;
            prvx <= 0;
            prvy <= 0;
            prs <= 0;
            prup <= 1'b1;
            dx_q <= 0;
            dy_q <= 0;
            far <= 0;
            kick <= 0;
            hook <= 0;
            in_oil <= 1'b1;
        end
        else begin
            // Steer window: collect sideways mouse motion for 0.5 s after release
            if (steer_valid && rolling && roll_ticks < `STEER_TICKS && st != S_MOVE)
                steer_q <= steer_new;

            // Load a new throw, or hold the ball at the stance while aiming
            if (throw_go) begin
                x <= {throw_x0, 14'd0};
                y <= {`W_BALL_Y0, 14'd0};
                vx <= {throw_vx, 8'd0};
                vy <= {throw_vy, 8'd0};
                ball_spin <= throw_spin;
                ball_phase <= `BP_SKID;
                slip <= spin_abs * rev_k;
                slip_left <= ~throw_spin[`SPIN_W-1];
                kick <= spin_abs * KICK_STEP;
                roll_ticks <= 0;
                steer_q <= 0;
                steer_used <= 0;
            end
            else if (aiming && idle && !throw_valid) begin
                ball_phase <= `BP_IDLE;
                x <= {stance_x, 14'd0};
                y <= {`W_BALL_Y0, 14'd0};
                vx <= 0;
                vy <= 0;
                slip <= 0;
                steer_q <= 0;
            end

            case (st)
                S_IDLE: begin
                    if (tick_phys) begin
                        if (rolling || ball_phase == `BP_GUTTER)
                            st <= S_OIL;
                        else
                            st <= S_DONE;
                    end
                end

                S_OIL: begin
                    st <= S_CALC;
                end

                // Friction from the oil ROM is ready: work out the hook force and the roll speed
                S_CALC: begin
                    hook <= hook_now;
                    in_oil <= (mu < MU_DRY);
                    steer_ok <= steer_max_ok;
                    roll_step <= {3'b000, vy[23:11]} + slip[23:8];
                    st <= S_MOVE;
                end

                // Move the ball one tick, apply hook and steering, then update the phase
                S_MOVE: begin
                    roll_pos <= roll_pos + roll_step;
                    ball_angle <= {roll_next[15:13], !slip_left, spin_look, 10'd0};
                    x <= nx[29:0];
                    y <= ny[29:0];
                    if (ball_phase != `BP_PIT)
                        vy <= vy_next;
                    if (roll_ticks != 11'h7FF)
                        roll_ticks <= roll_ticks + 11'd1;
                    // skid in the oil, hook while slip is left, roll once it is used up
                    if (rolling) begin
                        vx <= vx + (slip_left ? -$signed({1'b0, hook}) : $signed({1'b0, hook})) + steer_ok;
                        slip <= slip - hook;
                        steer_used <= steer_used + steer_ok;
                        steer_q <= 0;
                        if (in_oil)
                            ball_phase <= `BP_SKID;
                        else if (slip != hook)
                            ball_phase <= `BP_HOOK;
                        else
                            ball_phase <= `BP_ROLL;
                    end
                    // Past a lane edge before the deck: snap to the gutter centre
                    if (rolling && ball_y < `W_DECK_Y && (nx_pos < `W_LANE_L || nx_pos > `W_LANE_R)) begin
                        ball_phase <= `BP_GUTTER;
                        x <= {(nx_pos < `W_LANE_L) ? `W_GUT_LX : `W_GUT_RX, 14'd0};
                        vx <= 24'sd0;
                        slip <= 0;
                    end
                    // End of the lane: the ball is in the pit
                    if (ny[29:14] >= `W_BALL_PIT) begin
                        ball_phase <= `BP_PIT;
                        vx <= 0;
                        vy <= 0;
                    end
                    pin_rd_idx <= first_pin;
                    if (rolling)
                        st <= S_WAIT;
                    else
                        st <= S_DONE;
                end

                // Read one pin from Part C: wait for the read port, latch it, then compare distances
                S_WAIT: begin
                    st <= S_READ;
                end

                S_READ: begin
                    prx <= pin_rd_x;
                    pry <= pin_rd_y;
                    prvx <= pin_rd_vx;
                    prvy <= pin_rd_vy;
                    prs <= pin_rd_solid;
                    prup <= pin_rd_upright;
                    st <= S_DIST;
                end

                S_DIST: begin
                    dx_q <= pdx;
                    dy_q <= pdy;
                    far <= (adx > near) || (ady > near);
                    st <= S_CHECK;
                end

                S_CHECK: begin
                    if (!prs || far)
                        st <= S_NEXT;
                    else
                        st <= S_HIT;
                end

                // u_hit does the collision maths and sends the new ball speed back here
                S_HIT: begin
                    if (vx_wr)
                        vx <= vx - dbx;
                    if (vy_wr)
                        vy <= vy_hit;
                    if (hit_done)
                        st <= S_NEXT;
                end

                S_NEXT: begin
                    if (pin_rd_idx == last_pin)
                        st <= S_DONE;
                    else begin
                        if (scan_rev)
                            pin_rd_idx <= pin_rd_idx - 4'd1;
                        else
                            pin_rd_idx <= pin_rd_idx + 4'd1;
                        st <= S_WAIT;
                    end
                end

                // Tell Part C the scan is finished, so it can run its own update
                S_DONE: begin
                    scan_done <= 1'b1;
                    scan_rev <= ~scan_rev;
                    st <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule


// Ball constants for this oil setting and ball weight
module ball_settings (
    input  wire        long_oil,
    input  wire [1:0]  ball_lb,
    output wire [7:0]  dec_oil,
    output wire [7:0]  dec_dry,
    output wire [15:0] rev_k,
    output wire [17:0] kp,
    output wire [17:0] kb
);
    reg [63:0] param_rom [0:7];
    initial $readmemh("ball_params.mem", param_rom);

    // One ROM line per oil length and ball weight
    wire [63:0] param = param_rom[{long_oil, ball_lb}];

    assign dec_oil = param[63:56];
    assign dec_dry = param[55:48];
    assign rev_k   = param[47:32];
    assign kp      = {2'b00, param[31:16]};
    assign kb      = {2'b00, param[15:0]};
endmodule


// Lane friction at the ball's position
module ball_oil (
    input  wire        clk,
    input  wire        long_oil,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    output reg  [7:0]  mu
);
    reg [7:0] oil_rom [0:1023];
    initial $readmemh("oil_pattern.mem", oil_rom);

    // ROM address: oil setting, 16 in row along the lane, 4 in column out from the centre
    wire [9:0] y_in = ball_y[15:6];
    wire signed [10:0] xc = $signed({1'b0, ball_x[15:6]}) - 11'sd30;
    wire [10:0] axc = xc[10] ? -xc : xc;
    wire [2:0] xb = (axc[10:2] > 9'd7) ? 3'd7 : axc[4:2];
    wire [9:0] addr = {long_oil, (y_in[9:4] > 6'd47) ? 6'd47 : y_in[9:4], xb};

    always @ (posedge clk) begin
        mu <= oil_rom[addr];
    end
endmodule


// Remembers a throw until the FSM is free, so a throw is never lost
module ball_throw_latch (
    input  wire clk,
    input  wire rst,
    input  wire throw_valid,
    input  wire throwing,
    input  wire idle,
    output reg  pending
);
    always @ (posedge clk) begin
        if (rst || (pending && idle))
            pending <= 1'b0;
        else if (throw_valid && throwing)
            pending <= 1'b1;
    end
endmodule


// This tick's hook force and the ball's new forward speed
module ball_friction (
    input  wire [23:0] slip,
    input  wire [7:0]  mu,
    output wire [23:0] hook_now,
    input  wire signed [23:0] vy,
    input  wire [15:0] ball_y,
    input  wire        in_oil,
    input  wire [7:0]  dec_oil,
    input  wire [7:0]  dec_dry,
    input  wire [23:0] hook,
    output wire signed [23:0] vy_min,
    output wire signed [23:0] vy_next
);
    // The lane can take at most mu of side slip per tick
    assign hook_now = (slip < {16'd0, mu}) ? slip : {16'd0, mu};

    // Forward speed drops by friction plus half the hook.
    // The floor means the ball can never stop on the lane
    wire signed [23:0] vy_dec = vy - $signed({16'd0, in_oil ? dec_oil : dec_dry}) - $signed({1'b0, hook[23:1]});

    assign vy_min = (ball_y >= `W_DECK_Y) ? $signed({`W_SPEED_MIN_DECK, 8'd0}) : $signed({`W_SPEED_MIN, 8'd0});
    assign vy_next = (vy_dec < vy_min) ? vy_min : vy_dec;
endmodule


// Clamps mouse steering per packet and in total
module ball_steer (
    input  wire signed [11:0] steer_dx,
    input  wire signed [23:0] steer_q,
    input  wire signed [23:0] steer_used,
    output wire signed [23:0] steer_new,
    output wire signed [23:0] steer_ok
);
    localparam signed [23:0] STEER_MAX = 24'sd1536;

    // Limit each mouse packet to +-64 counts and the total steering to +-1536
    wire signed [11:0] sdx = (steer_dx > 12'sd64) ? 12'sd64 : (steer_dx < -12'sd64) ? -12'sd64 : steer_dx;
    wire signed [23:0] total = steer_used + steer_q;

    assign steer_new = steer_q + {{9{sdx[11]}}, sdx, 3'b000};
    assign steer_ok = (total > STEER_MAX) ? STEER_MAX - steer_used :
                      (total < -STEER_MAX) ? -STEER_MAX - steer_used : steer_q;
endmodule


// One pin's hit test and impulses. A product is ready 2 clocks after ma and mb are set.
module ball_hit #(
    parameter [15:0] R_DOWN = 16'd224
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        load,
    input  wire        start,
    input  wire        pin_skip,
    input  wire        clear_all,
    input  wire [3:0]  pin,
    input  wire [15:0] pin_x,
    input  wire [15:0] pin_y,
    input  wire signed [15:0] pin_vx,
    input  wire signed [15:0] pin_vy,
    input  wire        pin_up,
    input  wire signed [16:0] dx_in,
    input  wire signed [16:0] dy_in,
    input  wire signed [23:0] vx,
    input  wire signed [23:0] vy,
    input  wire signed [23:0] vy_min,
    input  wire        spin_neg,
    input  wire [17:0] kick,
    input  wire [17:0] kp,
    input  wire [17:0] kb,
    output reg         done,
    output wire        vx_wr,
    output wire signed [23:0] dbx,
    output wire        vy_wr,
    output wire signed [23:0] vy_hit,
    output reg         impulse_valid,
    output reg  [3:0]  impulse_pin,
    output reg  signed [15:0] impulse_vx,
    output reg  signed [15:0] impulse_vy,
    output reg         contact_pulse,
    output reg  [15:0] contact_px,
    output reg  [15:0] contact_py
);

    // ---------- 1. Constants and states ----------
    localparam [35:0] R2_HIT_UP = 36'd183869;
    localparam [35:0] R2_CLR_UP = 36'd201601;
    localparam [35:0] R2_HIT_DN = (R_DOWN + 36'd275) * (R_DOWN + 36'd275);
    localparam [35:0] R2_CLR_DN = (R_DOWN + 36'd288) * (R_DOWN + 36'd288);

    localparam [4:0] S_IDLE = 5'd0;
    localparam [4:0] S_P2   = 5'd1;
    localparam [4:0] S_P3   = 5'd2;
    localparam [4:0] S_P4   = 5'd3;
    localparam [4:0] S_P5   = 5'd4;
    localparam [4:0] S_N1   = 5'd5;
    localparam [4:0] S_N2   = 5'd6;
    localparam [4:0] S_N3   = 5'd7;
    localparam [4:0] S_N4   = 5'd8;
    localparam [4:0] S_N5   = 5'd9;
    localparam [4:0] S_N6   = 5'd10;
    localparam [4:0] S_N6B  = 5'd11;
    localparam [4:0] S_N7   = 5'd12;
    localparam [4:0] S_N8   = 5'd13;
    localparam [4:0] S_N9   = 5'd14;
    localparam [4:0] S_N10  = 5'd15;
    localparam [4:0] S_N11  = 5'd16;
    localparam [4:0] S_N12  = 5'd17;
    localparam [4:0] S_N13  = 5'd18;
    localparam [4:0] S_N14  = 5'd19;
    localparam [4:0] S_N14B = 5'd20;
    localparam [4:0] S_T2   = 5'd21;
    localparam [4:0] S_T3   = 5'd22;
    localparam [4:0] S_T4   = 5'd23;
    localparam [4:0] S_T5   = 5'd24;

    reg [4:0] st;

    // ---------- 2. Inverse length table and shared multiplier ----------
    reg [8:0] inv_rom [0:127];
    initial $readmemh("inv_len.mem", inv_rom);

    reg  signed [24:0] ma;
    reg  signed [17:0] mb;
    wire signed [42:0] mp;
    mul_s25x18 u_mul (.clk(clk), .a(ma), .b(mb), .p(mp));

    // arithmetic shift that rounds toward zero, so left and right hits are mirror images
    function signed [42:0] sra0;
        input signed [42:0] v;
        input [4:0] s;
        sra0 = v[42] ? -((-v) >>> s) : (v >>> s);
    endfunction

    // ---------- 3. Working registers ----------
    reg [9:0] touching;
    reg signed [16:0] dx, dy, relx, rely;
    reg [35:0] d2_a, d2;
    reg [17:0] inv;
    reg signed [17:0] nx, ny;
    reg signed [42:0] t;
    reg signed [24:0] vrn, sp, sb, tq;
    reg        vpos;
    reg signed [15:0] dpx, dpy, tdx;
    reg signed [23:0] dbx_q, dby;

    // Contact distance is compared squared, so no square root is needed
    wire [35:0] r2_hit = pin_up ? R2_HIT_UP : R2_HIT_DN;
    wire [35:0] r2_clr = pin_up ? R2_CLR_UP : R2_CLR_DN;
    wire [35:0] d2_full = d2_a + mp[35:0];
    wire signed [42:0] vrn_full = sra0(t + mp, 5'd14);
    wire in_reach = (d2 < r2_hit);
    wire pushed = touching[pin] && pin_up;

    // Finished with this pin: the same choices as the FSM below makes
    always @ (*) begin
        done = 1'b0;
        if (st == S_P5) begin
            if (in_reach) begin
                if (pushed)
                    done = 1'b1;
            end
            else
                done = 1'b1;
        end
        else if (st == S_N6B) begin
            if (!vpos)
                done = 1'b1;
        end
        else if (st == S_T5)
            done = 1'b1;
    end

    assign vx_wr = (st == S_N14);
    assign dbx = dbx_q;
    assign vy_wr = (st == S_N14B);
    assign vy_hit = ((vy - dby) < vy_min) ? vy_min : vy - dby;

    // ---------- 4. FSM: distance, unit normal, approach speed, impulses, spin kick ----------
    always @ (posedge clk) begin
        impulse_valid <= 1'b0;
        contact_pulse <= 1'b0;
        if (rst) begin
            st <= S_IDLE;
            touching <= 0;
            ma <= 0;
            mb <= 0;
            dx <= 0;
            dy <= 0;
            relx <= 0;
            rely <= 0;
            d2_a <= 0;
            d2 <= 0;
            inv <= 0;
            nx <= 0;
            ny <= 0;
            t <= 0;
            vrn <= 0;
            vpos <= 0;
            sp <= 0;
            sb <= 0;
            tq <= 0;
            dpx <= 0;
            dpy <= 0;
            tdx <= 0;
            dbx_q <= 0;
            impulse_pin <= 0;
            impulse_vx <= 0;
            impulse_vy <= 0;
            contact_px <= 0;
            contact_py <= 0;
        end
        else begin
            if (clear_all)
                touching <= 0;

            // Latch this pin distance and the speed of the ball relative to the pin
            if (load) begin
                dx <= dx_in;
                dy <= dy_in;
                relx <= $signed(vx[23:8]) - pin_vx;
                rely <= $signed(vy[23:8]) - pin_vy;
            end

            // A pin that is skipped is no longer being touched
            if (pin_skip)
                touching[pin] <= 1'b0;

            case (st)
                // Squared distance: dx^2 + dy^2 using two multiplies
                S_IDLE: begin
                    if (start) begin
                        ma <= dx_in;
                        mb <= dx_in;
                        st <= S_P2;
                    end
                end

                S_P2: begin
                    ma <= dy;
                    mb <= dy;
                    st <= S_P3;
                end

                S_P3: begin
                    d2_a <= mp[35:0];
                    st <= S_P4;
                end

                S_P4: begin
                    d2 <= d2_full;
                    st <= S_P5;
                end

                // In reach and not already pushed: start the normal. Moved away: clear the touching flag
                S_P5: begin
                    if (in_reach) begin
                        if (pushed)
                            st <= S_IDLE;
                        else begin
                            inv <= {9'd0, inv_rom[d2[18:12]]};
                            ma <= dx;
                            mb <= {9'd0, inv_rom[d2[18:12]]};
                            st <= S_N1;
                        end
                    end
                    else begin
                        if (d2 > r2_clr)
                            touching[pin] <= 1'b0;
                        st <= S_IDLE;
                    end
                end

                // Unit normal: n = d * 1/|d|, with 1/|d| from the ROM
                S_N1: begin
                    ma <= dy;
                    mb <= inv;
                    st <= S_N2;
                end

                S_N2: begin
                    nx <= mp[17:0];
                    st <= S_N3;
                end

                // Approach speed along the normal. Bodies moving apart get no impulse
                S_N3: begin
                    ny <= mp[17:0];
                    ma <= relx;
                    mb <= nx;
                    st <= S_N4;
                end

                S_N4: begin
                    ma <= rely;
                    mb <= ny;
                    st <= S_N5;
                end

                S_N5: begin
                    t <= mp;
                    st <= S_N6;
                end

                S_N6: begin
                    touching[pin] <= 1'b1;
                    vrn <= vrn_full[24:0];
                    vpos <= (vrn_full > 0);
                    st <= S_N6B;
                end

                // Pin gets kp * speed and ball gets kb * speed along n.
                // Both come from one ROM line, so momentum is conserved
                S_N6B: begin
                    if (!vpos)
                        st <= S_IDLE;
                    else begin
                        ma <= vrn;
                        mb <= kp;
                        st <= S_N7;
                    end
                end

                S_N7: begin
                    ma <= vrn;
                    mb <= kb;
                    st <= S_N8;
                end

                S_N8: begin
                    sp <= mp >>> 12;
                    st <= S_N9;
                end

                S_N9: begin
                    sb <= mp >>> 12;
                    ma <= sp;
                    mb <= nx;
                    st <= S_N10;
                end

                S_N10: begin
                    ma <= sp;
                    mb <= ny;
                    st <= S_N11;
                end

                S_N11: begin
                    dpx <= sra0(mp, 5'd14);
                    ma <= sb;
                    mb <= nx;
                    st <= S_N12;
                end

                S_N12: begin
                    dpy <= sra0(mp, 5'd14);
                    contact_pulse <= 1'b1;
                    contact_px <= pin_x;
                    contact_py <= pin_y;
                    ma <= sb;
                    mb <= ny;
                    st <= S_N13;
                end

                // Friction kick from the spin, applied along the tangent (-ny, nx)
                S_N13: begin
                    dbx_q <= sra0(mp, 5'd6);
                    ma <= sp;
                    mb <= kick;
                    st <= S_N14;
                end

                S_N14: begin
                    dby <= sra0(mp, 5'd6);
                    st <= S_N14B;
                end

                S_N14B: begin
                    tq <= mp >>> 12;
                    st <= S_T2;
                end

                S_T2: begin
                    ma <= tq;
                    mb <= ny;
                    st <= S_T3;
                end

                S_T3: begin
                    ma <= tq;
                    mb <= nx;
                    st <= S_T4;
                end

                S_T4: begin
                    tdx <= sra0(mp, 5'd14);
                    st <= S_T5;
                end

                // Send the pin its total impulse. The tangent sign follows the spin direction
                S_T5: begin
                    impulse_valid <= 1'b1;
                    impulse_pin <= pin;
                    if (spin_neg) begin
                        impulse_vx <= dpx + tdx;
                        impulse_vy <= dpy - sra0(mp, 5'd14);
                    end
                    else begin
                        impulse_vx <= dpx - tdx;
                        impulse_vy <= dpy + sra0(mp, 5'd14);
                    end
                    st <= S_IDLE;
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
