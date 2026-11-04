`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// menu_render.v : the full-screen screens (title, menus, settings, scores,
//                 help, game over, initials)
//-----------------------------------------------------------------------------
// Owner   : Student D
// Purpose : A function of the pixel position and game_fsm's registers. Each
//           screen is a list of text rows on the 5x7 grid (16 x 8 cells of
//           6 x 8 px) with 3x5 hint rows; text goes to the shared text engine
//           as requests, this module only decides WHAT is in each cell and
//           the background (title bar, hover bar, chips).
//           Scores and stats are read straight from the save image (two read
//           ports: low byte / high byte of the value under this pixel) and
//           turned into digits with combinational double dabble (bcd_fns.vh).
//=============================================================================
module menu_render (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire [`GS_W-1:0] game_state,
    input  wire [`SET_W-1:0] settings,
    input  wire [2:0]  hover,
    input  wire        chip_two,
    input  wire        has_save,
    input  wire [2:0]  leave_idx,
    input  wire        tab_quick,
    input  wire [1:0]  erase_step,
    input  wire [14:0] name,
    input  wire [1:0]  name_pos,
    input  wire        name_player,
    input  wire [1:0]  newhi,
    input  wire        two_players,
    input  wire [8:0]  game0, game1,
    input  wire        flash_ok,
    output reg  [6:0]  ra_lo,
    output reg  [6:0]  ra_hi,
    input  wire [7:0]  rd_lo,
    input  wire [7:0]  rd_hi,
    output reg  [15:0] color,
    output reg         en,
    output reg  [`TX_W-1:0] txt
);
`include "txt_helpers.vh"
`include "strings_map.vh"
`include "bcd_fns.vh"

    // ---------------- animation clock ---------------------------------------
    reg [7:0] fr;
    always @(posedge clk) if (rst) fr <= 0; else if (tick_frame) fr <= fr + 8'd1;
    wire blink = fr[5];

    // ---------------- grids ---------------------------------------------------
    wire [3:0] col = c6(px_x);
    wire [2:0] fx  = f6(px_x);
    wire [2:0] row = px_y[5:3];
    wire [2:0] fy  = px_y[2:0];
    wire [4:0] mcol = px_x[6:2];
    wire [2:0] mfx  = {1'b0, px_x[1:0]};
    wire [12:0] my43 = px_y * 6'd43;
    wire [3:0] mrow = my43[11:8];
    wire [5:0] mfy6 = px_y - {mrow, 2'b00} - {1'b0, mrow, 1'b0};
    wire [2:0] mfy  = mfy6[2:0];

    // big (2x) text helper: character index and pixel inside a 12 x 16 cell
    function [6:0] big;                    // {index[3:0], fx2[2:0]} from x - x0
        input [6:0] dx;
        reg [3:0] c; reg [2:0] f;
        reg [3:0] f12;                     // pixel inside the 12-px cell: 4 bits (0..11)
        begin
            c = c6(dx); f = f6(dx);
            f12 = c[0] ? {1'b0, f} + 4'd6 : {1'b0, f};
            big = {1'b0, c[3:1], f12[3:1]};
        end
    endfunction

    wire neon = settings[`SET_THEME];
    wire [15:0] c_bg    = neon ? 16'h0806 : 16'h0109;
    wire [15:0] c_title = neon ? 16'h780F : 16'h8A22;
    wire [15:0] c_hov   = neon ? 16'h300C : 16'h2967;
    wire [15:0] c_dim   = 16'h6B4D;
    localparam [15:0] W = `C_WHITE, Y = `C_YELLOW, C = `C_CYAN;

    // ---------------- numbers under this pixel ------------------------------
    wire [8:0]  v9   = {rd_hi[0], rd_lo};
    wire [11:0] b9   = bcd9(v9);
    wire [19:0] b16  = bcd16({rd_hi, rd_lo});
    wire [11:0] g0b  = bcd9(game0), g1b = bcd9(game1);
    wire [6:0]  tbl  = tab_quick ? `IM_TOPQ : `IM_TOPF;
    wire [2:0]  ent  = row - 3'd1;                                   // scores rows 1..5
    wire [6:0]  ebase = tbl + {ent, 2'b00} + {4'd0, ent};
    function [5:0] dg3;                     // digit k of a 3-digit BCD, blank leading zeros
        input [11:0] b; input [1:0] k;
        case (k)
            2'd0: dg3 = (b[11:8] == 0) ? 6'd0 : 6'd16 + b[11:8];
            2'd1: dg3 = (b[11:4] == 0) ? 6'd0 : 6'd16 + b[7:4];
            default: dg3 = 6'd16 + b[3:0];
        endcase
    endfunction
    function [5:0] dg5;                     // digit k (0 = left) of a 5-digit BCD, no leading zeros
        input [19:0] b; input [2:0] k;
        reg [19:0] lead;
        begin
            lead = b >> (4 * (3'd4 - k));
            dg5 = (k != 3'd4 && (lead >> 4) == 0 && lead[3:0] == 0) ? 6'd0 : 6'd16 + lead[3:0];
        end
    endfunction

    // ---------------- the screens --------------------------------------------
    always @(*) begin
        en = 1'b1; color = c_bg; txt = {`TX_W{1'b0}};
        ra_lo = `IM_BEST; ra_hi = `IM_BEST + 7'd1;
        case (game_state)
        // ===================================================== TITLE
        `GS_TITLE: begin
            color = (px_y < 6'd8 || px_y >= 6'd56) ? c_bg : (neon ? 16'h1008 : 16'h0109);
            if (px_y >= 6'd8 && px_y < 6'd24 && px_x >= 7'd12 && px_x < 7'd84)
                txt = tx_s(`S_TITLE1 + (big(px_x - 7'd12) >> 3), 1'b0, big(px_x - 7'd12) & 3'd7,
                           (px_y - 6'd8) >> 1, neon ? `C_MAGENTA : Y, 0, 1'b0);
            else if (px_y >= 6'd24 && px_y < 6'd40 && px_x >= 7'd24 && px_x < 7'd72)
                txt = tx_s(`S_TITLE2 + (big(px_x - 7'd24) >> 3), 1'b0, big(px_x - 7'd24) & 3'd7,
                           (px_y - 6'd24) >> 1, neon ? C : W, 0, 1'b0);
            else if (px_y >= 6'd43 && px_y <= 6'd52) begin
                // a tiny lane with a ball rolling into 4 pins, forever
                color = neon ? 16'h18C8 : 16'hCD0D;
                if ((px_y == 6'd47 || px_y == 6'd48) && px_x >= {1'b0, fr[6:1]} + 7'd8 &&
                    px_x <= {1'b0, fr[6:1]} + 7'd11)
                    color = 16'hA8E7;                                             // ball
                else if (fr[6:1] < 6'd44 && (px_x == 7'd80 || px_x == 7'd84 || px_x == 7'd88) &&
                         (px_y == 6'd45 || px_y == 6'd50 || px_y == 6'd47))
                    color = W;                                                    // pins
            end else if (row == 3'd7 && col >= 4'd1 && col < 4'd14 && blink)
                txt = tx_s(`S_CLICK + col - 4'd1, 1'b0, fx, fy, W, 0, 1'b0);
        end
        // ===================================================== MAIN MENU
        `GS_MENU: begin
            if (row == 3'd0) begin
                color = c_title;
                if (mrow == 4'd0 && mcol < 5'd24)
                    txt = tx_s((hover == 3'd1 && !has_save) ? `S_MHINT + 11'd168 + mcol :
                               `S_MHINT + {hover - 3'd1, 4'd0} + {hover - 3'd1, 3'd0} + mcol,
                               1'b1, mfx, mfy, W, 0, 1'b0);
            end else begin
                if (row == hover) color = c_hov;
                if (col >= 4'd1 && col < 4'd12)
                    txt = tx_s(`S_MENU + ({row - 3'd1, 3'd0} + {row - 3'd1, 1'b0} + (row - 3'd1)) + col - 4'd1,
                               1'b0, fx, fy, (row == 3'd1 && !has_save) ? c_dim : (row == hover ? Y : W), 0, 1'b0);
                else if ((row == 3'd2 || row == 3'd3) && col >= 4'd13 && col <= 4'd14) begin
                    color = chip_two ? `C_MAGENTA : 16'h0410;
                    txt = tx_s(`S_CHIP + (chip_two ? 11'd2 : 11'd0) + col - 4'd13, 1'b0, fx, fy, W, 0, 1'b0);
                end
            end
        end
        // ===================================================== PRACTICE
        `GS_PRACTICE_SPARE: begin
            if (row == 3'd0) begin
                color = c_title;
                if (col >= 4'd4 && col < 4'd12) txt = tx_s(`S_PRACT + col - 4'd4, 1'b0, fx, fy, W, 0, 1'b0);
            end else if (mrow == 4'd9) begin            // hint (y 54..59 spans rows 6 and 7)
                if (mcol < 5'd24) txt = tx_s(`S_PRACH + mcol, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
            end else begin
                if (row == hover && (row == 3'd2 || row == 3'd3 || row == 3'd4 || row == 3'd6)) color = c_hov;
                case (row)
                    3'd2: if (col >= 4'd1) txt = tx_s(`S_PRAC + col - 4'd1, 1'b0, fx, fy, row == hover ? Y : W, 0, 1'b0);
                    3'd3: if (col >= 4'd1) txt = tx_s(`S_PRAC + 11'd15 + col - 4'd1, 1'b0, fx, fy, row == hover ? Y : W, 0, 1'b0);
                    3'd4: if (col >= 4'd3 && col <= 4'd11) begin
                              color = (row == hover) ? `C_MAGENTA : 16'h0410;
                              if (col == 4'd3)       txt = tx_l(6'd59, 1'b0, fx, fy, W, 0, 1'b0);   // [
                              else if (col == 4'd11) txt = tx_l(6'd61, 1'b0, fx, fy, W, 0, 1'b0);   // ]
                              else txt = tx_s(`S_LEAVE + {leave_idx, 3'd0} - leave_idx + col - 4'd4, 1'b0, fx, fy, W, 0, 1'b0);
                          end
                    3'd6: if (col >= 4'd1) txt = tx_s(`S_PRAC + 11'd30 + col - 4'd1, 1'b0, fx, fy, row == hover ? Y : W, 0, 1'b0);
                    default: ;
                endcase
            end
        end
        // ===================================================== SETTINGS
        `GS_SETTINGS: begin
            if (row == 3'd0) begin
                color = c_title;
                if (col < 4'd8) txt = tx_s(`S_SETT + col, 1'b0, fx, fy, W, 0, 1'b0);
                else if (mcol >= 5'd14 && mrow == 4'd0) txt = tx_s(`S_BACKH + mcol - 5'd14, 1'b1, mfx, mfy, W, 0, 1'b0);
            end else begin
                if (row == hover) color = c_hov;
                if (col >= 4'd1 && col < 4'd7)
                    txt = tx_s(`S_SETN + {row - 3'd1, 2'b00} + {row - 3'd1, 1'b0} + col - 4'd1, 1'b0, fx, fy,
                               row == hover ? Y : W, 0, 1'b0);
                else if (col >= 4'd9 && col < 4'd14) begin
                    case (row)
                        3'd1: txt = tx_s(`S_SETV + (settings[`SET_OIL] ? 11'd5 : 11'd0) + col - 4'd9, 1'b0, fx, fy, C, 0, 1'b0);
                        3'd2: txt = tx_s(`S_SETV + 11'd10 + {settings[`SET_LB_HI:`SET_LB_LO], 2'b00} +
                                         settings[`SET_LB_HI:`SET_LB_LO] + col - 4'd9, 1'b0, fx, fy, C, 0, 1'b0);
                        3'd3: txt = tx_s(`S_SETV + (settings[`SET_LEFTY] ? 11'd30 : 11'd25) + col - 4'd9, 1'b0, fx, fy, C, 0, 1'b0);
                        3'd4: if (col == 4'd9) txt = tx_l(6'd17 + settings[`SET_SENS_HI:`SET_SENS_LO], 1'b0, fx, fy, C, 0, 1'b0);
                        3'd5: txt = tx_s(`S_SETV + (settings[`SET_THEME] ? 11'd40 : 11'd35) + col - 4'd9, 1'b0, fx, fy, C, 0, 1'b0);
                        3'd6: if (col == 4'd9) txt = tx_l(6'd17 + settings[`SET_BRI_HI:`SET_BRI_LO], 1'b0, fx, fy, C, 0, 1'b0);
                        default: txt = tx_s(`S_SETV + 11'd45 + {erase_step, 2'b00} + erase_step + col - 4'd9,
                                            1'b0, fx, fy, (erase_step == 2'd1) ? `C_RED : C, 0, 1'b0);
                    endcase
                end
            end
        end
        // ===================================================== HIGH SCORES
        `GS_SCORES: begin
            ra_lo = ebase; ra_hi = ebase + 7'd1;
            if (row == 3'd0) begin
                color = c_title;
                if (col < 4'd5) txt = tx_s(`S_TOP5 + col, 1'b0, fx, fy, W, 0, 1'b0);
                else if (col >= 4'd10 && col < 4'd15) begin
                    color = `C_MAGENTA;
                    txt = tx_s(`S_TABS + (tab_quick ? 11'd5 : 11'd0) + col - 4'd10, 1'b0, fx, fy, W, 0, 1'b0);
                end
            end else if (row <= 3'd5) begin
                if (col >= 4'd3 && col <= 4'd5) ra_lo = ebase + 7'd2 + (col - 4'd3);
                case (col)
                    4'd1: txt = tx_l(6'd16 + row, 1'b0, fx, fy, Y, 0, 1'b0);
                    4'd3, 4'd4, 4'd5: txt = tx_l(rd_hi[7] ? 6'd33 + rd_lo[5:0] : 6'd13, 1'b0, fx, fy, W, 0, 1'b0);
                    4'd9, 4'd10, 4'd11: txt = tx_l(rd_hi[7] ? dg3(b9, col - 4'd9) : 6'd13, 1'b0, fx, fy, C, 0, 1'b0);
                    default: ;
                endcase
            end else if (mrow == 4'd8 || mrow == 4'd9) begin
                // X strikes / spares,  GAMES n  BEST n
                if (mrow == 4'd8) begin
                    if (mcol < 5'd8) begin ra_lo = `IM_STRK; ra_hi = `IM_STRK + 7'd1; end
                    else             begin ra_lo = `IM_SPAR; ra_hi = `IM_SPAR + 7'd1; end
                    case (mcol)
                        5'd0: txt = tx_l(6'd56, 1'b1, mfx, mfy, Y, 0, 1'b0);
                        5'd2, 5'd3, 5'd4, 5'd5, 5'd6: txt = tx_l(dg5(b16, mcol - 5'd2), 1'b1, mfx, mfy, W, 0, 1'b0);
                        5'd9: txt = tx_l(6'd15, 1'b1, mfx, mfy, Y, 0, 1'b0);
                        5'd11, 5'd12, 5'd13, 5'd14, 5'd15: txt = tx_l(dg5(b16, mcol - 5'd11), 1'b1, mfx, mfy, W, 0, 1'b0);
                        default: ;
                    endcase
                end else begin
                    if (mcol < 5'd12) begin ra_lo = `IM_GAMES; ra_hi = `IM_GAMES + 7'd1; end
                    if (mcol < 5'd5)       txt = tx_s(`S_GAMES + mcol, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
                    else if (mcol >= 5'd6 && mcol < 5'd11) txt = tx_l(dg5(b16, mcol - 5'd6), 1'b1, mfx, mfy, W, 0, 1'b0);
                    else if (mcol >= 5'd13 && mcol < 5'd17) txt = tx_s(`S_BEST + mcol - 5'd13, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
                    else if (mcol >= 5'd18 && mcol < 5'd21) txt = tx_l(dg3(b9, mcol - 5'd18), 1'b1, mfx, mfy, W, 0, 1'b0);
                end
            end
        end
        // ===================================================== HELP
        `GS_HELP: begin
            if (row == 3'd0) begin
                color = c_title;
                if (col >= 4'd2 && col < 4'd13) txt = tx_s(`S_HELPT + col - 4'd2, 1'b0, fx, fy, W, 0, 1'b0);
            end else if (mrow >= 4'd2 && mrow <= 4'd9)     // (row 10 is cut off at y 63)
                txt = tx_s(`S_HELP + {mrow - 4'd2, 4'd0} + {mrow - 4'd2, 3'd0} + mcol, 1'b1, mfx, mfy,
                           mrow[0] ? W : 16'hBDF7, 0, 1'b0);
        end
        // ===================================================== GAME OVER
        `GS_GAMEOVER: begin
            if (row == 3'd0) begin
                color = c_title;
                if (col >= 4'd3 && col < 4'd12) txt = tx_s(`S_GOVER + col - 4'd3, 1'b0, fx, fy, W, 0, 1'b0);
            end else if (!two_players && px_y >= 6'd16 && px_y < 6'd32 && px_x >= 7'd30 && px_x < 7'd66)
                txt = tx_l(dg3(g0b, (big(px_x - 7'd30) >> 3)), 1'b0, big(px_x - 7'd30) & 3'd7, (px_y - 6'd16) >> 1, Y, 0, 1'b0);
            else if (two_players && (row == 3'd2 || row == 3'd3)) begin
                case (col)
                    4'd3: txt = tx_l(6'd48, 1'b0, fx, fy, W, 0, 1'b0);                      // P
                    4'd4: txt = tx_l(row == 3'd2 ? 6'd17 : 6'd18, 1'b0, fx, fy, W, 0, 1'b0);
                    4'd7, 4'd8, 4'd9: txt = tx_l(dg3(row == 3'd2 ? g0b : g1b, col - 4'd7), 1'b0, fx, fy, Y, 0, 1'b0);
                    default: ;
                endcase
            end else if (two_players && row == 3'd5 && col >= 4'd3) begin
                if (game0 == game1) begin
                    if (col < 4'd11) txt = tx_s(`S_TIE + col - 4'd3, 1'b0, fx, fy, C, 0, 1'b0);
                end else if (col == 4'd3) txt = tx_l(6'd48, 1'b0, fx, fy, C, 0, 1'b0);
                else if (col == 4'd4) txt = tx_l(game0 > game1 ? 6'd17 : 6'd18, 1'b0, fx, fy, C, 0, 1'b0);
                else if (col >= 4'd6 && col < 4'd11) txt = tx_s(`S_WINS + col - 4'd6, 1'b0, fx, fy, C, 0, 1'b0);
            end else if (row == 3'd6 && newhi != 0 && blink && col < 4'd15)
                txt = tx_s(`S_NEWHI + col, 1'b0, fx, fy, `C_MAGENTA, 0, 1'b0);
            else if (mrow == 4'd9 && mcol >= 5'd3 && mcol < 5'd20)
                txt = tx_s(`S_CONT + mcol - 5'd3, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
        end
        // ===================================================== INITIALS
        `GS_NAME: begin
            if (row == 3'd0) begin
                color = c_title;
                if (col < 4'd15) txt = tx_s(`S_NEWHI + col, 1'b0, fx, fy, W, 0, 1'b0);
            end else if (row == 3'd1) begin
                if (col == 4'd0) txt = tx_l(6'd48, 1'b0, fx, fy, Y, 0, 1'b0);
                else if (col == 4'd1) txt = tx_l(name_player ? 6'd18 : 6'd17, 1'b0, fx, fy, Y, 0, 1'b0);
                else if (col >= 4'd2) txt = tx_s(`S_ENTER + col - 4'd2, 1'b0, fx, fy, W, 0, 1'b0);
            end else if (px_y >= 6'd24 && px_y < 6'd40 && px_x >= 7'd30 && px_x < 7'd66) begin
                txt = tx_l(6'd33 + ((big(px_x - 7'd30) >> 3) == 0 ? name[14:10] :
                                    (big(px_x - 7'd30) >> 3) == 1 ? name[9:5] : name[4:0]),
                           1'b0, big(px_x - 7'd30) & 3'd7, (px_y - 6'd24) >> 1,
                           ((big(px_x - 7'd30) >> 3) == name_pos && blink) ? Y : W, 0, 1'b0);
            end else if (px_y == 6'd41 && px_x >= 7'd30 + {name_pos, 3'b000} + {1'b0, name_pos, 2'b00} &&
                         px_x <  7'd40 + {name_pos, 3'b000} + {1'b0, name_pos, 2'b00})
                color = Y;                                                              // underline
            else if (row == 3'd6) begin
                if (col >= 4'd6 && col <= 4'd8)
                    txt = tx_l(dg3(name_player ? g1b : g0b, col - 4'd6), 1'b0, fx, fy, C, 0, 1'b0);
            end else if (mrow == 4'd9 && mcol >= 5'd1 && mcol < 5'd22)
                txt = tx_s(`S_NAMEH + mcol - 5'd1, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
        end
        default: en = 1'b0;                                // in a game: other layers draw
        endcase
    end
endmodule
