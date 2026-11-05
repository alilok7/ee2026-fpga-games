`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// seg7_ctrl.v - chooses what the 4-digit display shows
//-----------------------------------------------------------------------------
// Owner   : Student D
// Character codes are the ones in seg7_driver.v (0-9 digits, 10.. letters,
// 37 '-', 39 blank).
//   menus           a word for the highlighted item (PLAY, PrAC, HI, SEt ...)
//   after a throw   the ball speed, e.g. "17.2" mph, for 3 s
//   during a game   the current player's provisional score; in a 2-player
//                   game the left digit is the player number
//   Spare Challenge made . tries, e.g. "03.05"
//   game over       the score; 2 players: P1 and P2 take turns every 1.5 s
//   Swipe Lab       the speed of the last swipe
//   paused          "PAUS"
//=============================================================================
module seg7_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_game,        // 1 ms tick
    input  wire [`GS_W-1:0] game_state,
    input  wire [2:0]  hover,
    input  wire        paused,
    input  wire        throw_valid,
    input  wire [7:0]  mph10,            // speed x 10 (172 = 17.2 mph)
    input  wire [8:0]  score0,           // provisional score of player 1
    input  wire [8:0]  score1,           // provisional score of player 2
    input  wire        player,           // whose turn it is
    input  wire        two,              // 2-player game
    input  wire        spare,            // Spare Challenge
    input  wire [7:0]  made,
    input  wire [7:0]  tries,
    output reg  [23:0] glyphs,
    output reg  [3:0]  dps
);
    // character codes
    localparam [5:0] A = 6'd10, B = 6'd11, Cc = 6'd12, D = 6'd13, E = 6'd14, F = 6'd15, H = 6'd17,
                     I = 6'd18, L = 6'd21, M = 6'd22, N = 6'd23, O = 6'd24, P = 6'd25, R = 6'd27,
                     S = 6'd28, T = 6'd29, U = 6'd30, WW = 6'd32, Yy = 6'd34, DASH = 6'd37, BL = 6'd39;

    // ---- 1. speed timer: show the speed for 3000 ms after a throw ---------
    reg [11:0] speed_ms;
    reg [7:0]  speed;                    // speed of the last throw
    always @(posedge clk) begin
        if (rst == 1) begin
            speed_ms <= 0;
            speed    <= 0;
        end
        else if (throw_valid == 1) begin
            speed_ms <= 3000;
            speed    <= mph10;
        end
        else if (tick_game == 1 && speed_ms != 0) begin
            speed_ms <= speed_ms - 1;
        end
    end

    // ---- 2. game over with 2 players: swap P1 / P2 every 1500 ms ----------
    reg [10:0] swap_ms;
    reg        swap;
    always @(posedge clk) begin
        if (rst == 1) begin
            swap_ms <= 0;
            swap    <= 0;
        end
        else if (tick_game == 1) begin
            if (swap_ms == 1499) begin
                swap_ms <= 0;
                swap    <= ~swap;
            end
            else begin
                swap_ms <= swap_ms + 1;
            end
        end
    end

    // ---- 3. split the numbers into decimal digits -------------------------
    // which player's score to show
    wire       who   = (game_state == `GS_GAMEOVER) ? (two & swap) : player;
    wire [8:0] score = (who == 1) ? score1 : score0;

    wire [3:0] score_100 = score / 100;
    wire [3:0] score_10  = (score / 10) % 10;
    wire [3:0] score_1   = score % 10;

    wire [3:0] speed_100 = speed / 100;
    wire [3:0] speed_10  = (speed / 10) % 10;
    wire [3:0] speed_1   = speed % 10;

    wire [3:0] made_10   = (made / 10) % 10;
    wire [3:0] made_1    = made % 10;
    wire [3:0] tries_10  = (tries / 10) % 10;
    wire [3:0] tries_1   = tries % 10;

    // ---- 4. the four characters for each kind of display ------------------
    // score: player digit, then the score without leading zeros
    reg [5:0] p_digit, s_d2, s_d1;
    always @(*) begin
        if (two == 1)
            p_digit = (who == 1) ? 6'd2 : 6'd1;
        else
            p_digit = BL;

        if (score_100 == 0)
            s_d2 = BL;
        else
            s_d2 = {2'b00, score_100};

        if (score_100 == 0 && score_10 == 0)
            s_d1 = BL;
        else
            s_d1 = {2'b00, score_10};
    end
    wire [23:0] score_chars = {p_digit, s_d2, s_d1, {2'b00, score_1}};

    // speed: " 17.2" (the decimal point is turned on below)
    wire [5:0]  sp_d2       = (speed_100 == 0) ? BL : {2'b00, speed_100};
    wire [23:0] speed_chars = {BL, sp_d2, {2'b00, speed_10}, {2'b00, speed_1}};

    // Spare Challenge: "03.05"
    wire [23:0] spare_chars = {{2'b00, made_10}, {2'b00, made_1}, {2'b00, tries_10}, {2'b00, tries_1}};

    wire in_game = (game_state >= `GS_AIM && game_state <= `GS_SWEEP) || game_state == `GS_REPLAY;

    // ---- 5. choose what to show (combinational), then register it --------
    reg [23:0] chars;
    reg [3:0]  dots;
    always @(*) begin
        dots  = 4'b0000;
        chars = {BL, BL, BL, BL};
        if (paused == 1 && in_game == 1) begin
            chars = {P, A, U, S};
        end
        else begin
            case (game_state)
                `GS_TITLE: chars = {B, O, WW, L};
                `GS_MENU: begin
                    case (hover)
                        3'd1:    chars = {R, E, S, U};
                        3'd2:    chars = {6'd3, BL, F, R};
                        3'd3:    chars = {6'd1, 6'd0, F, R};
                        3'd4:    chars = {P, R, A, Cc};
                        3'd5:    chars = {H, I, BL, BL};
                        3'd6:    chars = {S, E, T, BL};
                        default: chars = {H, E, L, P};
                    endcase
                end
                `GS_PRACTICE_SPARE: chars = {P, R, A, Cc};
                `GS_PRACTICE_SWIPE: begin chars = speed_chars; dots = 4'b0010; end
                `GS_SETTINGS:       chars = {S, E, T, BL};
                `GS_SCORES:         chars = {H, I, BL, BL};
                `GS_HELP:           chars = {H, E, L, P};
                `GS_NAME:           chars = {N, A, M, E};
                `GS_GAMEOVER:       chars = score_chars;
                default: begin                         // in a game
                    if (speed_ms != 0) begin
                        chars = speed_chars;
                        dots  = 4'b0010;
                    end
                    else if (game_state == `GS_THROW) begin
                        chars = {DASH, DASH, DASH, DASH};
                    end
                    else if (spare == 1) begin
                        chars = spare_chars;
                        dots  = 4'b0100;
                    end
                    else begin
                        chars = score_chars;
                    end
                end
            endcase
        end
    end

    always @(posedge clk) begin
        glyphs <= chars;
        dps    <= dots;
    end
endmodule
