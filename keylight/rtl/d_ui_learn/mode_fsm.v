`timescale 1ns / 1ps
`include "keylight_defs.vh"
//=============================================================================
// mode_fsm.v : the product's top-level state machine (single owner of mode)
//-----------------------------------------------------------------------------
// Owner   : Student D
// Style   : Lecture 3 FSM: (1) state register, (2) next-state logic,
//           (3) output logic. Each screen's own little state (menu cursor,
//           selected song, difficulty) is a "sub-FSM" register updated next
//           to the main state, as in Lecture 4 (modular FSMs).
// Transitions (slice):
//   TITLE    --C-->  MENU                 (long D -> TEST colour bars)
//   MENU     --C-->  SONGSEL (Play/Learn), FREE, SCORES, SETTINGS; L -> TITLE
//   SONGSEL  --C-->  PLAY or LEARN;  U/D song, R difficulty, L -> MENU
//   PLAY     --res_valid--> RESULTS;  L -> SONGSEL (abort)
//   RESULTS  --C--> SONGSEL,  R -> PLAY (retry),  L -> MENU
//   others   --L--> MENU
//   anywhere: long-press L -> MENU
// Ports
//   btn_*        {U,D,L,R,C} pulses from input_conditioner
//   rec_exists   B has a saved recording -> MY SONG is selectable
//   res_valid    C finished a song
//   mode, menu_idx, song_id, difficulty, learn_sel, settings  -> everyone
//   sfx_valid/sfx_id  UI sounds for A
//=============================================================================
module mode_fsm (
    input  wire                      clk,
    input  wire                      rst,
    input  wire [4:0]                btn_press,
    input  wire [4:0]                btn_long,
    input  wire [4:0]                btn_repeat,
    input  wire                      rec_exists,
    input  wire                      res_valid,
    output reg  [`KL_MODE_W-1:0]     mode,
    output reg  [2:0]                menu_idx,
    output reg  [2:0]                song_id,
    output reg  [1:0]                difficulty,
    output reg                       learn_sel,
    output reg  [`KL_SETTINGS_W-1:0] settings,
    output reg                       sfx_valid,
    output reg  [3:0]                sfx_id
);
    localparam MENU_ITEMS = 3'd5;

    // Navigation: a press, or an auto-repeat while held.
    wire up    = btn_press[`KL_BTN_U] | btn_repeat[`KL_BTN_U];
    wire down  = btn_press[`KL_BTN_D] | btn_repeat[`KL_BTN_D];
    wire left  = btn_press[`KL_BTN_L];
    wire right = btn_press[`KL_BTN_R];
    wire sel   = btn_press[`KL_BTN_C];
    wire home  = btn_long[`KL_BTN_L];

    wire [2:0] last_song = rec_exists ? `KL_SONG_MYSONG : 3'd3;

    // ---------------- (2) next-state logic ----------------------------------
    reg [`KL_MODE_W-1:0] next_mode;
    always @(*) begin
        next_mode = mode;                       // default: stay
        if (home && mode != `KL_MODE_TITLE) begin
            next_mode = `KL_MODE_MENU;
        end else begin
            case (mode)
                `KL_MODE_TITLE:
                    if (sel)                        next_mode = `KL_MODE_MENU;
                    else if (btn_long[`KL_BTN_D])   next_mode = `KL_MODE_TEST;
                `KL_MODE_MENU:
                    if (left) next_mode = `KL_MODE_TITLE;
                    else if (sel)
                        case (menu_idx)
                            3'd0, 3'd1: next_mode = `KL_MODE_SONGSEL;
                            3'd2:       next_mode = `KL_MODE_FREE;
                            3'd3:       next_mode = `KL_MODE_SCORES;
                            default:    next_mode = `KL_MODE_SETTINGS;
                        endcase
                `KL_MODE_SONGSEL:
                    if (left)     next_mode = `KL_MODE_MENU;
                    else if (sel) next_mode = learn_sel ? `KL_MODE_LEARN : `KL_MODE_PLAY;
                `KL_MODE_PLAY:
                    if (res_valid) next_mode = `KL_MODE_RESULTS;
                    else if (left) next_mode = `KL_MODE_SONGSEL;
                `KL_MODE_RESULTS:
                    if (sel)        next_mode = `KL_MODE_SONGSEL;
                    else if (right) next_mode = `KL_MODE_PLAY;
                    else if (left)  next_mode = `KL_MODE_MENU;
                `KL_MODE_TEST:
                    if (left || sel) next_mode = `KL_MODE_TITLE;
                default:                         // LEARN, FREE, SCORES, SETTINGS, NAME
                    if (left) next_mode = `KL_MODE_MENU;
            endcase
        end
    end

    // ---------------- (1) state register + sub-state registers --------------
    always @(posedge clk) begin
        if (rst) begin
            mode       <= `KL_MODE_TITLE;
            menu_idx   <= 3'd0;
            song_id    <= 3'd0;
            difficulty <= `KL_DIFF_NORMAL;
            learn_sel  <= 1'b0;
            settings   <= `KL_SETTINGS_DEFAULT;
        end else begin
            mode <= next_mode;
            // Menu cursor (sub-FSM of MENU), wraps around.
            if (mode == `KL_MODE_MENU) begin
                if (up)   menu_idx <= (menu_idx == 3'd0) ? MENU_ITEMS - 3'd1 : menu_idx - 3'd1;
                if (down) menu_idx <= (menu_idx == MENU_ITEMS - 3'd1) ? 3'd0 : menu_idx + 3'd1;
                if (sel)  learn_sel <= (menu_idx == 3'd1);
            end
            // Song list and difficulty (sub-FSM of SONGSEL).
            if (mode == `KL_MODE_SONGSEL) begin
                if (up)    song_id <= (song_id == 3'd0) ? last_song : song_id - 3'd1;
                if (down)  song_id <= (song_id == last_song) ? 3'd0 : song_id + 3'd1;
                if (right) difficulty <= (difficulty == `KL_DIFF_HARD) ? `KL_DIFF_EASY
                                                                       : difficulty + 2'd1;
            end
            // MY SONG vanished (erase): fall back to song 0.
            if (song_id > last_song) song_id <= 3'd0;
        end
    end

    // ---------------- (3) output logic: UI sound effects --------------------
    always @(posedge clk) begin
        sfx_valid <= 1'b0;
        sfx_id    <= 4'd0;
        if (!rst && mode != `KL_MODE_PLAY && mode != `KL_MODE_FREE) begin
            if (next_mode != mode && (left || home)) begin
                sfx_valid <= 1'b1; sfx_id <= `KL_SFX_BACK;
            end else if (next_mode != mode || (sel && mode != `KL_MODE_TITLE)) begin
                sfx_valid <= 1'b1; sfx_id <= `KL_SFX_SELECT;
            end else if (up || down || right) begin
                sfx_valid <= 1'b1; sfx_id <= `KL_SFX_MOVE;
            end
        end
    end
endmodule
