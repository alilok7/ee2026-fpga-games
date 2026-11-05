`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// deck_panel.v - screen 2 game panel: live pin diagram, pin counts, Spare Challenge
//-----------------------------------------------------------------------------
// Owner   : Student C (second OLED)
// Draws, for the pixel (px_x, px_y) of screen 2:
//
//   y 36..63, whole width: THE PIN DECK
//     left : the 10 pins as 4x4 squares, seen from the bowler
//              7  8  9  10         white = standing
//               4  5  6            red   = knocked down by THIS ball
//                2  3              grey  = already down before this ball
//                 1
//     right: "DOWN n"     pins knocked down by this ball (counts up live
//                          while the pins are still falling)
//            "STANDING n" pins still up
//            "SPLIT!"     (flashing) after a ball that leaves a split
//
//   y 0..35, only in Spare Challenge (there is no scorecard to show):
//            SPARE CHALLENGE / the leave's name / MADE nn OF nn
//
// Everything is combinational: a few comparisons per pixel. Text goes out as
// a text request (strike_defs.vh, TX_*); screen2.v turns it into pixels.
// All text is the 3x5 font: cells 4 px wide, 6 px tall.
//=============================================================================
module deck_panel (
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire [9:0]  standing,         // live, from pin_physics (bit k = pin k+1)
    input  wire [9:0]  standing_before,  // pins up when this ball was thrown
    input  wire        split_flag,       // from pin_settle, valid after settling
    input  wire        show_split,       // the result is on screen
    input  wire        blink,            // ~4 Hz, for "SPLIT!"
    input  wire        spare,            // Spare Challenge (no scorecard)
    input  wire [2:0]  leave_idx,
    input  wire [7:0]  spare_made,
    input  wire [7:0]  spare_tries,
    output reg  [15:0] color,
    output reg         en,
    output reg  [`TX_W-1:0] txt
);
`include "txt_helpers.vh"
`include "bcd_fns.vh"
`include "screen2_map.vh"

    localparam [15:0] BG     = 16'h0841;     // panel background (almost black)
    localparam [15:0] LINE   = 16'h4208;     // separator line
    localparam [15:0] PIN_UP = 16'hFFFF;
    localparam [15:0] PIN_HIT= 16'hF800;
    localparam [15:0] PIN_OLD= 16'h31A6;
    localparam [15:0] LABEL  = 16'hAD55;
    localparam [15:0] YEL    = 16'hFFE0;

    // ---------------- counts --------------------------------------------
    // knocked = up before the ball AND down now
    wire [9:0] knocked = standing_before & ~standing;
    integer i;
    reg [3:0] n_down, n_up;
    always @(*) begin
        n_down = 4'd0;
        n_up   = 4'd0;
        for (i = 0; i < 10; i = i + 1) begin
            n_down = n_down + knocked[i];
            n_up   = n_up   + standing[i];
        end
    end

    // ---------------- which pin square is this pixel in? ----------------
    // Each row of the diagram is 4 px tall; the squares are 4 px wide and
    // 8 px apart. pin_hit = 1 inside a square, pin_no = 0..9 (pin 1..10).
    reg       pin_hit;
    reg [3:0] pin_no;
    always @(*) begin
        pin_hit = 1'b0;
        pin_no  = 4'd0;
        if (px_y >= 6'd39 && px_y <= 6'd42) begin            // 7 8 9 10
            if      (px_x >= 7'd4  && px_x <= 7'd7)  begin pin_hit = 1'b1; pin_no = 4'd6; end
            else if (px_x >= 7'd12 && px_x <= 7'd15) begin pin_hit = 1'b1; pin_no = 4'd7; end
            else if (px_x >= 7'd20 && px_x <= 7'd23) begin pin_hit = 1'b1; pin_no = 4'd8; end
            else if (px_x >= 7'd28 && px_x <= 7'd31) begin pin_hit = 1'b1; pin_no = 4'd9; end
        end else if (px_y >= 6'd45 && px_y <= 6'd48) begin   // 4 5 6
            if      (px_x >= 7'd8  && px_x <= 7'd11) begin pin_hit = 1'b1; pin_no = 4'd3; end
            else if (px_x >= 7'd16 && px_x <= 7'd19) begin pin_hit = 1'b1; pin_no = 4'd4; end
            else if (px_x >= 7'd24 && px_x <= 7'd27) begin pin_hit = 1'b1; pin_no = 4'd5; end
        end else if (px_y >= 6'd51 && px_y <= 6'd54) begin   // 2 3
            if      (px_x >= 7'd12 && px_x <= 7'd15) begin pin_hit = 1'b1; pin_no = 4'd1; end
            else if (px_x >= 7'd20 && px_x <= 7'd23) begin pin_hit = 1'b1; pin_no = 4'd2; end
        end else if (px_y >= 6'd57 && px_y <= 6'd60) begin   // 1 (head pin)
            if (px_x >= 7'd16 && px_x <= 7'd19)      begin pin_hit = 1'b1; pin_no = 4'd0; end
        end
    end

    // ---------------- 3x5 text grid helpers ------------------------------
    // A text line starts at (x0, y0); column = (x - x0) / 4, fx = (x - x0) % 4
    wire [6:0] tx40 = px_x - 7'd40;         // text column area starts at x = 40
    wire [4:0] col  = tx40[6:2];
    wire [2:0] fx   = {1'b0, tx40[1:0]};

    // digits of the counts (0..10) and of the Spare Challenge numbers
    wire [11:0] down_b  = bcd9({5'd0, n_down});
    wire [11:0] up_b    = bcd9({5'd0, n_up});
    wire [11:0] made_b  = bcd9({1'b0, spare_made});
    wire [11:0] tries_b = bcd9({1'b0, spare_tries});

    // leave name: LIST LEAVE is 7 characters per item -> address = idx*7 + k
    wire [10:0] leave_base = `S2_LEAVE + {5'd0, leave_idx, 3'd0} - {8'd0, leave_idx};

    // Spare Challenge header lines (y 0..35): column from x = 16
    wire [6:0] sx  = px_x - 7'd16;
    wire [4:0] scol = sx[6:2];
    wire [2:0] sfx  = {1'b0, sx[1:0]};

    always @(*) begin
        en    = 1'b0;
        color = BG;
        txt   = {`TX_W{1'b0}};

        // ===================== pin deck (y 36..63) =====================
        if (px_y >= 6'd36) begin
            en = 1'b1;
            if (px_y == 6'd36)
                color = LINE;
            else if (pin_hit) begin
                if (standing[pin_no])             color = PIN_UP;
                else if (standing_before[pin_no]) color = PIN_HIT;
                else                              color = PIN_OLD;
            end

            // "DOWN nn"  (y 39..44)
            if (px_y >= 6'd39 && px_y <= 6'd44 && px_x >= 7'd40) begin
                case (col)
                    5'd0, 5'd1, 5'd2, 5'd3:
                        txt = tx_s(`S2_DOWNW + col, 1'b1, fx, px_y - 6'd39, LABEL, 16'd0, 1'b0);
                    5'd5: if (down_b[7:4] != 4'd0)
                        txt = tx_l(dig(down_b[7:4]), 1'b1, fx, px_y - 6'd39, YEL, 16'd0, 1'b0);
                    5'd6:
                        txt = tx_l(dig(down_b[3:0]), 1'b1, fx, px_y - 6'd39, YEL, 16'd0, 1'b0);
                    default: ;
                endcase
            end
            // "STANDING nn"  (y 47..52)
            else if (px_y >= 6'd47 && px_y <= 6'd52 && px_x >= 7'd40) begin
                if (col <= 5'd7)
                    txt = tx_s(`S2_STANDW + col, 1'b1, fx, px_y - 6'd47, LABEL, 16'd0, 1'b0);
                else if (col == 5'd9 && up_b[7:4] != 4'd0)
                    txt = tx_l(dig(up_b[7:4]), 1'b1, fx, px_y - 6'd47, PIN_UP, 16'd0, 1'b0);
                else if (col == 5'd10)
                    txt = tx_l(dig(up_b[3:0]), 1'b1, fx, px_y - 6'd47, PIN_UP, 16'd0, 1'b0);
            end
            // "SPLIT!"  (y 55..60), flashing
            else if (px_y >= 6'd55 && px_y <= 6'd60 && px_x >= 7'd40) begin
                if (split_flag && show_split && blink && col <= 5'd5)
                    txt = tx_s(`S2_SPLITW + col, 1'b1, fx, px_y - 6'd55, `C_ORANGE, 16'd0, 1'b0);
            end
        end

        // ============ Spare Challenge header (y 0..35) ============
        else if (spare) begin
            en = 1'b1;
            color = 16'h0109;                              // dark blue
            if (px_x >= 7'd16) begin
                // "SPARE CHALLENGE"  (y 4..9)
                if (px_y >= 6'd4 && px_y <= 6'd9 && scol <= 5'd14)
                    txt = tx_s(`S2_SPCH + scol, 1'b1, sfx, px_y - 6'd4, YEL, 16'd0, 1'b0);
                // leave name, e.g. "7-10"  (y 15..20), from column 4
                else if (px_y >= 6'd15 && px_y <= 6'd20 && scol >= 5'd4 && scol <= 5'd10)
                    txt = tx_s(leave_base + scol - 5'd4, 1'b1, sfx, px_y - 6'd15, PIN_UP, 16'd0, 1'b0);
                // "MADE nn OF nn"  (y 26..31)
                else if (px_y >= 6'd26 && px_y <= 6'd31) begin
                    case (scol)
                        5'd0, 5'd1, 5'd2, 5'd3:
                            txt = tx_s(`S2_MADEW + scol, 1'b1, sfx, px_y - 6'd26, LABEL, 16'd0, 1'b0);
                        5'd5:  txt = tx_l(dig(made_b[7:4]),  1'b1, sfx, px_y - 6'd26, `C_GREEN, 16'd0, 1'b0);
                        5'd6:  txt = tx_l(dig(made_b[3:0]),  1'b1, sfx, px_y - 6'd26, `C_GREEN, 16'd0, 1'b0);
                        5'd8, 5'd9:
                            txt = tx_s(`S2_OFW + scol - 5'd8, 1'b1, sfx, px_y - 6'd26, LABEL, 16'd0, 1'b0);
                        5'd11: txt = tx_l(dig(tries_b[7:4]), 1'b1, sfx, px_y - 6'd26, PIN_UP, 16'd0, 1'b0);
                        5'd12: txt = tx_l(dig(tries_b[3:0]), 1'b1, sfx, px_y - 6'd26, PIN_UP, 16'd0, 1'b0);
                        default: ;
                    endcase
                end
            end
        end
    end
endmodule
