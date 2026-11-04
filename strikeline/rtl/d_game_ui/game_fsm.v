`timescale 1ns / 1ps
`include "strike_defs.vh"
//=============================================================================
// game_fsm.v : the product's top-level FSM (modes, menus, settings, names)
//-----------------------------------------------------------------------------
// Owner   : Student D
// Style   : Lecture 3/4 modular FSM. The mode register is the main FSM; the
//           bowling itself is the turn_fsm sub-FSM (started with go_new /
//           go_resume, finished with game_over). game_state = the mode's
//           GS_ code, or turn_fsm's state while a game runs.
// Input   : mouse first (hover = the row under the pointer, click = choose),
//           buttons as a second way for everything (U/D move, C chooses,
//           L goes back, R = scorecard). Title -> Quick Game is 2 clicks.
// Menus (5x7 text rows of 8 px; row 0 is the title / hint row):
//   MAIN     1 RESUME 2 QUICK [1P/2P] 3 FULL [1P/2P] 4 PRACTICE 5 SCORES
//            6 SETTINGS 7 HELP          (the chip is x >= 78)
//   PRACTICE 2 SWIPE LAB 3 SPARE CHALLENGE 4 leave chip 6 BACK
//   SETTINGS 1 OIL 2 BALL 3 HAND 4 MOUSE 5 THEME 6 BRIGHT 7 ERASE (2 clicks)
//=============================================================================
module game_fsm (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_game,
    input  wire        load_done,
    input  wire [6:0]  cursor_x,
    input  wire [5:0]  cursor_y,
    input  wire        mouse_move,       // a mouse packet arrived
    input  wire        l_press,
    input  wire        r_press,
    input  wire        m_press,
    input  wire signed [3:0] wheel,
    input  wire [4:0]  btn_press,
    input  wire [4:0]  btn_repeat,
    input  wire [4:0]  btn_long,
    input  wire        sw_lefty,          // sw15
    input  wire [3:0]  sw_play,           // {sw14 long oil, sw13 neon, sw12 16 lb, sw11 12 lb}
    output reg         nudge_l,           // btnL / btnR while aiming: move one board
    output reg         nudge_r,
    // turn_fsm
    input  wire [`GS_W-1:0] tstate,
    input  wire        t_active,
    input  wire        t_game_over,
    input  wire [`PK_W-1:0] t_kind,
    output reg         go_new,
    output reg         go_resume,
    output reg  [`PK_W-1:0] kind_out,
    output reg  [9:0]  leave_mask,
    output reg         abort,
    // scores
    input  wire [8:0]  game0, game1,
    // save image (read) and persist commands
    output reg  [6:0]  ra,
    input  wire [7:0]  rd,
    input  wire        persist_busy,
    output reg         c_settings,
    output reg         c_insert,
    output reg         ins_quick,
    output reg  [8:0]  ins_score,
    output reg  [14:0] ins_name,
    output reg         c_gameend,
    output reg         gend_full,
    output reg  [8:0]  gend_score,
    output reg         c_defaults,
    output reg         save_req,
    // to everyone / renderers
    output reg  [`GS_W-1:0] game_state,
    output reg  [`SET_W-1:0] settings,
    output wire [`SET_W-1:0] settings_raw,     // as chosen in the menu (saved)
    output reg  [2:0]  hover,            // highlighted row (1..7), 0 = none
    output reg         chip_two,         // QUICK / FULL start as 2-player
    output reg         has_save,
    output reg  [2:0]  leave_idx,
    output reg         tab_quick,
    output reg  [1:0]  erase_step,       // 0 SAVES, 1 SURE?, 2 DONE
    output reg  [14:0] name,
    output reg  [1:0]  name_pos,
    output reg         name_player,
    output reg  [1:0]  newhi,            // which players made the top 5
    output reg         card_show,
    output reg         want_replay,
    output reg         skip
);
    localparam M_TITLE = 4'd0, M_MENU = 4'd1, M_PLAY = 4'd2, M_PRACT = 4'd3, M_LAB = 4'd4,
               M_SET = 4'd5, M_SCORES = 4'd6, M_HELP = 4'd7, M_OVER = 4'd8, M_NAME = 4'd9,
               M_BOOT = 4'd10, M_QUAL = 4'd11;
    reg [3:0] mode;

    reg [9:0] leaves_rom [0:7];
    initial $readmemh("leaves.mem", leaves_rom);

    // ---------------- input events -----------------------------------------
    wire b_up   = btn_press[`BTN_U] | btn_repeat[`BTN_U];
    wire b_down = btn_press[`BTN_D] | btn_repeat[`BTN_D];
    wire b_sel  = btn_press[`BTN_C];
    wire b_back = btn_press[`BTN_L];
    wire b_card = btn_press[`BTN_R];
    wire [2:0] row_at = (cursor_y < 6'd8) ? 3'd0 : cursor_y[5:3];   // 8-px rows
    wire chip_zone = (cursor_x >= 7'd78);
    wire click = l_press;
    // the cursor register updates one clock after the packet pulse, so the
    // row under the pointer is read one clock later
    reg moved;
    always @(posedge clk) moved <= mouse_move;
    // activation of the highlighted row by mouse click or btnC
    wire act = (click && row_at != 0 && row_at == hover) || (b_sel && hover != 0);
    wire act_chip = click && chip_zone;

    // ---------------- mode -> game_state -----------------------------------
    always @(*) begin
        case (mode)
            M_TITLE, M_BOOT: game_state = `GS_TITLE;
            M_MENU:   game_state = `GS_MENU;
            M_PLAY:   game_state = tstate;
            M_PRACT:  game_state = `GS_PRACTICE_SPARE;
            M_LAB:    game_state = `GS_PRACTICE_SWIPE;
            M_SET:    game_state = `GS_SETTINGS;
            M_SCORES: game_state = `GS_SCORES;
            M_HELP:   game_state = `GS_HELP;
            M_NAME:   game_state = `GS_NAME;
            default:  game_state = `GS_GAMEOVER;
        endcase
    end

    // settings fields
    reg [`SET_W-1:0] set_r;
    always @(*) begin
        // v2: the physical play settings come from switches (live, visible on
        // the board); the menu keeps mouse sensitivity and brightness
        settings = set_r;
        settings[`SET_OIL]   = sw_play[3];
        settings[`SET_THEME] = sw_play[2];
        settings[`SET_LB_HI:`SET_LB_LO] = sw_play[1] ? 2'd2 : sw_play[0] ? 2'd0 : 2'd1;
        settings[`SET_LEFTY] = sw_lefty;
    end
    reg set_dirty;
    assign settings_raw = set_r;

    // ---------------- sequenced image reads (boot settings, qualification) --
    reg [2:0] q;                         // read step
    reg [7:0] tmp;
    reg [8:0] qual_score;
    reg       qual_p;                    // player being checked
    wire [6:0] tbl_last = (t_kind[`PK_FULL] ? `IM_TOPF : `IM_TOPQ) + 7'd20;    // entry 4

    always @(posedge clk) begin
        go_new <= 0; go_resume <= 0; abort <= 0; c_settings <= 0; c_insert <= 0; c_gameend <= 0;
        c_defaults <= 0; save_req <= 0; want_replay <= 0; skip <= 0; nudge_l <= 0; nudge_r <= 0;
        if (rst) begin
            mode <= M_BOOT; set_r <= `SET_DEFAULT; set_dirty <= 0; hover <= 3'd2; chip_two <= 0;
            has_save <= 0; leave_idx <= 3'd1; tab_quick <= 0; erase_step <= 0; name <= 0; name_pos <= 0;
            name_player <= 0; newhi <= 0; card_show <= 0; kind_out <= 0; leave_mask <= 0; ra <= `IM_GVALID;
            q <= 0; tmp <= 0; qual_score <= 0; qual_p <= 0; ins_quick <= 0; ins_score <= 0; ins_name <= 0;
            gend_full <= 0; gend_score <= 0;
        end else begin
            // the read port normally watches "is a game saved?"
            if (mode != M_BOOT && mode != M_QUAL) begin
                ra <= `IM_GVALID;
                if (ra == `IM_GVALID) has_save <= rd[0];
            end
            // hover follows the pointer when it moves, buttons step it
            if (moved && row_at != 0) hover <= row_at;
            if (b_up   && hover > 3'd1) hover <= hover - 3'd1;
            if (b_down && hover < 3'd7) hover <= hover + 3'd1;

            case (mode)
                M_BOOT: begin                     // wait for the flash load, then read settings
                    if (load_done && !persist_busy) begin
                        q <= q + 3'd1;
                        case (q)
                            3'd0: ra <= `IM_SET_LO;
                            3'd1: begin tmp <= rd; ra <= `IM_SET_HI; end
                            default: begin set_r <= {rd, tmp}; q <= 0; mode <= M_TITLE; end
                        endcase
                    end
                end
                M_TITLE: if (click || b_sel) begin mode <= M_MENU; hover <= 3'd2; end
                M_MENU: begin
                    if (b_back) mode <= M_TITLE;
                    else if ((act_chip && (row_at == 3'd2 || row_at == 3'd3)) || b_card) chip_two <= ~chip_two;
                    else if (act) case (hover)
                        3'd1: if (has_save) begin go_resume <= 1; card_show <= 0; mode <= M_PLAY; end
                        3'd2: begin kind_out <= {1'b0, chip_two, 1'b0}; go_new <= 1; card_show <= 0; mode <= M_PLAY; end
                        3'd3: begin kind_out <= {1'b0, chip_two, 1'b1}; go_new <= 1; card_show <= 0; mode <= M_PLAY; end
                        3'd4: begin mode <= M_PRACT; hover <= 3'd2; end
                        3'd5: mode <= M_SCORES;
                        3'd6: begin mode <= M_SET; erase_step <= 0; hover <= 3'd1; end
                        3'd7: mode <= M_HELP;
                        default: ;
                    endcase
                end
                M_PLAY: begin
                    // v2 buttons: L/R move the stance one board, U replay,
                    // D scorecard, C skip the result, hold L quit
                    if (r_press || btn_press[`BTN_D]) card_show <= ~card_show;
                    if (tstate == `GS_AIM) begin
                        nudge_l <= btn_press[`BTN_L] | btn_repeat[`BTN_L];
                        nudge_r <= btn_press[`BTN_R] | btn_repeat[`BTN_R];
                    end
                    if (tstate == `GS_RESULT) begin
                        if (m_press || btn_press[`BTN_U]) want_replay <= 1;
                        if (click || b_sel) skip <= 1;
                    end
                    if (t_kind[`PK_SPARE] && (btn_long[`BTN_L] || (r_press && tstate == `GS_AIM))) begin
                        abort <= 1; mode <= M_PRACT;
                    end else if (!t_kind[`PK_SPARE] && btn_long[`BTN_L]) begin
                        abort <= 1; mode <= M_MENU;                     // saved at the last frame
                    end else if (t_game_over) begin
                        mode <= M_QUAL; q <= 0; qual_p <= 0; newhi <= 0;
                    end
                end
                M_QUAL: begin                     // stats + top-5 check for each player
                    if (q != 3'd0 || !persist_busy) q <= q + 3'd1;   // one GAMEEND at a time
                    case (q)
                        3'd0: if (!persist_busy) begin
                            qual_score <= qual_p ? game1 : game0;
                            c_gameend <= 1; gend_full <= t_kind[`PK_FULL]; gend_score <= qual_p ? game1 : game0;
                            ra <= tbl_last;
                        end
                        3'd1: begin tmp <= rd; ra <= tbl_last + 7'd1; end
                        default: begin
                            // beats entry 4 (or entry 4 is empty) -> qualifies
                            if (!rd[7] || qual_score > {rd[0], tmp}) newhi[qual_p] <= 1'b1;
                            q <= 0;
                            if (t_kind[`PK_TWO] && !qual_p) qual_p <= 1;
                            else mode <= M_OVER;
                        end
                    endcase
                end
                M_OVER: if ((click || b_sel) && !persist_busy) begin
                    if (newhi[0]) begin mode <= M_NAME; name_player <= 0; name <= 0; name_pos <= 0; end
                    else if (newhi[1]) begin mode <= M_NAME; name_player <= 1; name <= 0; name_pos <= 0; end
                    else begin mode <= M_SCORES; tab_quick <= !t_kind[`PK_FULL]; end
                end
                M_NAME: begin
                    // wheel or U/D change the letter (A..Z wraps), click / C confirms it
                    if ((moved && wheel != 0) || b_up || b_down) begin
                        case (name_pos)
                            2'd0: name[14:10] <= step_letter(name[14:10], (wheel < 0) || b_up);
                            2'd1: name[9:5]   <= step_letter(name[9:5],   (wheel < 0) || b_up);
                            default: name[4:0] <= step_letter(name[4:0], (wheel < 0) || b_up);
                        endcase
                    end
                    if (click || b_sel) begin
                        if (name_pos != 2'd2) name_pos <= name_pos + 2'd1;
                        else begin
                            c_insert <= 1; ins_quick <= !t_kind[`PK_FULL];
                            ins_score <= name_player ? game1 : game0; ins_name <= name;
                            save_req <= 1;
                            newhi[name_player] <= 1'b0;
                            if (!name_player && newhi[1]) begin name_player <= 1; name <= 0; name_pos <= 0; end
                            else begin mode <= M_SCORES; tab_quick <= !t_kind[`PK_FULL]; end
                        end
                    end
                end
                M_PRACT: begin
                    if (b_back || r_press) begin mode <= M_MENU; hover <= 3'd4; end
                    else if (act) case (hover)
                        3'd2: mode <= M_LAB;
                        3'd3: begin
                            kind_out <= 3'b100; leave_mask <= leaves_rom[leave_idx];
                            go_new <= 1; card_show <= 0; mode <= M_PLAY;
                        end
                        3'd4: leave_idx <= leave_idx + 3'd1;
                        3'd6: begin mode <= M_MENU; hover <= 3'd4; end
                        default: ;
                    endcase
                end
                M_LAB: if (b_back || r_press) begin mode <= M_PRACT; hover <= 3'd2; end
                M_SET: begin
                    if (b_back || r_press) begin
                        if (set_dirty) begin c_settings <= 1; save_req <= 1; set_dirty <= 0; end
                        mode <= M_MENU; hover <= 3'd6;
                    end else if (act) begin
                        set_dirty <= (hover == 3'd4) || (hover == 3'd6);
                        // rows 1, 2, 3, 5 (oil, ball, hand, theme) are on switches now
                        case (hover)
                            3'd4: set_r[`SET_SENS_HI:`SET_SENS_LO] <= set_r[`SET_SENS_HI:`SET_SENS_LO] + 2'd1;
                            3'd6: set_r[`SET_BRI_HI:`SET_BRI_LO] <= set_r[`SET_BRI_HI:`SET_BRI_LO] + 2'd1;
                            3'd7: begin
                                if (erase_step == 2'd0) erase_step <= 2'd1;
                                else if (erase_step == 2'd1) begin
                                    erase_step <= 2'd2; c_defaults <= 1; save_req <= 1;
                                    set_r <= `SET_DEFAULT;
                                end
                            end
                            default: ;
                        endcase
                    end
                end
                M_SCORES: begin
                    if (click && cursor_y < 6'd8 && cursor_x >= 7'd60) tab_quick <= ~tab_quick;
                    else if (b_up || b_down) tab_quick <= ~tab_quick;
                    if (b_back || r_press) begin mode <= M_MENU; hover <= 3'd5; end
                end
                M_HELP: if (b_back || r_press || click || b_sel) begin mode <= M_MENU; hover <= 3'd7; end
                default: mode <= M_MENU;
            endcase
        end
    end

    function [4:0] step_letter;
        input [4:0] l;
        input       up;
        step_letter = up ? ((l == 5'd25) ? 5'd0 : l + 5'd1) : ((l == 5'd0) ? 5'd25 : l - 5'd1);
    endfunction
endmodule
