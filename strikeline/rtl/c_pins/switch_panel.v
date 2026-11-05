`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// switch_panel.v - screen 2 help page: what every switch does, live, and the buttons
//-----------------------------------------------------------------------------
// Owner   : Student C (second OLED)
// Shown on screen 2 in the menus, and in a game when the player presses btnD
// (or right-clicks). Text grid: 3x5 font, 24 columns x 10 rows,
// row r covers y = 2 + 6r .. 7 + 6r.
//
//   row 0   SWITCHES        UP = ON
//   row 1   0 PAUSE         11 12 LB      <- each entry is GREEN when that
//   row 2   1 MINIMAP       12 16 LB         switch is up, GREY when down,
//   row 3   2 DEBUG         13 NEON          so the screen always shows the
//   row 4   3 SLOW-MO       14 LONG OIL      real state of the board
//   row 5   4 TOP VIEW      15 LEFT HAND
//   ------  (line)
//   row 7-9 the buttons: menu version, or in-game version
//
// The left column is the "while playing" group (sw0-sw4, right side of the
// board), the right column the "bowler set-up" group (sw11-sw15, left side).
//=============================================================================
module switch_panel (
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire [15:0] sw_level,         // debounced switches
    input  wire        in_game,          // which button help to show
    output reg  [15:0] color,
    output reg         en,
    output reg  [`TX_W-1:0] txt
);
`include "txt_helpers.vh"
`include "screen2_map.vh"

    localparam [15:0] BG    = 16'h0841;
    localparam [15:0] ON_C  = 16'h07E0;      // green
    localparam [15:0] OFF_C = 16'h630C;      // grey
    localparam [15:0] HEAD  = 16'hFFE0;      // yellow
    localparam [15:0] HELP  = 16'hBDF7;      // light grey-blue

    // ---- text grid position: row = (y - 2) / 6, fy = (y - 2) % 6 ----
    // Dividing by 6 without a divider: n / 6 == (n * 43) >> 8 for n < 128.
    wire [5:0]  yy   = px_y - 6'd2;
    wire [11:0] y43  = yy * 6'd43;
    wire [3:0]  row  = y43[11:8];
    wire [5:0]  fy6  = yy - {row, 2'b00} - {1'b0, row, 1'b0};   // yy - 6*row
    wire [2:0]  fy   = fy6[2:0];
    wire [4:0]  col  = px_x[6:2];            // 4 px per column
    wire [2:0]  fx   = {1'b0, px_x[1:0]};

    // ---- which switch belongs to this row (rows 1..5) ----
    wire [2:0] k       = row[2:0] - 3'd1;            // 0..4
    wire       left_on = sw_level[k];                // sw0 .. sw4
    wire       right_on= sw_level[4'd11 + k];        // sw11 .. sw15

    // LIST items are 12 (switches) or 24 (buttons) characters long:
    //   item * 12 = (item << 3) + (item << 2),  item * 24 = that << 1
    wire [10:0] k12  = {5'd0, k, 3'b000} + {6'd0, k, 2'b00};
    wire [1:0]  b    = row[1:0] - 2'd3;              // rows 7,8,9 -> 0,1,2
    wire [10:0] b24  = {4'd0, b, 5'b00000} - {6'd0, b, 3'b000};   // b*32 - b*8

    always @(*) begin
        en    = 1'b1;               // this page covers the whole screen
        color = BG;
        txt   = {`TX_W{1'b0}};

        if (px_y == 6'd38 && px_x >= 7'd2 && px_x <= 7'd93)
            color = 16'h4208;                                   // separator line
        else if (px_y >= 6'd2 && px_y <= 6'd61) begin
            if (row == 4'd0) begin
                if (col < `L2_SWHDR)
                    txt = tx_s(`S2_SWHDR + col, 1'b1, fx, fy, HEAD, 16'd0, 1'b0);
            end
            else if (row <= 4'd5) begin
                if (col < 5'd12)
                    txt = tx_s(`S2_SWL + k12 + col, 1'b1, fx, fy,
                               left_on ? ON_C : OFF_C, 16'd0, 1'b0);
                else
                    txt = tx_s(`S2_SWR + k12 + col - 5'd12, 1'b1, fx, fy,
                               right_on ? ON_C : OFF_C, 16'd0, 1'b0);
            end
            else if (row >= 4'd7) begin
                if (in_game)
                    txt = tx_s(`S2_BTNG + b24 + col, 1'b1, fx, fy, HELP, 16'd0, 1'b0);
                else
                    txt = tx_s(`S2_BTNM + b24 + col, 1'b1, fx, fy, HELP, 16'd0, 1'b0);
            end
        end
    end
endmodule
