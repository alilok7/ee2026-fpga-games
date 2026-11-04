//=============================================================================
// keylight_defs.vh : the KeyLight interface contract (FROZEN)
//-----------------------------------------------------------------------------
// Owner   : all four students (changes need A+B+C+D to agree)
// Purpose : every code, bit position and field slice that crosses a part
//           boundary is named here once, so no module uses a magic number
//           for something another student produces.
// Usage   : `include "keylight_defs.vh" at the top of any module file.
//           Verilog-2001 has no structs, so multi-field buses are packed
//           vectors and the field slices are `defines, e.g.
//               settings[`KL_SET_VOLUME]
// See docs/INTERFACES.md for the human-readable version with timing notes.
//=============================================================================
`ifndef KEYLIGHT_DEFS_VH
`define KEYLIGHT_DEFS_VH

//----------------------------------------------------------------- display --
`define KL_OLED_W        96
`define KL_OLED_H        64

//------------------------------------------------------------ modes (D->all) -
`define KL_MODE_W        4
`define KL_MODE_TITLE    4'd0
`define KL_MODE_MENU     4'd1
`define KL_MODE_SONGSEL  4'd2
`define KL_MODE_PLAY     4'd3
`define KL_MODE_RESULTS  4'd4
`define KL_MODE_NAME     4'd5
`define KL_MODE_LEARN    4'd6
`define KL_MODE_FREE     4'd7
`define KL_MODE_SCORES   4'd8
`define KL_MODE_SETTINGS 4'd9
`define KL_MODE_TEST     4'd15   // colour bars (base build / self test)

//------------------------------------------------ songs and difficulty (D) --
`define KL_SONG_MYSONG   3'd4    // 0..3 are ROM songs
`define KL_NUM_ROM_SONGS 4
`define KL_DIFF_EASY     2'd0
`define KL_DIFF_NORMAL   2'd1
`define KL_DIFF_HARD     2'd2

//------------------------------------------- settings bus (D -> A, C, D) ----
// 16-bit packed vector. Reset defaults are in KL_SETTINGS_DEFAULT.
`define KL_SETTINGS_W    16
`define KL_SET_INSTR     1:0     // 0 piano, 1 organ, 2 chiptune, 3 bell
`define KL_SET_VOLUME    4:2     // 0..7 master volume
`define KL_SET_SPEED     6:5     // 0 slow, 1 normal, 2 fast, 3 very fast
`define KL_SET_GUIDES    7       // 1 = LED guide lights on
`define KL_SET_METRO     8       // 1 = metronome in Play / Learn
`define KL_SET_THEME     9       // 0 dark, 1 light
`define KL_SET_BRIGHT    11:10   // 0 = 25 %, 1 = 50 %, 2 = 75 %, 3 = 100 %
//                       15:12      reserved, always 0
// instr=0, vol=5, speed=1, guides=1, metro=0, theme=0, bright=3
`define KL_SETTINGS_DEFAULT 16'b0000_11_0_0_1_01_101_00

//------------------------------------------------------- keys (B -> all) ----
// key_strike / key_level are 13 bits in CHROMATIC order:
// bit 0 = C4, 1 = C#4, 2 = D4, ... 11 = B4, 12 = C5.
`define KL_NKEYS         13
`define KL_NLANES        8       // Play lanes = white keys C4..C5
`define KL_MIDI_C4       7'd60

//---------------------------------------------------- buttons (B -> D, C) ---
// btn_press / btn_long / btn_repeat / btn_level are 5 bits, order {U,D,L,R,C}
`define KL_BTN_U         4
`define KL_BTN_D         3
`define KL_BTN_L         2
`define KL_BTN_R         1
`define KL_BTN_C         0

//------------------------------------------------------ sound bus (-> A) ----
// ev_valid (1-cycle pulse), ev_note [6:0] MIDI number, ev_vel [1:0]
// sfx_valid (1-cycle pulse), sfx_id [3:0]
`define KL_VEL_SOFT      2'd1
`define KL_VEL_NORMAL    2'd2
`define KL_VEL_LOUD      2'd3
`define KL_SFX_MOVE      4'd1
`define KL_SFX_SELECT    4'd2
`define KL_SFX_BACK      4'd3
`define KL_SFX_PERFECT   4'd4
`define KL_SFX_MISS      4'd5
`define KL_SFX_COMBO     4'd6
`define KL_SFX_RECORD    4'd7    // new high score jingle
`define KL_SFX_CLICK     4'd8    // metronome tick (normal beat)
`define KL_SFX_CLICK_HI  4'd9    // metronome tick (bar downbeat)

//------------------------------------------------------------ chart port ----
// One 24-bit word per address, 9-bit address (512 words per song).
//   word 0  : header {step_ms[23:14], event_count[13:5], 5'b0}
//   word 1+ : event  {note[23:17], start_step[16:6], len_steps[5:0]}
//             note == 0 marks the end of the song.
// step_ms = milliseconds per 16th note = 15000 / BPM (precomputed by the
// song script so the hardware never divides).
`define KL_CHART_AW      9
`define KL_CHART_DW      24
`define KL_HDR_STEPMS    23:14
`define KL_HDR_COUNT     13:5
`define KL_EV_NOTE       23:17
`define KL_EV_START      16:6
`define KL_EV_LEN        5:0

//------------------------------------------------------ results (C -> D, B) -
`define KL_GRADE_S       3'd0
`define KL_GRADE_A       3'd1
`define KL_GRADE_B       3'd2
`define KL_GRADE_C       3'd3
`define KL_GRADE_D       3'd4

//------------------------------------------- 7-segment glyph codes (-> D) ---
// Producers send glyph codes, never raw segments. D's driver owns the table.
// 0..9 digits, 10..35 letters A..Z, then symbols.
`define KL_G_A           6'd10
`define KL_G_BLANK       6'd36
`define KL_G_DASH        6'd37
`define KL_G_UNDER       6'd38

//--------------------------------------------------------------- colours ----
// RGB565 helpers used by every renderer (one visual language).
`define KL_BLACK         16'h0000
`define KL_WHITE         16'hFFFF
`define KL_GREY          16'h8410
`define KL_DKGREY        16'h31A6

`endif
