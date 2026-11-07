`timescale 1ns / 1ps
// mouse_setup.v : MouseCtl configuration, movement deltas, cursor, buttons
// Owner: Student A
`include "strike_defs.vh"

module mouse_setup (
    input  wire        clk,
    input  wire        rst,
    input  wire [11:0] m_xpos,
    input  wire [11:0] m_ypos,
    input  wire [3:0]  m_zpos,
    input  wire        m_left,
    input  wire        m_middle,
    input  wire        m_right,
    input  wire        m_new_event,
    output reg  [11:0] m_value,
    output reg         m_setx,
    output reg         m_sety,
    output reg         m_setmax_x,
    output reg         m_setmax_y,
    input  wire [1:0]  sens,
    output wire [7:0]  cursor_x,
    output wire [6:0]  cursor_y,
    output wire [6:0]  ucur_x,
    output wire [5:0]  ucur_y,
    output reg         delta_valid,
    output reg  signed [11:0] delta_x,
    output reg  signed [11:0] delta_y,
    output reg  signed [3:0]  wheel,
    output reg         l_level,
    output reg         r_level,
    output reg         m_level,
    output reg         l_press,
    output reg         l_release,
    output reg         r_press,
    output reg         m_press
);
    localparam CENTRE = 12'd2048;
    localparam QX_MAX = 10'd639;
    localparam QY_MAX = 10'd479;

    localparam S_MAX = 3'd0, S_CEN = 3'd1, S_RUN = 3'd2, S_WAIT = 3'd3,
               S_READ = 3'd4, S_OUT = 3'd5;
    reg [2:0] state;
    reg [1:0] wait_cnt;
    reg signed [12:0] raw_x, raw_y;
    reg signed [3:0]  raw_z;

    reg signed [12:0] half_x, half_y;
    reg signed [12:0] sx, sy;
    always @(*) begin
        if (raw_x < 0) half_x = -((-raw_x) >>> 1);
        else half_x = raw_x >>> 1;
        if (raw_y < 0) half_y = -((-raw_y) >>> 1);
        else half_y = raw_y >>> 1;
        sx = raw_x;
        sy = raw_y;
        case (sens)
            0: begin sx = half_x; sy = half_y; end
            1: begin sx = raw_x; sy = raw_y; end
            2: begin sx = raw_x + half_x; sy = raw_y + half_y; end
            3: begin sx = raw_x <<< 1; sy = raw_y <<< 1; end
        endcase
    end

    always @(posedge clk) begin
        m_setx <= 1'b0;
        m_sety <= 1'b0;
        m_setmax_x <= 1'b0;
        m_setmax_y <= 1'b0;
        delta_valid <= 1'b0;
        if (rst) begin
            state   <= S_MAX;
            m_value <= 12'd4095;
            raw_x <= 0;
            raw_y <= 0;
            raw_z <= 0;
            delta_x <= 0;
            delta_y <= 0;
            wheel <= 0;
            wait_cnt <= 0;
        end else begin
            case (state)
                S_MAX: begin
                    m_value <= 12'd4095;
                    m_setmax_x <= 1'b1;
                    m_setmax_y <= 1'b1;
                    state <= S_CEN;
                end
                S_CEN: begin
                    m_value <= CENTRE;
                    m_setx <= 1'b1;
                    m_sety <= 1'b1;
                    state <= S_RUN;
                end
                S_RUN: begin
                    m_value <= CENTRE;
                    wait_cnt <= 2'd0;
                    if (m_new_event) state <= S_WAIT;
                end
                S_WAIT: begin
                    wait_cnt <= wait_cnt + 2'd1;
                    if (wait_cnt == 2'd3) state <= S_READ;
                end
                S_READ: begin
                    raw_x <= $signed({1'b0, m_xpos}) - $signed({1'b0, CENTRE});
                    raw_y <= $signed({1'b0, m_ypos}) - $signed({1'b0, CENTRE});
                    raw_z <= m_zpos;
                    m_setx <= 1'b1;
                    m_sety <= 1'b1;
                    state <= S_OUT;
                end
                S_OUT: begin
                    delta_x <= sx[11:0];
                    delta_y <= sy[11:0];
                    wheel   <= raw_z;
                    delta_valid <= 1'b1;
                    state <= S_RUN;
                end
                default: state <= S_MAX;
            endcase
        end
    end

    reg [9:0] qx, qy;
    wire signed [12:0] nx = $signed({3'b000, qx}) + $signed(delta_x);
    wire signed [12:0] ny = $signed({3'b000, qy}) + $signed(delta_y);
    always @(posedge clk) begin
        if (rst) begin
            qx <= 10'd320;
            qy <= 10'd240;
        end else if (delta_valid) begin
            if ((nx < 0)) begin
                qx <= 10'd0;
            end else begin
                if ((nx > $signed({3'b000, QX_MAX}))) begin
                    qx <= QX_MAX;
                end else begin
                    qx <= nx[9:0];
                end
            end
            if ((ny < 0)) begin
                qy <= 10'd0;
            end else begin
                if ((ny > $signed({3'b000, QY_MAX}))) begin
                    qy <= QY_MAX;
                end else begin
                    qy <= ny[9:0];
                end
            end
        end
    end
    assign cursor_x = qx[9:2];
    assign cursor_y = qy[8:2];
    wire signed [8:0] uxs = $signed({1'b0, cursor_x}) - $signed({1'b0, `UI_X0});
    wire signed [8:0] uys = $signed({2'b00, cursor_y}) - $signed({2'b00, `UI_Y0});
    assign ucur_x = (uxs < 0) ? 7'd0 : (uxs > 9'sd95) ? 7'd95 : uxs[6:0];
    assign ucur_y = (uys < 0) ? 6'd0 : (uys > 9'sd63) ? 6'd63 : uys[5:0];

    reg [2:0] btn_s;
    reg       btn_go;
    always @(posedge clk) begin
        l_press <= 1'b0;
        l_release <= 1'b0;
        r_press <= 1'b0;
        m_press <= 1'b0;
        btn_go  <= delta_valid;
        if (rst) begin
            l_level <= 1'b0;
            r_level <= 1'b0;
            m_level <= 1'b0;
            btn_s <= 3'b000;
            btn_go <= 1'b0;
        end else begin
            if (state == S_READ) btn_s <= {m_left, m_right, m_middle};
            if (btn_go) begin
                l_level <= btn_s[2];
                r_level <= btn_s[1];
                m_level <= btn_s[0];
                l_press   <=  btn_s[2] & ~l_level;
                l_release <= ~btn_s[2] &  l_level;
                r_press   <=  btn_s[1] & ~r_level;
                m_press   <=  btn_s[0] & ~m_level;
            end
        end
    end
endmodule
