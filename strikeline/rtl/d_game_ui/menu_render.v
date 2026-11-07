`timescale 1ns / 1ps
`include "strike_defs.vh"
// menu_render.v : the full-screen screens on the 96 x 64 UI picture
// Student D. One block per screen, then a mux on game_state. Text goes to the
// shared text engine as requests; scores and stats come from the save image.
module menu_render (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_frame,
    input  wire [6:0]  px_x,
    input  wire [5:0]  px_y,
    input  wire [`GS_W-1:0] game_state,
    input  wire [`SET_W-1:0] settings,
    input  wire [2:0]  hover,            // ---- game_fsm registers ----
    input  wire        chip_two,
    input  wire        has_save,
    input  wire [2:0]  leave_idx,        // (not used)
    input  wire        tab_quick,
    input  wire [1:0]  erase_step,
    input  wire [14:0] name,
    input  wire [1:0]  name_pos,
    input  wire        name_player,
    input  wire [1:0]  newhi,
    input  wire        two_players,      // C: t_kind[PK_TWO]
    input  wire [8:0]  game0, game1,     // C: final scores
    input  wire        flash_ok,         // (not used)
    output reg  [6:0]  ra_lo,            // save image read ports 4 and 5
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

    // frame counter: blinking + animation
    reg [7:0] fr;
    always @(posedge clk) begin
        if (rst)             fr <= 0;
        else if (tick_frame) fr <= fr + 8'd1;
    end
    wire blink = fr[5];                                   // ~1 Hz

    // the text grids
    wire [3:0]  col  = c6(px_x);                          // 5x7 column  (x / 6)
    wire [2:0]  fx   = f6(px_x);
    wire [2:0]  row  = px_y[5:3];                         // 5x7 row     (y / 8)
    wire [2:0]  fy   = px_y[2:0];
    wire [4:0]  mcol = px_x[6:2];                         // 3x5 column  (x / 4)
    wire [2:0]  mfx  = {1'b0, px_x[1:0]};
    wire [12:0] my43 = px_y * 6'd43;
    wire [3:0]  mrow = my43[11:8];                        // 3x5 row     (y / 6)
    wire [5:0]  mfy6 = px_y - {mrow, 2'b00} - {1'b0, mrow, 1'b0};
    wire [2:0]  mfy  = mfy6[2:0];

    // double-size text (12 x 16 cells): {character index, pixel column} from x - x0
    function [6:0] big;
        input [6:0] dx;
        reg [3:0] c; reg [2:0] f; reg [3:0] f12;
        begin
            c = c6(dx); f = f6(dx);
            f12 = c[0] ? {1'b0, f} + 4'd6 : {1'b0, f};    // pixel inside the 12-px cell
            big = {1'b0, c[3:1], f12[3:1]};
        end
    endfunction

    // colours
    wire neon = settings[`SET_THEME];
    wire [15:0] c_bg    = neon ? 16'h0806 : 16'h0109;     // background
    wire [15:0] c_title = neon ? 16'h780F : 16'h8A22;     // title bar
    wire [15:0] c_hov   = neon ? 16'h300C : 16'h2967;     // hover bar
    wire [15:0] c_dim   = 16'h6B4D;                       // greyed-out text
    localparam [15:0] W = `C_WHITE, Y = `C_YELLOW, C = `C_CYAN;

    // numbers -> digits
    wire [8:0]  v9   = {rd_hi[0], rd_lo};                 // a score from the image
    wire [11:0] b9   = bcd9(v9);
    wire [19:0] b16  = bcd16({rd_hi, rd_lo});             // a 16-bit stat from the image
    wire [11:0] g0b  = bcd9(game0), g1b = bcd9(game1);
    wire [6:0]  tbl  = tab_quick ? `IM_TOPQ : `IM_TOPF;
    wire [2:0]  ent  = row - 3'd1;
    wire [6:0]  ebase = tbl + {ent, 2'b00} + {4'd0, ent};
    // digit k (0 = hundreds) of a 3-digit BCD number, leading zeros blank
    function [5:0] dg3;
        input [11:0] b; input [1:0] k;
        case (k)
            2'd0: dg3 = (b[11:8] == 0) ? 6'd0 : 6'd16 + b[11:8];
            2'd1: dg3 = (b[11:4] == 0) ? 6'd0 : 6'd16 + b[7:4];
            default: dg3 = 6'd16 + b[3:0];
        endcase
    endfunction
    // digit k (0 = left) of a 5-digit BCD number, leading zeros blank
    function [5:0] dg5;
        input [19:0] b; input [2:0] k;
        reg [19:0] lead;
        begin
            lead = b >> (4 * (3'd4 - k));
            dg5 = (k != 3'd4 && (lead >> 4) == 0 && lead[3:0] == 0) ? 6'd0 : 6'd16 + lead[3:0];
        end
    endfunction

    // TITLE: "STRIKE" / "LINE" in double size, a little lane, "CLICK TO PLAY"
    reg [15:0] t_col; reg [`TX_W-1:0] t_txt;
    always @(*) begin
        t_txt = {`TX_W{1'b0}};
        t_col = (px_y < 6'd8 || px_y >= 6'd56) ? c_bg : (neon ? 16'h1008 : 16'h0109);
        if (px_y >= 6'd8 && px_y < 6'd24 && px_x >= 7'd12 && px_x < 7'd84)
            t_txt = tx_s(`S_TITLE1 + (big(px_x - 7'd12) >> 3), 1'b0, big(px_x - 7'd12) & 3'd7,
                         (px_y - 6'd8) >> 1, neon ? `C_MAGENTA : Y, 0, 1'b0);
        else if (px_y >= 6'd24 && px_y < 6'd40 && px_x >= 7'd24 && px_x < 7'd72)
            t_txt = tx_s(`S_TITLE2 + (big(px_x - 7'd24) >> 3), 1'b0, big(px_x - 7'd24) & 3'd7,
                         (px_y - 6'd24) >> 1, neon ? C : W, 0, 1'b0);
        else if (px_y >= 6'd43 && px_y <= 6'd52) begin
            // a tiny lane with a ball rolling into 4 pins, forever
            t_col = neon ? 16'h18C8 : 16'hCD0D;
            if ((px_y == 6'd47 || px_y == 6'd48) && px_x >= {1'b0, fr[6:1]} + 7'd8 &&
                px_x <= {1'b0, fr[6:1]} + 7'd11)
                t_col = 16'hA8E7;                                                   // ball
            else if (fr[6:1] < 6'd44 && (px_x == 7'd80 || px_x == 7'd84 || px_x == 7'd88) &&
                     (px_y == 6'd45 || px_y == 6'd50 || px_y == 6'd47))
                t_col = W;                                                          // pins
        end else if (row == 3'd7 && col >= 4'd1 && col < 4'd14 && blink)
            t_txt = tx_s(`S_CLICK + col - 4'd1, 1'b0, fx, fy, W, 0, 1'b0);
    end

    // MAIN MENU: hint row, 6 items with hover bar, 1P/2P chips on rows 2-3
    reg [15:0] m_col; reg [`TX_W-1:0] m_txt;
    always @(*) begin
        m_col = c_bg; m_txt = {`TX_W{1'b0}};
        if (row == 3'd0) begin                                   // hint for the highlighted item
            m_col = c_title;
            if (mrow == 4'd0 && mcol < 5'd24)
                m_txt = tx_s((hover == 3'd1 && !has_save) ? `S_MHINT + 11'd144 + mcol :     // "NO SAVED GAME YET"
                             `S_MHINT + {hover - 3'd1, 4'd0} + {hover - 3'd1, 3'd0} + mcol,  // hint (hover-1) x 24
                             1'b1, mfx, mfy, W, 0, 1'b0);
        end else if (row != 3'd7) begin                          // items 1..6
            if (row == hover) m_col = c_hov;
            if (col >= 4'd1 && col < 4'd12)                      // item name, 11 characters
                m_txt = tx_s(`S_MENU + ({row - 3'd1, 3'd0} + {row - 3'd1, 1'b0} + (row - 3'd1)) + col - 4'd1,
                             1'b0, fx, fy, (row == 3'd1 && !has_save) ? c_dim : (row == hover ? Y : W), 0, 1'b0);
            else if ((row == 3'd2 || row == 3'd3) && col >= 4'd13 && col <= 4'd14) begin   // chip "1P" / "2P"
                m_col = chip_two ? `C_MAGENTA : 16'h0410;
                m_txt = tx_s(`S_CHIP + (chip_two ? 11'd2 : 11'd0) + col - 4'd13, 1'b0, fx, fy, W, 0, 1'b0);
            end
        end
    end

    // SETTINGS: 6 rows (HAND removed), name in cols 1-6, value in cols 9-13; switch rows dim
    // item = the entry of the SETN list shown on this row (rows 3..6 show items 4..7)
    wire [2:0] item   = (row >= 3'd3) ? row + 3'd1 : row;
    wire       sw_row = (item == 3'd2 || item == 3'd5);              // BALL, THEME: on switches
    reg [15:0] s_col; reg [`TX_W-1:0] s_txt;
    always @(*) begin
        s_col = c_bg; s_txt = {`TX_W{1'b0}};
        if (row == 3'd0) begin
            s_col = c_title;
            if (col < 4'd8) s_txt = tx_s(`S_SETT + col, 1'b0, fx, fy, W, 0, 1'b0);              // "SETTINGS"
            else if (mcol >= 5'd14 && mrow == 4'd0) s_txt = tx_s(`S_BACKH + mcol - 5'd14, 1'b1, mfx, mfy, W, 0, 1'b0);
        end else if (row != 3'd7) begin
            if (row == hover) s_col = c_hov;
            if (col >= 4'd1 && col < 4'd7)                                                   // row name
                s_txt = tx_s(`S_SETN + {item - 3'd1, 2'b00} + {item - 3'd1, 1'b0} + col - 4'd1, 1'b0, fx, fy,
                             sw_row ? c_dim : (row == hover ? Y : W), 0, 1'b0);
            else if (sw_row && col == 4'd15)                                                 // "S" = on a switch
                s_txt = tx_l(6'd51, 1'b0, fx, fy, c_dim, 0, 1'b0);
            else if (col >= 4'd9 && col < 4'd14) begin                                       // value
                case (item)
                    3'd1: s_txt = tx_s(`S_SETV + 11'd60 + {settings[`SET_SPIN_HI:`SET_SPIN_LO], 2'b00} +
                                       settings[`SET_SPIN_HI:`SET_SPIN_LO] + col - 4'd9, 1'b0, fx, fy, C, 0, 1'b0);
                    3'd2: s_txt = tx_s(`S_SETV + 11'd10 + {settings[`SET_LB_HI:`SET_LB_LO], 2'b00} +
                                       settings[`SET_LB_HI:`SET_LB_LO] + col - 4'd9, 1'b0, fx, fy, c_dim, 0, 1'b0);
                    3'd3: s_txt = tx_s(`S_SETV + (settings[`SET_LEFTY] ? 11'd30 : 11'd25) + col - 4'd9, 1'b0, fx, fy, c_dim, 0, 1'b0);
                    3'd4: if (col == 4'd9) s_txt = tx_l(6'd17 + settings[`SET_SENS_HI:`SET_SENS_LO], 1'b0, fx, fy, C, 0, 1'b0);
                    3'd5: s_txt = tx_s(`S_SETV + (settings[`SET_THEME] ? 11'd40 : 11'd35) + col - 4'd9, 1'b0, fx, fy, c_dim, 0, 1'b0);
                    3'd6: if (col == 4'd9) s_txt = tx_l(6'd17 + settings[`SET_BRI_HI:`SET_BRI_LO], 1'b0, fx, fy, C, 0, 1'b0);
                    default: s_txt = tx_s(`S_SETV + 11'd45 + {erase_step, 2'b00} + erase_step + col - 4'd9,
                                          1'b0, fx, fy, (erase_step == 2'd1) ? `C_RED : C, 0, 1'b0);
                endcase
            end
        end
    end

    // HIGH SCORES: top 5 of the tab + lifetime stats (read from the image)
    reg [15:0] h_col; reg [`TX_W-1:0] h_txt; reg [6:0] h_lo, h_hi;
    always @(*) begin
        h_col = c_bg; h_txt = {`TX_W{1'b0}};
        h_lo = ebase; h_hi = ebase + 7'd1;
        if (row == 3'd0) begin
            h_col = c_title;
            if (col < 4'd5) h_txt = tx_s(`S_TOP5 + col, 1'b0, fx, fy, W, 0, 1'b0);           // "TOP 5"
            else if (col >= 4'd10 && col < 4'd15) begin                                       // tab "FULL"/"QUICK"
                h_col = `C_MAGENTA;
                h_txt = tx_s(`S_TABS + (tab_quick ? 11'd5 : 11'd0) + col - 4'd10, 1'b0, fx, fy, W, 0, 1'b0);
            end
        end else if (row <= 3'd5) begin                                                       // the 5 entries
            if (col >= 4'd3 && col <= 4'd5) h_lo = ebase + 7'd2 + (col - 4'd3);               // an initial
            case (col)
                4'd1: h_txt = tx_l(6'd16 + row, 1'b0, fx, fy, Y, 0, 1'b0);                     // place 1..5
                4'd3, 4'd4, 4'd5: h_txt = tx_l(rd_hi[7] ? 6'd33 + rd_lo[5:0] : 6'd13, 1'b0, fx, fy, W, 0, 1'b0);
                4'd9, 4'd10, 4'd11: h_txt = tx_l(rd_hi[7] ? dg3(b9, col - 4'd9) : 6'd13, 1'b0, fx, fy, C, 0, 1'b0);
                default: ;
            endcase
        end else if (mrow == 4'd8) begin                         // STRIKES n   SPARES n
            if (mcol < 5'd13) begin h_lo = `IM_STRK; h_hi = `IM_STRK + 7'd1; end
            else              begin h_lo = `IM_SPAR; h_hi = `IM_SPAR + 7'd1; end
            if (mcol < 5'd7)                        h_txt = tx_s(`S_STRK + mcol, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
            else if (mcol >= 5'd8 && mcol < 5'd12)  h_txt = tx_l(dg5(b16, mcol - 5'd7), 1'b1, mfx, mfy, W, 0, 1'b0);
            else if (mcol >= 5'd13 && mcol < 5'd19) h_txt = tx_s(`S_SPRS + mcol - 5'd13, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
            else if (mcol >= 5'd20)                 h_txt = tx_l(dg5(b16, mcol - 5'd19), 1'b1, mfx, mfy, W, 0, 1'b0);
        end else if (mrow == 4'd9) begin
            if (mcol < 5'd12) begin h_lo = `IM_GAMES; h_hi = `IM_GAMES + 7'd1; end
            else              begin h_lo = tbl;       h_hi = tbl + 7'd1;       end
            if (mcol < 5'd5)                        h_txt = tx_s(`S_GAMES + mcol, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
            else if (mcol >= 5'd6 && mcol < 5'd11)  h_txt = tx_l(dg5(b16, mcol - 5'd6), 1'b1, mfx, mfy, W, 0, 1'b0);
            else if (mcol >= 5'd13 && mcol < 5'd17) h_txt = tx_s(`S_BEST + mcol - 5'd13, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
            else if (mcol >= 5'd18 && mcol < 5'd21)
                h_txt = tx_l(rd_hi[7] ? dg3(b9, mcol - 5'd18) : (mcol == 5'd20 ? 6'd16 : 6'd0), 1'b1, mfx, mfy, W, 0, 1'b0);
        end
    end

    // HELP: title + 8 lines of 3x5 text (24 characters each)
    reg [15:0] p_col; reg [`TX_W-1:0] p_txt;
    always @(*) begin
        p_col = c_bg; p_txt = {`TX_W{1'b0}};
        if (row == 3'd0) begin
            p_col = c_title;
            if (col >= 4'd2 && col < 4'd13) p_txt = tx_s(`S_HELPT + col - 4'd2, 1'b0, fx, fy, W, 0, 1'b0);
        end else if (mrow >= 4'd2 && mrow <= 4'd9)
            p_txt = tx_s(`S_HELP + {mrow - 4'd2, 4'd0} + {mrow - 4'd2, 3'd0} + mcol, 1'b1, mfx, mfy,
                         mrow[0] ? W : 16'hBDF7, 0, 1'b0);
    end

    // GAME OVER: score (1P big; 2P both + winner), "NEW HIGH SCORE!", hint
    reg [15:0] o_col; reg [`TX_W-1:0] o_txt;
    always @(*) begin
        o_col = c_bg; o_txt = {`TX_W{1'b0}};
        if (row == 3'd0) begin
            o_col = c_title;
            if (col >= 4'd3 && col < 4'd12) o_txt = tx_s(`S_GOVER + col - 4'd3, 1'b0, fx, fy, W, 0, 1'b0);
        end else if (!two_players && px_y >= 6'd16 && px_y < 6'd32 && px_x >= 7'd30 && px_x < 7'd66)
            o_txt = tx_l(dg3(g0b, (big(px_x - 7'd30) >> 3)), 1'b0, big(px_x - 7'd30) & 3'd7, (px_y - 6'd16) >> 1, Y, 0, 1'b0);
        else if (two_players && (row == 3'd2 || row == 3'd3)) begin          // P1 nnn / P2 nnn
            case (col)
                4'd3: o_txt = tx_l(6'd48, 1'b0, fx, fy, W, 0, 1'b0);                          // P
                4'd4: o_txt = tx_l(row == 3'd2 ? 6'd17 : 6'd18, 1'b0, fx, fy, W, 0, 1'b0);   // 1 / 2
                4'd7, 4'd8, 4'd9: o_txt = tx_l(dg3(row == 3'd2 ? g0b : g1b, col - 4'd7), 1'b0, fx, fy, Y, 0, 1'b0);
                default: ;
            endcase
        end else if (two_players && row == 3'd5 && col >= 4'd3) begin       // "Pn WINS" / "TIE GAME"
            if (game0 == game1) begin
                if (col < 4'd11) o_txt = tx_s(`S_TIE + col - 4'd3, 1'b0, fx, fy, C, 0, 1'b0);
            end else if (col == 4'd3) o_txt = tx_l(6'd48, 1'b0, fx, fy, C, 0, 1'b0);
            else if (col == 4'd4) o_txt = tx_l(game0 > game1 ? 6'd17 : 6'd18, 1'b0, fx, fy, C, 0, 1'b0);
            else if (col >= 4'd6 && col < 4'd11) o_txt = tx_s(`S_WINS + col - 4'd6, 1'b0, fx, fy, C, 0, 1'b0);
        end else if (row == 3'd6 && newhi != 0 && blink && col < 4'd15)
            o_txt = tx_s(`S_NEWHI + col, 1'b0, fx, fy, `C_MAGENTA, 0, 1'b0);
        else if (mrow == 4'd9 && mcol >= 5'd3 && mcol < 5'd20)
            o_txt = tx_s(`S_CONT + mcol - 5'd3, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
    end

    // INITIALS: 3 big letters, the current one blinks and is underlined
    reg [15:0] n_col; reg [`TX_W-1:0] n_txt;
    always @(*) begin
        n_col = c_bg; n_txt = {`TX_W{1'b0}};
        if (row == 3'd0) begin
            n_col = c_title;
            if (col < 4'd15) n_txt = tx_s(`S_NEWHI + col, 1'b0, fx, fy, W, 0, 1'b0);
        end else if (row == 3'd1) begin
            if (col == 4'd0)      n_txt = tx_l(6'd48, 1'b0, fx, fy, Y, 0, 1'b0);                         // P
            else if (col == 4'd1) n_txt = tx_l(name_player ? 6'd18 : 6'd17, 1'b0, fx, fy, Y, 0, 1'b0);   // 1 / 2
            else if (col >= 4'd2) n_txt = tx_s(`S_ENTER + col - 4'd2, 1'b0, fx, fy, W, 0, 1'b0);
        end else if (px_y >= 6'd24 && px_y < 6'd40 && px_x >= 7'd30 && px_x < 7'd66) begin
            n_txt = tx_l(6'd33 + ((big(px_x - 7'd30) >> 3) == 0 ? name[14:10] :
                                  (big(px_x - 7'd30) >> 3) == 1 ? name[9:5] : name[4:0]),
                         1'b0, big(px_x - 7'd30) & 3'd7, (px_y - 6'd24) >> 1,
                         ((big(px_x - 7'd30) >> 3) == name_pos && blink) ? Y : W, 0, 1'b0);
        end else if (px_y == 6'd41 && px_x >= 7'd30 + {name_pos, 3'b000} + {1'b0, name_pos, 2'b00} &&
                     px_x <  7'd40 + {name_pos, 3'b000} + {1'b0, name_pos, 2'b00})
            n_col = Y;                                                                           // underline
        else if (row == 3'd6) begin
            if (col >= 4'd6 && col <= 4'd8)
                n_txt = tx_l(dg3(name_player ? g1b : g0b, col - 4'd6), 1'b0, fx, fy, C, 0, 1'b0);
        end else if (mrow == 4'd9 && mcol < 5'd23)
            n_txt = tx_s(`S_NAMEH + mcol, 1'b1, mfx, mfy, c_dim, 0, 1'b0);
    end

    // which screen is on
    always @(*) begin
        en = 1'b1; color = c_bg; txt = {`TX_W{1'b0}};
        ra_lo = `IM_BEST; ra_hi = `IM_BEST + 7'd1;
        case (game_state)
            `GS_TITLE:    begin color = t_col; txt = t_txt; end
            `GS_MENU:     begin color = m_col; txt = m_txt; end
            `GS_SETTINGS: begin color = s_col; txt = s_txt; end
            `GS_SCORES:   begin color = h_col; txt = h_txt; ra_lo = h_lo; ra_hi = h_hi; end
            `GS_HELP:     begin color = p_col; txt = p_txt; end
            `GS_GAMEOVER: begin color = o_col; txt = o_txt; end
            `GS_NAME:     begin color = n_col; txt = n_txt; end
            default:      en = 1'b0;                              // in a game: other layers draw
        endcase
    end
endmodule
