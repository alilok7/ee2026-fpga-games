`timescale 1ns / 1ps
`include "strike_defs.vh"
// game_fsm.v - main state machine: title, menus, game, game over, names, settings
// Student D
module game_fsm (
    input  wire        clk,
    input  wire        rst,
    input  wire        tick_game,
    input  wire        load_done,
    input  wire [6:0]  cursor_x,
    input  wire [5:0]  cursor_y,
    input  wire        mouse_move,
    input  wire        l_press,
    input  wire        r_press,
    input  wire        r_level,
    input  wire        m_press,
    input  wire signed [3:0] wheel,
    input  wire [4:0]  btn_press,
    input  wire [4:0]  btn_repeat,
    input  wire [4:0]  btn_long,
    input  wire        sw_lefty,
    input  wire        paused,
    input  wire [3:0]  sw_play,
    output reg         nudge_l,
    output reg         nudge_r,
    input  wire [`GS_W-1:0] tstate,
    input  wire        t_active,
    input  wire        t_game_over,
    input  wire [`PK_W-1:0] t_kind,
    output reg         go_new,
    output reg         go_resume,
    output reg  [`PK_W-1:0] kind_out,
    output wire [9:0]  leave_mask,
    output reg         abort,
    input  wire [8:0]  game0, game1,
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
    output reg  [`GS_W-1:0] game_state,
    output reg  [`SET_W-1:0] settings,
    output wire [`SET_W-1:0] settings_raw,
    output reg  [2:0]  hover,
    output reg         chip_two,
    output reg         has_save,
    output wire [2:0]  leave_idx,
    output reg         tab_quick,
    output reg  [1:0]  erase_step,
    output reg  [14:0] name,
    output reg  [1:0]  name_pos,
    output reg         name_player,
    output reg  [1:0]  newhi,
    output reg         card_show,
    output reg         aim_zoom,
    output reg         want_replay,
    output reg         skip
);
    parameter M_TITLE = 4'd0, M_MENU = 4'd1, M_PLAY = 4'd2, M_SET = 4'd5, M_SCORES = 4'd6,
              M_HELP = 4'd7, M_OVER = 4'd8, M_NAME = 4'd9, M_BOOT = 4'd10, M_QUAL = 4'd11;
    reg [3:0] mode, nextmode;

    assign leave_mask = 10'd0;
    assign leave_idx  = 3'd1;

    // clicks and buttons turned into simple events
    wire b_up   = btn_press[`BTN_U] | btn_repeat[`BTN_U];
    wire b_down = btn_press[`BTN_D] | btn_repeat[`BTN_D];
    wire b_sel  = btn_press[`BTN_C];
    wire b_back = btn_press[`BTN_L];
    wire b_card = btn_press[`BTN_R];
    wire click  = l_press;
    wire [2:0] row_at = (cursor_y < 6'd8) ? 3'd0 : cursor_y[5:3];
    wire chip_zone = (cursor_x >= 7'd78);
    reg moved = 1'b0;
    always @(posedge clk) moved <= mouse_move;
    // a row is picked by clicking it or pressing btnC
    wire act      = (click && row_at != 0 && row_at == hover) || (b_sel && hover != 0);
    wire act_chip = click && chip_zone;
    wire chip_hit = (act_chip && (row_at == 3'd2 || row_at == 3'd3)) || b_card;
    wire any_sel  = click || b_sel;
    wire back     = b_back || r_press;

    reg [`SET_W-1:0] set_r;
    reg       set_dirty;
    reg [2:0] q;
    reg [7:0] tmp;
    reg [8:0] qual_score;
    reg       qual_p;
    wire [6:0] tbl_last = (t_kind[`PK_FULL] ? `IM_TOPF : `IM_TOPQ) + 7'd20;
    wire       last_player = !(t_kind[`PK_TWO] && !qual_p);

    // next state
    always @(*) begin
        nextmode = mode;
        case (mode)
            M_BOOT:   if (load_done && !persist_busy && q >= 3'd2) nextmode = M_TITLE;
            M_TITLE:  if (any_sel) nextmode = M_MENU;
            M_MENU: begin
                if (b_back)        nextmode = M_TITLE;
                else if (chip_hit) nextmode = M_MENU;
                else if (act) case (hover)
                    3'd1: if (has_save) nextmode = M_PLAY;
                    3'd2, 3'd3:         nextmode = M_PLAY;
                    3'd4:               nextmode = M_SCORES;
                    3'd5:               nextmode = M_SET;
                    3'd6:               nextmode = M_HELP;
                    default: ;
                endcase
            end
            M_PLAY: begin
                if (paused && any_sel)        nextmode = M_MENU;
                else if (btn_long[`BTN_L])    nextmode = M_MENU;
                else if (t_game_over)         nextmode = M_QUAL;
            end
            M_QUAL:   if (q >= 3'd2 && last_player) nextmode = M_OVER;
            M_OVER:   if (any_sel && !persist_busy) nextmode = (newhi != 2'b00) ? M_NAME : M_SCORES;
            M_NAME:   if (!(back && name_pos != 2'd0) && any_sel && name_pos == 2'd2 &&
                          !(!name_player && newhi[1])) nextmode = M_SCORES;
            M_SET:    if (back) nextmode = M_MENU;
            M_SCORES: if (back) nextmode = M_MENU;
            M_HELP:   if (back || any_sel) nextmode = M_MENU;
            default:  nextmode = M_MENU;
        endcase
    end

    always @(posedge clk) begin
        if (rst) mode <= M_BOOT;
        else     mode <= nextmode;
    end

    // game_state that the other parts use
    always @(*) begin
        case (mode)
            M_TITLE, M_BOOT: game_state = `GS_TITLE;
            M_MENU:   game_state = `GS_MENU;
            M_PLAY:   game_state = tstate;
            M_SET:    game_state = `GS_SETTINGS;
            M_SCORES: game_state = `GS_SCORES;
            M_HELP:   game_state = `GS_HELP;
            M_NAME:   game_state = `GS_NAME;
            default:  game_state = `GS_GAMEOVER;
        endcase
    end

    // some settings come straight from the switches
    always @(*) begin
        settings = set_r;
        settings[`SET_OIL]   = sw_play[3];
        settings[`SET_THEME] = sw_play[2];
        settings[`SET_LB_HI:`SET_LB_LO] = sw_play[1] ? 2'd2 : sw_play[0] ? 2'd0 : 2'd1;
        settings[`SET_LEFTY] = 1'b0;
    end
    assign settings_raw = set_r;

    // change one letter of the initials, A to Z and back round
    wire [4:0] cur_letter = (name_pos == 2'd0) ? name[14:10] : (name_pos == 2'd1) ? name[9:5] : name[4:0];
    wire       letter_up  = (wheel < 0) || b_up;
    wire [4:0] new_letter = letter_up ? ((cur_letter == 5'd25) ? 5'd0  : cur_letter + 5'd1)
                                      : ((cur_letter == 5'd0)  ? 5'd25 : cur_letter - 5'd1);

    always @(posedge clk) begin
        go_new <= 0; go_resume <= 0; abort <= 0; c_settings <= 0; c_insert <= 0; c_gameend <= 0;
        c_defaults <= 0; save_req <= 0; want_replay <= 0; skip <= 0; nudge_l <= 0; nudge_r <= 0;
        if (rst) begin
            set_r <= `SET_DEFAULT; set_dirty <= 0; hover <= 3'd2; chip_two <= 0; has_save <= 0;
            tab_quick <= 0; erase_step <= 0; name <= 0; name_pos <= 0; name_player <= 0; newhi <= 0;
            card_show <= 0; aim_zoom <= 0; kind_out <= 0; ra <= `IM_GVALID;
            q <= 0; tmp <= 0; qual_score <= 0; qual_p <= 0; ins_quick <= 0; ins_score <= 0; ins_name <= 0;
            gend_full <= 0; gend_score <= 0;
        end else begin
            if (mode != M_BOOT && mode != M_QUAL) begin
                ra <= `IM_GVALID;
                if (ra == `IM_GVALID) has_save <= rd[0];
            end
            if (mode != M_PLAY) aim_zoom <= 1'b0;
            if (moved && row_at != 0) hover <= row_at;
            if (b_up   && hover > 3'd1) hover <= hover - 3'd1;
            if (b_down && hover < 3'd7) hover <= hover + 3'd1;

            case (mode)
                // wait for the flash to load, then read back the settings
                M_BOOT: if (load_done && !persist_busy) begin
                    q <= q + 3'd1;
                    case (q)
                        3'd0:    ra <= `IM_SET_LO;
                        3'd1:    begin tmp <= rd; ra <= `IM_SET_HI; end
                        default: begin set_r <= {rd, tmp}; q <= 0; end
                    endcase
                end
                M_TITLE: if (nextmode == M_MENU) hover <= 3'd2;
                // main menu
                M_MENU: begin
                    if (hover == 3'd7) hover <= 3'd6;
                    if (!b_back && chip_hit) chip_two <= ~chip_two;
                    if (nextmode == M_PLAY) begin
                        card_show <= 1'b0;
                        if (hover == 3'd1) go_resume <= 1'b1;
                        else begin go_new <= 1'b1; kind_out <= {1'b0, chip_two, hover == 3'd3}; end
                    end
                    if (nextmode == M_SET) begin erase_step <= 2'd0; hover <= 3'd1; end
                end
                // in a game: scorecard and zoom
                M_PLAY: begin
                    if (btn_press[`BTN_D] || (r_press && (tstate == `GS_RESULT || tstate == `GS_SWEEP)))
                        card_show <= ~card_show;
                    aim_zoom <= r_level && !t_kind[`PK_SPARE] && (tstate == `GS_AIM || tstate == `GS_THROW ||
                                tstate == `GS_ROLL || tstate == `GS_PINACTION || tstate == `GS_SETTLE);
                    if (tstate == `GS_AIM) begin
                        nudge_l <= btn_press[`BTN_L] | btn_repeat[`BTN_L];
                        nudge_r <= btn_press[`BTN_R] | btn_repeat[`BTN_R];
                    end
                    if (tstate == `GS_RESULT) begin
                        if (m_press || btn_press[`BTN_U]) want_replay <= 1'b1;
                        if (any_sel) skip <= 1'b1;
                    end
                    if (tstate == `GS_REPLAY && any_sel) skip <= 1'b1;
                    if (nextmode == M_MENU) abort <= 1'b1;
                    if (nextmode == M_QUAL) begin q <= 0; qual_p <= 0; newhi <= 0; end
                end
                // check if anyone made the top 5
                M_QUAL: begin
                    if (q != 3'd0 || !persist_busy) q <= q + 3'd1;
                    case (q)
                        3'd0: if (!persist_busy) begin
                            qual_score <= qual_p ? game1 : game0;
                            c_gameend <= 1'b1; gend_full <= t_kind[`PK_FULL]; gend_score <= qual_p ? game1 : game0;
                            ra <= tbl_last;
                        end
                        3'd1: begin tmp <= rd; ra <= tbl_last + 7'd1; end
                        default: begin
                            if (!rd[7] || qual_score > {rd[0], tmp}) newhi[qual_p] <= 1'b1;
                            q <= 0;
                            if (!last_player) qual_p <= 1'b1;
                        end
                    endcase
                end
                M_OVER: begin
                    if (nextmode == M_NAME)   begin name_player <= !newhi[0]; name <= 0; name_pos <= 0; end
                    if (nextmode == M_SCORES) tab_quick <= !t_kind[`PK_FULL];
                end
                // entering initials with the wheel or buttons
                M_NAME: begin
                    if ((moved && wheel != 0) || b_up || b_down) begin
                        case (name_pos)
                            2'd0:    name[14:10] <= new_letter;
                            2'd1:    name[9:5]   <= new_letter;
                            default: name[4:0]   <= new_letter;
                        endcase
                    end
                    if (back && name_pos != 2'd0) name_pos <= name_pos - 2'd1;
                    else if (any_sel) begin
                        if (name_pos != 2'd2) name_pos <= name_pos + 2'd1;
                        else begin
                            c_insert <= 1'b1; ins_quick <= !t_kind[`PK_FULL];
                            ins_score <= name_player ? game1 : game0; ins_name <= name;
                            save_req <= 1'b1;
                            newhi[name_player] <= 1'b0;
                            if (!name_player && newhi[1]) begin name_player <= 1'b1; name <= 0; name_pos <= 0; end
                            else tab_quick <= !t_kind[`PK_FULL];
                        end
                    end
                end
                // settings, saved when you leave
                M_SET: begin
                    if (hover == 3'd7) hover <= 3'd6;
                    if (back) begin
                        if (set_dirty) begin c_settings <= 1'b1; save_req <= 1'b1; set_dirty <= 1'b0; end
                        hover <= 3'd5;
                    end else if (act) begin
                        set_dirty <= set_dirty | (hover == 3'd1) | (hover == 3'd3) | (hover == 3'd5);
                        case (hover)
                            3'd1: set_r[`SET_SPIN_HI:`SET_SPIN_LO] <= set_r[`SET_SPIN_HI:`SET_SPIN_LO] + 2'd1;
                            3'd3: set_r[`SET_SENS_HI:`SET_SENS_LO] <= set_r[`SET_SENS_HI:`SET_SENS_LO] + 2'd1;
                            3'd5: set_r[`SET_BRI_HI:`SET_BRI_LO]   <= set_r[`SET_BRI_HI:`SET_BRI_LO] + 2'd1;
                            3'd6: begin
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
                // high scores, switch between FULL and QUICK
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
