`timescale 1ns / 1ps
`include "strike_defs.vh"
// persp_proj.v : where the ball and the pins appear in the first-person view
// Owner: Student B

(* use_dsp = "yes" *)
module persp_proj (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire signed [10:0] cam_fp,
    input  wire [15:0] k_fp,
    input  wire        ball_visible,
    input  wire [15:0] ball_x,
    input  wire [15:0] ball_y,
    input  wire [239:0] pin_vis,
    output reg         b_vis,
    output reg  signed [9:0] b_x,
    output reg  [7:0]  b_row,
    output reg  [3:0]  b_rad,
    output wire [359:0] pins_fp,
    output reg  [7:0]  rp_mu,
    output reg  [7:0]  rp_bw,
    output reg  [15:0] mu_step
);

    // ---------- 1. Constants and states ----------
    localparam signed [11:0] Y_MU = 12'sd700;
    localparam signed [11:0] Y_BW = 12'sd790;

    localparam [4:0] S_IDLE = 5'd0;
    localparam [4:0] S_PRE  = 5'd1;
    localparam [4:0] S_SEL0 = 5'd2;
    localparam [4:0] S_SEL  = 5'd3;
    localparam [4:0] S_DIV  = 5'd4;
    localparam [4:0] S_WAIT = 5'd5;
    localparam [4:0] S_RES  = 5'd6;
    localparam [4:0] S_MUL  = 5'd7;
    localparam [4:0] S_MUL2 = 5'd8;
    localparam [4:0] S_MUL3 = 5'd9;
    localparam [4:0] S_MUL4 = 5'd10;
    localparam [4:0] S_OUT  = 5'd11;
    localparam [4:0] S_WR   = 5'd12;
    localparam [4:0] S_B0   = 5'd13;
    localparam [4:0] S_B0W  = 5'd14;
    localparam [4:0] S_B1   = 5'd15;
    localparam [4:0] S_B1W  = 5'd16;
    localparam [4:0] S_B2   = 5'd17;
    localparam [4:0] S_B2W  = 5'd18;

    reg [4:0] st;

    // ---------- 2. Divider, one projection at a time (object 0 = ball, 1..10 = pins) ----------
    reg  [3:0]  obj;
    reg         dv_start;
    reg  [15:0] dv_num, dv_den;
    wire [15:0] dv_quo;
    wire        dv_done;

    div_seq #(.W(16)) u_div (
        .clk(clk),
        .rst(rst),
        .start(dv_start),
        .num(dv_num),
        .den(dv_den),
        .quo(dv_quo),
        .done(dv_done),
        .busy()
    );

    // ---------- 3. What kind of pin this object is ----------
    reg  [23:0] pin_word;
    wire        pin_up, pin_bar, pin_lean;
    wire signed [1:0] dir_x;
    wire [5:0]  ext_x, ext_y;

    persp_pin u_pin (
        .pin_word(pin_word),
        .pin_up(pin_up),
        .pin_bar(pin_bar),
        .pin_lean(pin_lean),
        .dir_x(dir_x),
        .ext_x(ext_x),
        .ext_y(ext_y)
    );

    reg  signed [11:0] base_x, base_y;
    reg         on_q, bar_q, lean_q;
    reg  signed [1:0] dir_q;
    reg  [5:0]  ex_q, ey_q;

    // ---------- 4. Sizes on screen, from r ----------
    reg  [7:0]  r;
    reg  signed [11:0] wx, dz;
    reg         obj_on, obj_bar, obj_lean;
    reg  signed [1:0] obj_dir;
    reg  [5:0]  obj_ex, obj_ey;
    reg  signed [21:0] xo_q;
    reg  [15:0] rr_q;
    reg  [15:0] hw_q;
    reg  [26:0] dep_q;
    reg  [4:0]  cls_q;
    reg  [3:0]  rad_q, th_q;
    reg  [35:0] word_q;
    reg  [4:0]  hw5_q, hh5_q, neck_q;
    reg  signed [9:0] xpos_q, lean_x_q;
    reg  [7:0]  row_q;

    // x offset = (wx - 30) * r / 51, done as r * 5 >> 8
    wire [9:0]  r5 = {r, 2'b00} + {2'b00, r};
    wire signed [21:0] xo = ((wx - 12'sd30) * $signed({1'b0, r5})) >>> 8;
    wire [4:0]  cls;
    wire [3:0]  rad, th;

    persp_size u_size (
        .r(r),
        .cls(cls),
        .rad(rad),
        .th(th)
    );

    // Size of a lying pin on screen, limited to fit the 5-bit fields of the pin word
    wire [9:0]  dep = dep_q[26:19] > 8'd200 ? 10'd200 : {2'b00, dep_q[26:19]};
    wire [9:0]  th_r = {6'd0, th_q};
    wire [9:0]  hw_full = {4'd0, hw_q[15:10]};
    wire [4:0]  hw5 = (hw_full > 10'd31) ? 5'd31 : (hw_full == 0) ? 5'd1 : hw_full[4:0];
    wire [9:0]  hh_s = (th_r + dep + 10'd1) >> 1;
    wire [4:0]  hh5 = (hh_s > 10'd31) ? 5'd31 : (hh_s == 0) ? 5'd1 : hh_s[4:0];
    wire [4:0]  nk = (hw5 >> 1);
    wire [4:0]  neck = (obj_dir == 0) ? 5'd0 : (obj_dir > 0) ? {1'b0, nk[3:0]} : -{1'b0, nk[3:0]};
    wire signed [9:0] xpos = $signed({1'b0, `H_CX}) + xo_q[9:0];
    wire signed [9:0] lean_x = obj_lean ? (obj_dir * $signed({6'd0, r[7], ~r[7], 1'b0})) : 10'sd0;

    // Distance from the camera to the masking unit and to the curtain
    wire signed [11:0] d_mu = Y_MU - $signed({cam_fp[10], cam_fp});
    wire signed [11:0] d_bw = Y_BW - $signed({cam_fp[10], cam_fp});

    // ---------- 5. Finished pin words ----------
    reg [35:0] pf [0:9];
    genvar g;
    generate
        for (g = 0; g < 10; g = g + 1) begin : g_o
            assign pins_fp[36*g +: 36] = pf[g];
        end
    endgenerate

    // ---------- 6. FSM: 11 objects, then the 2 backdrop planes, once per frame ----------
    integer q;
    always @ (posedge clk) begin
        dv_start <= 1'b0;
        if (rst) begin
            st <= S_IDLE;
            obj <= 0;
            dv_num <= 0;
            dv_den <= 1;
            wx <= 0;
            dz <= 0;
            obj_on <= 0;
            obj_bar <= 0;
            obj_lean <= 0;
            obj_dir <= 0;
            obj_ex <= 0;
            obj_ey <= 0;
            r <= 0;
            xo_q <= 0;
            rr_q <= 0;
            hw_q <= 0;
            dep_q <= 0;
            pin_word <= 0;
            cls_q <= 0;
            rad_q <= 1;
            th_q <= 0;
            word_q <= 0;
            b_vis <= 0;
            b_x <= 0;
            b_row <= 0;
            b_rad <= 0;
            rp_mu <= 8'd8;
            rp_bw <= 8'd7;
            mu_step <= 16'd6528;
            for (q = 0; q < 10; q = q + 1)
                pf[q] <= 36'd0;
        end
        else begin
            case (st)
                S_IDLE: begin
                    if (tick_frame) begin
                        obj <= 4'd0;
                        st <= S_PRE;
                    end
                end

                // Pick the next object: the ball for obj 0, otherwise pin obj - 1
                S_PRE: begin
                    pin_word <= pin_vis[24 * (obj - 4'd1) +: 24];
                    st <= S_SEL0;
                end

                S_SEL0: begin
                    if (obj == 0) begin
                        base_x <= $signed({2'b00, ball_x[15:6]});
                        base_y <= $signed({2'b00, ball_y[15:6]});
                        on_q <= ball_visible;
                    end
                    else begin
                        base_x <= $signed({6'd0, pin_word[23:18]});
                        base_y <= $signed({2'b00, pin_word[17:8]});
                        on_q <= (pin_up || pin_bar);
                    end
                    bar_q <= (obj != 0) && pin_bar;
                    lean_q <= (obj != 0) && pin_lean;
                    dir_q <= dir_x;
                    ex_q <= ext_x;
                    ey_q <= ext_y;
                    st <= S_SEL;
                end

                S_SEL: begin
                    wx <= base_x;
                    dz <= base_y - $signed({cam_fp[10], cam_fp});
                    obj_on <= on_q;
                    obj_bar <= bar_q;
                    obj_lean <= lean_q;
                    obj_dir <= dir_q;
                    obj_ex <= ex_q;
                    obj_ey <= ey_q;
                    st <= S_DIV;
                end

                // Hidden or too close: skip it. Otherwise divide to get r = 2K / dz
                S_DIV: begin
                    if (!obj_on || dz < 12'sd35) begin
                        if (obj == 0)
                            b_vis <= 1'b0;
                        else
                            pf[obj - 4'd1] <= 36'd0;
                        if (obj == 4'd10)
                            st <= S_B0;
                        else begin
                            obj <= obj + 4'd1;
                            st <= S_PRE;
                        end
                    end
                    else begin
                        dv_num <= {k_fp[14:0], 1'b0};
                        dv_den <= {4'd0, dz};
                        dv_start <= 1'b1;
                        st <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (dv_done)
                        st <= S_RES;
                end

                // A very large r would land below the screen, so skip that object too
                S_RES: begin
                    if (dv_quo > 16'd180) begin
                        if (obj == 0)
                            b_vis <= 1'b0;
                        else
                            pf[obj - 4'd1] <= 36'd0;
                        if (obj == 4'd10)
                            st <= S_B0;
                        else begin
                            obj <= obj + 4'd1;
                            st <= S_PRE;
                        end
                    end
                    else begin
                        r <= (dv_quo > 16'd179) ? 8'd179 : dv_quo[7:0];
                        st <= S_MUL;
                    end
                end

                // Screen position and sizes from r, split over a few clocks for timing
                S_MUL: begin
                    xo_q <= xo;
                    rr_q <= r * r;
                    hw_q <= obj_ex * r5;
                    st <= S_MUL2;
                end

                S_MUL2: begin
                    dep_q <= obj_ey * rr_q * 5'd21;
                    st <= S_MUL3;
                end

                S_MUL3: begin
                    cls_q <= cls;
                    rad_q <= rad;
                    th_q <= th;
                    st <= S_MUL4;
                end

                S_MUL4: begin
                    hw5_q <= hw5;
                    hh5_q <= hh5;
                    neck_q <= neck;
                    xpos_q <= xpos;
                    lean_x_q <= lean_x;
                    row_q <= 8'd60 + r - (obj_bar ? {5'd0, th_q[3:1]} : 8'd0);
                    st <= S_OUT;
                end

                // Build the ball outputs or the 36-bit pin word, then store it
                S_OUT: begin
                    if (obj == 0) begin
                        b_vis <= 1'b1;
                        b_x <= xpos_q;
                        b_row <= row_q;
                        b_rad <= rad_q;
                    end
                    else if (obj_bar)
                        word_q <= {1'b1, 1'b1, xpos_q, row_q, hw5_q, hh5_q, neck_q, 1'b0};
                    else
                        word_q <= {1'b1, 1'b0, xpos_q + lean_x_q, row_q, cls_q, 5'd0, 5'd0, 1'b0};
                    st <= S_WR;
                end

                S_WR: begin
                    if (obj != 0)
                        pf[obj - 4'd1] <= word_q;
                    if (obj == 4'd10)
                        st <= S_B0;
                    else begin
                        obj <= obj + 4'd1;
                        st <= S_PRE;
                    end
                end

                // Backdrop planes use the same r = 2K / d
                S_B0: begin
                    dv_num <= {k_fp[14:0], 1'b0};
                    dv_den <= (d_mu < 12'sd1) ? 16'd1 : {4'd0, d_mu};
                    dv_start <= 1'b1;
                    st <= S_B0W;
                end

                S_B0W: begin
                    if (dv_done) begin
                        rp_mu <= (dv_quo > 16'd255) ? 8'd255 : (dv_quo == 16'd0) ? 8'd1 : dv_quo[7:0];
                        st <= S_B1;
                    end
                end

                S_B1: begin
                    dv_num <= {k_fp[14:0], 1'b0};
                    dv_den <= (d_bw < 12'sd1) ? 16'd1 : {4'd0, d_bw};
                    dv_start <= 1'b1;
                    st <= S_B1W;
                end

                S_B1W: begin
                    if (dv_done) begin
                        rp_bw <= (dv_quo > 16'd255) ? 8'd255 : (dv_quo == 16'd0) ? 8'd1 : dv_quo[7:0];
                        st <= S_B2;
                    end
                end

                // Step across the panel for each pixel, used by backdrop_render
                S_B2: begin
                    dv_num <= 16'd52224;
                    dv_den <= {8'd0, rp_mu};
                    dv_start <= 1'b1;
                    st <= S_B2W;
                end

                S_B2W: begin
                    if (dv_done) begin
                        mu_step <= dv_quo;
                        st <= S_IDLE;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end
endmodule


// Upright or lying, fall direction and size of one pin's word
(* use_dsp = "yes" *)
module persp_pin (
    input  wire [23:0] pin_word,
    output wire        pin_up,
    output wire        pin_bar,
    output wire        pin_lean,
    output wire signed [1:0] dir_x,
    output wire [5:0]  ext_x,
    output wire [5:0]  ext_y
);
    // Fields of the pin word from Part C: state, fall direction, fall stage
    wire [2:0] ps = pin_word[7:5];
    wire [2:0] pd = pin_word[4:2];
    wire [1:0] pg = pin_word[1:0];

    wire falling = (ps == `PS_FALLING);
    wire diag    = (pd[0] == 1'b1);

    wire signed [1:0] dir_y = (pd == 3'd7 || pd == 3'd0 || pd == 3'd1) ? 2'sd1 :
                              (pd == 3'd3 || pd == 3'd4 || pd == 3'd5) ? -2'sd1 : 2'sd0;
    wire [5:0] ext_long = diag ? (falling ? 6'd15 : 6'd26) : (falling ? 6'd20 : 6'd35);

    // Upright pins use a silhouette, lying pins use a bar along their fall direction
    assign pin_up   = (ps == `PS_STANDING) || (ps == `PS_WOBBLING) || (falling && pg == 2'd0);
    assign pin_bar  = (ps == `PS_DOWN) || (falling && pg != 2'd0);
    assign pin_lean = falling && (pg == 2'd0);
    assign dir_x = (pd == 3'd1 || pd == 3'd2 || pd == 3'd3) ? 2'sd1 :
                   (pd == 3'd5 || pd == 3'd6 || pd == 3'd7) ? -2'sd1 : 2'sd0;
    assign ext_x = (dir_x == 0) ? 6'd5 : ext_long;
    assign ext_y = (dir_y == 0) ? 6'd5 : ext_long;
endmodule


// Pin size class, ball radius and lying pin thickness for row r
(* use_dsp = "yes" *)
module persp_size (
    input  wire [7:0] r,
    output reg  [4:0] cls,
    output wire [3:0] rad,
    output wire [3:0] th
);
    // Sizes scale with r, as a multiply and a shift
    wire [14:0] h75   = r * 7'd75;
    wire [6:0]  h     = h75[14:8];
    wire [12:0] rad22 = r * 5'd22;
    wire [11:0] th12  = r * 4'd12;

    assign rad = (rad22[12:8] == 0) ? 4'd1 : (rad22[12:8] > 5'd15) ? 4'd15 : rad22[11:8];
    assign th  = th12[11:8];

    // Pin height on screen picks one of the pin size classes
    always @ (*) begin
        if      (h >= 7'd53) cls = 5'd31;
        else if (h >= 7'd50) cls = 5'd30;
        else if (h >= 7'd48) cls = 5'd29;
        else if (h >= 7'd46) cls = 5'd28;
        else if (h >= 7'd44) cls = 5'd27;
        else if (h >= 7'd42) cls = 5'd26;
        else if (h >= 7'd40) cls = 5'd25;
        else if (h >= 7'd38) cls = 5'd24;
        else if (h >= 7'd36) cls = 5'd23;
        else if (h >= 7'd34) cls = 5'd22;
        else if (h >= 7'd32) cls = 5'd21;
        else if (h >= 7'd30) cls = 5'd20;
        else if (h >= 7'd28) cls = 5'd19;
        else if (h >= 7'd26) cls = 5'd18;
        else if (h >= 7'd24) cls = 5'd17;
        else if (h >= 7'd22) cls = 5'd16;
        else if (h >= 7'd20) cls = 5'd15;
        else if (h >= 7'd18) cls = 5'd14;
        else if (h >= 7'd16) cls = 5'd13;
        else if (h >= 7'd14) cls = 5'd12;
        else if (h >= 7'd13) cls = 5'd11;
        else if (h >= 7'd12) cls = 5'd10;
        else if (h >= 7'd11) cls = 5'd9;
        else if (h >= 7'd10) cls = 5'd8;
        else if (h >= 7'd9)  cls = 5'd7;
        else if (h >= 7'd8)  cls = 5'd6;
        else if (h >= 7'd7)  cls = 5'd5;
        else if (h >= 7'd6)  cls = 5'd4;
        else if (h >= 7'd5)  cls = 5'd3;
        else if (h >= 7'd4)  cls = 5'd2;
        else if (h >= 7'd3)  cls = 5'd1;
        else                 cls = 5'd0;
    end
endmodule
