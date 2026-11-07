`timescale 1ns / 1ps
`include "strike_defs.vh"
// game_fsm.v : main FSM - title, menu, play, game over, initials, scores, settings, help
// Student D. game_state = the state's GS_ code (C's turn_fsm state while playing).
// Mouse first, buttons as a second way: U/D move, C choose, L back, R 1P/2P.
module game_fsm (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_game,        // (not used: kept so the port list matches)
    input  wire        load_done,
    input  wire [6:0]  cursor_x,
    input  wire [5:0]  cursor_y,
    input  wire        mouse_move,       // a mouse packet arrived
    input  wire        l_press,          // 1-clock click pulses
    input  wire        r_press,
    input  wire        r_level,          // right button held (zoom)
    input  wire        m_press,
    input  wire signed [3:0] wheel,
    input  wire [4:0]  btn_press,        // buttons {U, D, L, R, C}
    input  wire [4:0]  btn_repeat,
    input  wire [4:0]  btn_long,
    input  wire        sw_lefty,         // sw15
    input  wire        paused,
    input  wire [3:0]  sw_play,
    output reg         nudge_l,
    output reg         nudge_r,
    // C's turn_fsm (the submachine)
    input  wire [`GS_W-1:0] tstate,
    input  wire        t_active,         // (not used)
    input  wire        t_game_over,
    input  wire [`PK_W-1:0] t_kind,
    output reg         go_new,
    output reg         go_resume,
    output reg  [`PK_W-1:0] kind_out,
    output wire [9:0]  leave_mask,
    output reg         abort,
    // scores (C)
    input  wire [8:0]  game0, game1,
    // save image read port 3, persist_ctrl commands
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
    // to everyone / the renderers
    output reg  [`GS_W-1:0] game_state,
    output reg  [`SET_W-1:0] settings,
    output wire [`SET_W-1:0] settings_raw,
    output reg  [2:0]  hover,            // highlighted row 1..7, 0 = none
    output reg         chip_two,
    output reg         has_save,
    output wire [2:0]  leave_idx,
    output reg         tab_quick,
    output reg  [1:0]  erase_step,       // 0 "SAVES", 1 "SURE?", 2 "DONE"
    output reg  [14:0] name,
    output reg  [1:0]  name_pos,         // which letter (0..2)
    output reg         name_player,      // whose initials (0 = P1)
    output reg  [1:0]  newhi,            // which players made the top 5
    output reg         card_show,        // show the scorecard
    output reg         aim_zoom,
    output reg         want_replay,      // 1 clock: half-speed replay
    output reg         skip
);
    // states (the codes are kept from v3.5)
    parameter M_TITLE = 4'd0, M_MENU = 4'd1, M_PLAY = 4'd2, M_SET = 4'd5, M_SCORES = 4'd6,
              M_HELP = 4'd7, M_OVER = 4'd8, M_NAME = 4'd9, M_BOOT = 4'd10, M_QUAL = 4'd11;
    reg [3:0] mode, nextmode;

    assign leave_mask = 10'd0;
    assign leave_idx  = 3'd1;

    // input events
    wire b_up   = btn_press[`BTN_U] | btn_repeat[`BTN_U];
    wire b_down = btn_press[`BTN_D] | btn_repeat[`BTN_D];
    wire b_sel  = btn_press[`BTN_C];
    wire b_back = btn_press[`BTN_L];
    wire b_card = btn_press[`BTN_R];
    wire click  = l_press;
    wire [2:0] row_at = (cursor_y < 6'd8) ? 3'd0 : cursor_y[5:3];    // the 8-px row under the pointer
    wire chip_zone = (cursor_x >= 7'd78);
    // the pointer updates a clock after the packet pulse, so the row is read a clock later
    reg moved = 1'b0;
    always @(posedge clk) moved <= mouse_move;
    // choose the highlighted row: a click on it, or btnC
    wire act      = (click && row_at != 0 && row_at == hover) || (b_sel && hover != 0);
    wire act_chip = click && chip_zone;
    wire chip_hit = (act_chip && (row_at == 3'd2 || row_at == 3'd3)) || b_card;   // 1P/2P toggle
    wire any_sel  = click || b_sel;
    wire back     = b_back || r_press;

    // registers used by the screens
    reg [`SET_W-1:0] set_r;              // the menu's settings
    reg       set_dirty;
    reg [2:0] q;                         // read step (BOOT, QUAL)
    reg [7:0] tmp;
    reg [8:0] qual_score;
    reg       qual_p;
    wire [6:0] tbl_last = (t_kind[`PK_FULL] ? `IM_TOPF : `IM_TOPQ) + 7'd20;   // entry 5 of the table
    wire       last_player = !(t_kind[`PK_TWO] && !qual_p);                 // QUAL: no more players to check

    // NEXT-STATE LOGIC: this case is the next-state table
    always @(*) begin
        nextmode = mode;
        case (mode)
            M_BOOT:   if (load_done && !persist_busy && q >= 3'd2) nextmode = M_TITLE;   // settings read
            M_TITLE:  if (any_sel) nextmode = M_MENU;
            M_MENU: begin
                if (b_back)        nextmode = M_TITLE;
                else if (chip_hit) nextmode = M_MENU;                  // only the chip toggles
                else if (act) case (hover)
                    3'd1: if (has_save) nextmode = M_PLAY;             // RESUME
                    3'd2, 3'd3:         nextmode = M_PLAY;             // QUICK / FULL
                    3'd4:               nextmode = M_SCORES;
                    3'd5:               nextmode = M_SET;
                    3'd6:               nextmode = M_HELP;
                    default: ;
                endcase
            end
            M_PLAY: begin
                if (paused && any_sel)        nextmode = M_MENU;       // pause + click: leave (saved)
                else if (btn_long[`BTN_L])    nextmode = M_MENU;       // hold btnL: leave (saved)
                else if (t_game_over)         nextmode = M_QUAL;
            end
            M_QUAL:   if (q >= 3'd2 && last_player) nextmode = M_OVER;
            M_OVER:   if (any_sel && !persist_busy) nextmode = (newhi != 2'b00) ? M_NAME : M_SCORES;
            M_NAME:   if (!(back && name_pos != 2'd0) && any_sel && name_pos == 2'd2 &&
                          !(!name_player && newhi[1])) nextmode = M_SCORES;     // last letter of the last player
            M_SET:    if (back) nextmode = M_MENU;
            M_SCORES: if (back) nextmode = M_MENU;
            M_HELP:   if (back || any_sel) nextmode = M_MENU;
            default:  nextmode = M_MENU;
        endcase
    end

    // STATE REGISTER
    always @(posedge clk) begin
        if (rst) mode <= M_BOOT;
        else     mode <= nextmode;
    end

    // OUTPUT LOGIC (Moore): game_state and settings depend on registers only
    always @(*) begin
        case (mode)
            M_TITLE, M_BOOT: game_state = `GS_TITLE;
            M_MENU:   game_state = `GS_MENU;
            M_PLAY:   game_state = tstate;              // the submachine's state
            M_SET:    game_state = `GS_SETTINGS;
            M_SCORES: game_state = `GS_SCORES;
            M_HELP:   game_state = `GS_HELP;
            M_NAME:   game_state = `GS_NAME;
            default:  game_state = `GS_GAMEOVER;        // QUAL, OVER
        endcase
    end

    // play settings from the switches; the menu keeps spin, mouse and brightness
    always @(*) begin
        settings = set_r;
        settings[`SET_OIL]   = sw_play[3];
        settings[`SET_THEME] = sw_play[2];
        settings[`SET_LB_HI:`SET_LB_LO] = sw_play[1] ? 2'd2 : sw_play[0] ? 2'd0 : 2'd1;   // 16 / 12 / 14 lb
        settings[`SET_LEFTY] = 1'b0;          // left-handed option removed (sw15 not used)
    end
    assign settings_raw = set_r;

    // initials: the letter being changed, one step up or down (A..Z wraps)
    wire [4:0] cur_letter = (name_pos == 2'd0) ? name[14:10] : (name_pos == 2'd1) ? name[9:5] : name[4:0];
    wire       letter_up  = (wheel < 0) || b_up;
    wire [4:0] new_letter = letter_up ? ((cur_letter == 5'd25) ? 5'd0  : cur_letter + 5'd1)
                                      : ((cur_letter == 5'd0)  ? 5'd25 : cur_letter - 5'd1);

    // registered outputs: what happens in each state and on each transition (nextmode)
    always @(posedge clk) begin
        // 1-clock pulses: low unless set below
        go_new <= 0; go_resume <= 0; abort <= 0; c_settings <= 0; c_insert <= 0; c_gameend <= 0;
        c_defaults <= 0; save_req <= 0; want_replay <= 0; skip <= 0; nudge_l <= 0; nudge_r <= 0;
        if (rst) begin
            set_r <= `SET_DEFAULT; set_dirty <= 0; hover <= 3'd2; chip_two <= 0; has_save <= 0;
            tab_quick <= 0; erase_step <= 0; name <= 0; name_pos <= 0; name_player <= 0; newhi <= 0;
            card_show <= 0; aim_zoom <= 0; kind_out <= 0; ra <= `IM_GVALID;
            q <= 0; tmp <= 0; qual_score <= 0; qual_p <= 0; ins_quick <= 0; ins_score <= 0; ins_name <= 0;
            gend_full <= 0; gend_score <= 0;
        end else begin
            // every state: watch IM_GVALID (RESUME on / off), move the highlight
            if (mode != M_BOOT && mode != M_QUAL) begin
                ra <= `IM_GVALID;
                if (ra == `IM_GVALID) has_save <= rd[0];
            end
            if (mode != M_PLAY) aim_zoom <= 1'b0;
            // the highlight follows the pointer when it moves; U / D step it
            if (moved && row_at != 0) hover <= row_at;
            if (b_up   && hover > 3'd1) hover <= hover - 3'd1;
            if (b_down && hover < 3'd7) hover <= hover + 3'd1;

            case (mode)
                // BOOT: wait for the flash load, then read the saved settings
                M_BOOT: if (load_done && !persist_busy) begin
                    q <= q + 3'd1;
                    case (q)
                        3'd0:    ra <= `IM_SET_LO;
                        3'd1:    begin tmp <= rd; ra <= `IM_SET_HI; end
                        default: begin set_r <= {rd, tmp}; q <= 0; end
                    endcase
                end
                M_TITLE: if (nextmode == M_MENU) hover <= 3'd2;          // QUICK GAME highlighted
                // MAIN MENU
                M_MENU: begin
                    if (hover == 3'd7) hover <= 3'd6;                     // 6 rows only
                    if (!b_back && chip_hit) chip_two <= ~chip_two;
                    if (nextmode == M_PLAY) begin
                        card_show <= 1'b0;
                        if (hover == 3'd1) go_resume <= 1'b1;
                        else begin go_new <= 1'b1; kind_out <= {1'b0, chip_two, hover == 3'd3}; end  // {spare, 2P, full}
                    end
                    if (nextmode == M_SET) begin erase_step <= 2'd0; hover <= 3'd1; end
                end
                // PLAY: buttons during the game
                M_PLAY: begin
                    // btnD (any time) or a right click after the throw: scorecard
                    if (btn_press[`BTN_D] || (r_press && (tstate == `GS_RESULT || tstate == `GS_SWEEP)))
                        card_show <= ~card_show;
                    // hold the right button to zoom, from aiming to the pin action
                    aim_zoom <= r_level && !t_kind[`PK_SPARE] && (tstate == `GS_AIM || tstate == `GS_THROW ||
                                tstate == `GS_ROLL || tstate == `GS_PINACTION || tstate == `GS_SETTLE);
                    if (tstate == `GS_AIM) begin                          // move one board
                        nudge_l <= btn_press[`BTN_L] | btn_repeat[`BTN_L];
                        nudge_r <= btn_press[`BTN_R] | btn_repeat[`BTN_R];
                    end
                    if (tstate == `GS_RESULT) begin
                        if (m_press || btn_press[`BTN_U]) want_replay <= 1'b1;
                        if (any_sel) skip <= 1'b1;
                    end
                    if (tstate == `GS_REPLAY && any_sel) skip <= 1'b1;    // a click ends the replay
                    if (nextmode == M_MENU) abort <= 1'b1;                // leave: saved at the last frame
                    if (nextmode == M_QUAL) begin q <= 0; qual_p <= 0; newhi <= 0; end
                end
                // QUAL: count the game, then check each player against place 5
                M_QUAL: begin
                    if (q != 3'd0 || !persist_busy) q <= q + 3'd1;        // one GAMEEND at a time
                    case (q)
                        3'd0: if (!persist_busy) begin
                            qual_score <= qual_p ? game1 : game0;
                            c_gameend <= 1'b1; gend_full <= t_kind[`PK_FULL]; gend_score <= qual_p ? game1 : game0;
                            ra <= tbl_last;                               // place 5, score low byte
                        end
                        3'd1: begin tmp <= rd; ra <= tbl_last + 7'd1; end // {valid, score bit 8}
                        default: begin
                            // beats place 5 (or place 5 is empty) -> made the top 5
                            if (!rd[7] || qual_score > {rd[0], tmp}) newhi[qual_p] <= 1'b1;
                            q <= 0;
                            if (!last_player) qual_p <= 1'b1;             // now player 2
                        end
                    endcase
                end
                // GAME OVER
                M_OVER: begin
                    if (nextmode == M_NAME)   begin name_player <= !newhi[0]; name <= 0; name_pos <= 0; end
                    if (nextmode == M_SCORES) tab_quick <= !t_kind[`PK_FULL];
                end
                // INITIALS: wheel / U / D change the letter, click / C confirms
                M_NAME: begin
                    if ((moved && wheel != 0) || b_up || b_down) begin
                        case (name_pos)
                            2'd0:    name[14:10] <= new_letter;
                            2'd1:    name[9:5]   <= new_letter;
                            default: name[4:0]   <= new_letter;
                        endcase
                    end
                    if (back && name_pos != 2'd0) name_pos <= name_pos - 2'd1;    // back one letter
                    else if (any_sel) begin
                        if (name_pos != 2'd2) name_pos <= name_pos + 2'd1;
                        else begin                                        // 3rd letter: save it
                            c_insert <= 1'b1; ins_quick <= !t_kind[`PK_FULL];
                            ins_score <= name_player ? game1 : game0; ins_name <= name;
                            save_req <= 1'b1;
                            newhi[name_player] <= 1'b0;
                            if (!name_player && newhi[1]) begin name_player <= 1'b1; name <= 0; name_pos <= 0; end
                            else tab_quick <= !t_kind[`PK_FULL];
                        end
                    end
                end
                // SETTINGS
                M_SET: begin
                    if (hover == 3'd7) hover <= 3'd6;                     // 6 rows only (HAND removed)
                    if (back) begin
                        if (set_dirty) begin c_settings <= 1'b1; save_req <= 1'b1; set_dirty <= 1'b0; end
                        hover <= 3'd5;
                    end else if (act) begin
                        // keep the dirty flag until we leave (v3.5 lost it: fixed)
                        set_dirty <= set_dirty | (hover == 3'd1) | (hover == 3'd3) | (hover == 3'd5);
                        case (hover)                          // 1 SPIN 2 BALL 3 MOUSE 4 THEME 5 BRIGHT 6 ERASE; 2, 4 on switches
                            3'd1: set_r[`SET_SPIN_HI:`SET_SPIN_LO] <= set_r[`SET_SPIN_HI:`SET_SPIN_LO] + 2'd1;
                            3'd3: set_r[`SET_SENS_HI:`SET_SENS_LO] <= set_r[`SET_SENS_HI:`SET_SENS_LO] + 2'd1;
                            3'd5: set_r[`SET_BRI_HI:`SET_BRI_LO]   <= set_r[`SET_BRI_HI:`SET_BRI_LO] + 2'd1;
                            3'd6: begin                               // erase: 2 clicks
                                if (erase_step == 2'd0) erase_step <= 2'd1;
                                else if (erase_step == 2'd1) begin
                                    erase_step <= 2'd2; c_defaults <= 1'b1; save_req <= 1'b1;
                                    set_r <= `SET_DEFAULT;
                                end
                            end
                            default: ;
                        endcase
                    end
                end
                // HIGH SCORES: FULL / QUICK tab
                M_SCORES: begin
                    if (click && cursor_y < 6'd8 && cursor_x >= 7'd60) tab_quick <= ~tab_quick;
                    else if (b_up || b_down) tab_quick <= ~tab_quick;
                    if (back) hover <= 3'd4;
                end
                M_HELP: if (nextmode == M_MENU) hover <= 3'd6;
                default: ;
            endcase
        end
    end
endmodule
