`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// mouse_setup.v : MouseCtl configuration, movement deltas, cursor, buttons
//-----------------------------------------------------------------------------
// Owner   : Student A
// Purpose : MouseCtl (provided, unchanged) keeps an absolute position that it
//           CLAMPS to [0, max]. A forward flick moves the mouse ~1000 counts
//           (MouseCtl sets 8 counts/mm), far more than a 256-count screen
//           range, so a clamped position would stop changing in the middle
//           of a throw. We therefore use MouseCtl as a DELTA source:
//             1. at reset: setmax_x = setmax_y = 4095, then x = y = 2048
//             2. after every packet (new_event) read xpos/ypos, the delta is
//                pos - 2048, then put the position back to 2048 (setx/sety)
//           A packet moves at most +-255 counts, so 2048 never clamps.
//           Packets come every 25 ms (MouseCtl asks for 40 samples/s) and
//           x_pos/y_pos are written in packet byte 2/3, ~2 ms BEFORE
//           new_event, so the read and re-centre can never collide with an
//           update.
//           The deltas are scaled by the sensitivity setting with shifts
//           (x0.5, x1, x1.5, x2) and accumulated into a cursor kept in
//           quarter pixels (0..383 x 0..255), which gives smooth sub-pixel
//           motion; the pixel cursor is that value >> 2.
// Ports
//   m_*          MouseCtl ports
//   sens         settings[5:4]
//   cursor_x/y   pointer in pixels (0..95, 0..63)
//   delta_valid  1-cycle pulse per packet; delta_x/y scaled counts, screen
//                axes (+x right, +y DOWN, so a forward swipe is negative y)
//   (v3) the cursor covers the VGA screen (quarter pixels 0..639 x 0..479);
//                ucur_x/y is the same point in the 96 x 64 UI window
//   wheel        signed wheel steps of that packet
//   l_level ...  button levels, *_press / l_release 1-cycle edges
//=============================================================================
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
    output wire [7:0]  cursor_x,         // v3: VGA pixels 0..159
    output wire [6:0]  cursor_y,         //               0..119
    output wire [6:0]  ucur_x,           // v3: the same point in UI space (0..95)
    output wire [5:0]  ucur_y,           //     (VGA minus the window offset, clamped)
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
    localparam QX_MAX = 10'd639;           // 160 px * 4 - 1 (v3: the VGA screen)
    localparam QY_MAX = 10'd479;           // 120 px * 4 - 1

    // ---------------- (1) state register ------------------------------------
    localparam S_MAX = 3'd0, S_CEN = 3'd1, S_RUN = 3'd2, S_WAIT = 3'd3,
               S_READ = 3'd4, S_OUT = 3'd5;
    reg [2:0] state;
    reg [1:0] wait_cnt;
    reg signed [12:0] raw_x, raw_y;         // pos - 2048
    reg signed [3:0]  raw_z;

    // ---------------- sensitivity scaling (shifts only) ---------------------
    // v3: the halves round toward ZERO (an arithmetic >>> rounds toward -inf,
    // which made small moves drift left / forward). Symmetric for +d and -d.
    function signed [12:0] half0;                   // d / 2, toward zero
        input signed [12:0] d;
        half0 = d[12] ? -((-d) >>> 1) : (d >>> 1);
    endfunction
    function signed [12:0] scale;
        input signed [12:0] d;
        input [1:0] s;
        case (s)
            2'd0:    scale = half0(d);              // x0.5
            2'd1:    scale = d;                     // x1
            2'd2:    scale = d + half0(d);          // x1.5
            default: scale = d <<< 1;               // x2
        endcase
    endfunction
    wire signed [12:0] sx = scale(raw_x, sens);
    wire signed [12:0] sy = scale(raw_y, sens);

    // ---------------- (2)+(3) FSM: next state and outputs --------------------
    always @(posedge clk) begin
        m_setx <= 1'b0; m_sety <= 1'b0; m_setmax_x <= 1'b0; m_setmax_y <= 1'b0;
        delta_valid <= 1'b0;
        if (rst) begin
            state   <= S_MAX;
            m_value <= 12'd4095;
            raw_x <= 0; raw_y <= 0; raw_z <= 0;
            delta_x <= 0; delta_y <= 0; wheel <= 0;
            wait_cnt <= 0;
        end else begin
            case (state)
                S_MAX: begin                       // both limits in one cycle
                    m_value <= 12'd4095;
                    m_setmax_x <= 1'b1; m_setmax_y <= 1'b1;
                    state <= S_CEN;
                end
                S_CEN: begin
                    m_value <= CENTRE;
                    m_setx <= 1'b1; m_sety <= 1'b1;
                    state <= S_RUN;
                end
                S_RUN: begin
                    m_value <= CENTRE;
                    wait_cnt <= 2'd0;
                    if (m_new_event) state <= S_WAIT;
                end
                S_WAIT: begin                      // xpos is registered in
                    wait_cnt <= wait_cnt + 2'd1;   // MouseCtl: give it time
                    if (wait_cnt == 2'd3) state <= S_READ;
                end
                S_READ: begin
                    raw_x <= $signed({1'b0, m_xpos}) - $signed({1'b0, CENTRE});
                    raw_y <= $signed({1'b0, m_ypos}) - $signed({1'b0, CENTRE});
                    raw_z <= m_zpos;
                    m_setx <= 1'b1; m_sety <= 1'b1; // back to the centre
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

    // ---------------- cursor in quarter pixels, clamped to the screen -------
    reg [9:0] qx, qy;
    wire signed [12:0] nx = $signed({3'b000, qx}) + $signed(delta_x);
    wire signed [12:0] ny = $signed({3'b000, qy}) + $signed(delta_y);
    always @(posedge clk) begin
        if (rst) begin
            qx <= 10'd320;                         // screen centre
            qy <= 10'd240;
        end else if (delta_valid) begin
            qx <= (nx < 0) ? 10'd0 : (nx > $signed({3'b000, QX_MAX})) ? QX_MAX : nx[9:0];
            qy <= (ny < 0) ? 10'd0 : (ny > $signed({3'b000, QY_MAX})) ? QY_MAX : ny[9:0];
        end
    end
    assign cursor_x = qx[9:2];
    assign cursor_y = qy[8:2];
    wire signed [8:0] uxs = $signed({1'b0, cursor_x}) - $signed({1'b0, `UI_X0});
    wire signed [8:0] uys = $signed({2'b00, cursor_y}) - $signed({2'b00, `UI_Y0});
    assign ucur_x = (uxs < 0) ? 7'd0 : (uxs > 9'sd95) ? 7'd95 : uxs[6:0];
    assign ucur_y = (uys < 0) ? 6'd0 : (uys > 9'sd63) ? 6'd63 : uys[5:0];

    // ---------------- button levels and edges ------------------------------
    // v3: MouseCtl updates the buttons at packet byte 1, but that packet's
    // motion only arrives with new_event after byte 3. The buttons are
    // therefore sampled together with the motion (S_READ) and their edges
    // come out ONE CYCLE AFTER that packet's delta_valid: the motion of the
    // release packet now belongs to the swipe, the motion of the press
    // packet (made before the press) does not.
    reg [2:0] btn_s;                       // {left, right, middle} of this packet
    reg       btn_go;
    always @(posedge clk) begin
        l_press <= 1'b0; l_release <= 1'b0; r_press <= 1'b0; m_press <= 1'b0;
        btn_go  <= delta_valid;
        if (rst) begin
            l_level <= 1'b0; r_level <= 1'b0; m_level <= 1'b0; btn_s <= 3'b000; btn_go <= 1'b0;
        end else begin
            if (state == S_READ) btn_s <= {m_left, m_right, m_middle};
            if (btn_go) begin
                l_level <= btn_s[2]; r_level <= btn_s[1]; m_level <= btn_s[0];
                l_press   <=  btn_s[2] & ~l_level;
                l_release <= ~btn_s[2] &  l_level;
                r_press   <=  btn_s[1] & ~r_level;
                m_press   <=  btn_s[0] & ~m_level;
            end
        end
    end
endmodule
