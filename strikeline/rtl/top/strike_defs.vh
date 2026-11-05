//=============================================================================
// strike_defs.vh : THE shared interface contract of StrikeLine (frozen)
//-----------------------------------------------------------------------------
// Owner   : all four students (changes need all four owners to agree)
// Purpose : Every number that crosses a part boundary is defined here once.
//           See docs/INTERFACES.md for the meaning of each signal.
//
// Units (real bowling dimensions, 1 inch = 1 OLED pixel):
//   POS   unsigned Q10.6  inches     (16 bits, 1/64 in, 0 .. 1023.98 in)
//   VEL   signed   Q3.12  in / tick  (16 bits, tick = 1/1024 s)
//   world x : 0 = outer edge of the left gutter, lane centre = 30 in
//   world y : 0 = foul line, head pin = 720 in (60 ft), grows toward the pins
//=============================================================================
`ifndef STRIKE_DEFS_VH
`define STRIKE_DEFS_VH

// ---------------- game_state (D -> everyone) ---------------------------------
`define GS_W              5
`define GS_TITLE          5'd0
`define GS_MENU           5'd1
`define GS_AIM            5'd2    // ball on the foul line, waiting for a grab
`define GS_THROW          5'd3    // swipe in progress (left button held)
`define GS_ROLL           5'd4    // ball rolling down the lane
`define GS_PINACTION      5'd5    // ball reached the pin deck
`define GS_SETTLE         5'd6   // ball in the pit, waiting for pins to settle
`define GS_RESULT         5'd7    // popup + score update
`define GS_SWEEP          5'd8    // pin-setter working (rake / new rack)
`define GS_GAMEOVER       5'd9
`define GS_NAME           5'd10   // initials entry for a new high score
`define GS_PRACTICE_SWIPE 5'd11   // Swipe Lab
`define GS_PRACTICE_SPARE 5'd12   // practice menu + leave picker
`define GS_SCORES         5'd13
`define GS_SETTINGS       5'd14
`define GS_REPLAY         5'd15   // instant replay of the last throw
`define GS_HELP           5'd16

// ---------------- play kind (D -> everyone) ----------------------------------
`define PK_W        3
`define PK_FULL     0             // bit: 1 = 10 frames, 0 = Quick (frames 8-10)
`define PK_TWO      1             // bit: 2-player hot-seat
`define PK_SPARE    2             // bit: Spare Challenge practice (no scoring)

// ---------------- settings (D -> A, B, C) ------------------------------------
`define SET_W        16
`define SET_OIL      0            // 0 = short oil (40 ft), 1 = long oil (45 ft)
`define SET_LB_LO    1            // [2:1] ball weight 0 = 12 lb, 1 = 14 lb, 2 = 16 lb
`define SET_LB_HI    2
`define SET_LEFTY    3            // left-handed (D replaces it with sw[15])
`define SET_SENS_LO  4            // [5:4] mouse sensitivity 0..3 (x0.5 x1 x1.5 x2)
`define SET_SENS_HI  5
`define SET_THEME    6            // 0 = wood, 1 = neon ("cosmic bowling")
`define SET_BRI_LO   7            // [8:7] brightness 0..3 (3 = full)
`define SET_BRI_HI   8
`define SET_SPIN_LO  9            // [10:9] spin sensitivity (v3): 0 normal, 1 high, 2 max, 3 soft
`define SET_SPIN_HI  10
`define SET_DEFAULT  16'h0192     // short oil, 14 lb ball, right hand, sens 1, wood, bright 3, spin normal

// ---------------- throw spin (A -> B, D) -------------------------------------
// v3: signed -31..+31 (was -7..+7). +ve = the swipe curved left = hooks left.
`define SPIN_W      6
`define SPIN_MAX    31

// ---------------- steer window (A -> B, v3) ----------------------------------
// For STEER_TICKS physics ticks after release, sideways mouse motion nudges
// the rolling ball ("body English"): steer_valid + steer_dx (scaled counts).
`define STEER_TICKS 11'd512       // 0.5 s

// ---------------- ball phase (B -> C, D, A) ----------------------------------
`define BP_W        3
`define BP_IDLE     3'd0          // held at the foul line
`define BP_SKID     3'd1          // in the oil: low friction, little hook
`define BP_HOOK     3'd2          // dry lane: spin turns into sideways acceleration
`define BP_ROLL     3'd3          // spin used up: rolls straight in its final direction
`define BP_GUTTER   3'd4          // in a gutter: straight, cannot touch pins
`define BP_PIT      3'd5          // finished, ball is in the pit

// ---------------- pin state (C internal + replay) ----------------------------
`define PS_STANDING 3'd0
`define PS_WOBBLING 3'd1
`define PS_FALLING  3'd2
`define PS_DOWN     3'd3
`define PS_OFF      3'd4          // off the deck (pit), not drawn, not colliding

// ---------------- rack commands (D -> C) -------------------------------------
`define RK_FULL     2'd0          // all 10 pins on their spots
`define RK_SWEEP    2'd1          // rake: clear every pin that is not standing
`define RK_LEAVE    2'd2          // exactly the pins in rack_mask (Spare Challenge)

// ---------------- gesture messages (A -> D) ----------------------------------
`define GM_OK       2'd0
`define GM_FASTER   2'd1          // too short or too slow
`define GM_FORWARD  2'd2          // sideways or backwards
`define GM_CANCEL   2'd3          // right click during the swipe

// ---------------- buttons: btn bus = {U, D, L, R, C} -------------------------
`define BTN_C       0
`define BTN_R       1
`define BTN_L       2
`define BTN_D       3
`define BTN_U       4

// ---------------- world geometry, POS units (inch * 64) ----------------------
`define W_LANE_L    16'd592       //  9.25 in : left lane edge (lane is 41.5 in)
`define W_LANE_R    16'd3248      // 50.75 in : right lane edge
`define W_LANE_CX   16'd1920      // 30 in
`define W_GUT_LX    16'd304       //  4.75 in : centre of the left gutter
`define W_GUT_RX    16'd3536      // 55.25 in : centre of the right gutter
`define W_KICK_L    16'd170       //  2.65 in : pin centre limit at the left kickback
`define W_KICK_R    16'd3670      // 57.35 in
`define W_BALL_Y0   16'd320       //  5 in    : ball centre at release
`define W_OIL_S     16'd30720     // 480 in = 40 ft
`define W_OIL_L     16'd34560     // 540 in = 45 ft
`define W_DECK_Y    16'd45312     // 708 in   : start of the pin deck
`define W_PIN_PIT   16'd48384     // 756 in   : a pin beyond this falls into the pit
`define W_BALL_PIT  16'd48640     // 760 in   : the ball is finished
`define W_SPEED_MIN 16'd205       // 0.05 in/tick (3 mph): the ball never stops on the lane
`define W_SPEED_MIN_DECK 16'd70   // v3: 1 mph floor on the deck (pins can slow the ball more)

// ---------------- screen layout (pixels) -------------------------------------
`define SCR_LANE_W  7'd60         // x 0..59  : lane view, 1 px = 1 in
`define SCR_MAP_X0  7'd61         // x 61..69 : B's minimap (sw[1])
`define SCR_HUD_X0  7'd71         // x 71..95 : D's HUD (top) and A's meters (y >= 36)
`define SCR_MTR_Y0  6'd36

// ---------------- v3: two screens, one render engine (pixels) ----------------
// render_scan draws every frame twice: the VGA picture (160 x 120 logical
// pixels, shown 4x = 640 x 480) and then the OLED picture (96 x 64).
//   scr = 0 : VGA       scr = 1 : OLED
// "UI space" is the 96 x 64 picture of v2 (menus, Swipe Lab, the top-down
// game). The OLED shows it 1:1; the VGA shows it in a framed window at
// (UI_X0, UI_Y0), except during play, when the VGA shows the new 3-D view.
// v3.3: the view fills the whole screen (the scorecard strip on top is gone,
// the scorecard is on the OLED) and the panel is a half-size box drawn at
// 320 x 240 in the top-right corner (H_PANEL_*):
//   x 0..159, y 0..119  first-person view, horizon on row V_HOR, lane centre V_CX
`define VGA_W       8'd160
`define VGA_H       7'd120
`define UI_X0       8'd32
`define UI_Y0       7'd28
`define V_VIEW_W    8'd160
`define V_TOP_H     7'd0
`define V_HOR       7'd30
`define V_CX        8'd80
`define H_PANEL_X0  9'd268
`define H_PANEL_Y1  8'd109
// v3.2: the VGA picture is walked at 320 x 240 (shown 2x). Text, the panel,
// the strip, menus and the pointer still use the 160 x 120 coordinates above
// (the pixel position halved); only the 3-D lane, ball and pins are drawn at
// the full 320 x 240, with these "hi-res" constants (all doubled):
`define H_VIEW_W    9'd320
`define H_TOP_H     8'd0
`define H_HOR       8'd60
`define H_CX        9'd160

// ---------------- save image layout (128 bytes, D) ---------------------------
`define IM_MAGIC0   7'd0          // 'S'
`define IM_MAGIC1   7'd1          // 'L'
`define IM_VER      7'd2
`define IM_SEQ_LO   7'd3          // written by flash_ctrl
`define IM_SEQ_HI   7'd4
`define IM_SET_LO   7'd5
`define IM_SET_HI   7'd6
`define IM_STRK     7'd8          // 16-bit lifetime strikes (lo, hi)
`define IM_SPAR     7'd10         // 16-bit lifetime spares
`define IM_GAMES    7'd12         // 16-bit games finished
`define IM_BEST     7'd14         // best full game (lo, hi)
`define IM_TOPF     7'd16         // 5 x 5 bytes: score lo, {valid, 6'b0, score[8]}, 3 initials (0..25)
`define IM_TOPQ     7'd41         // same for Quick games
`define IM_GVALID   7'd66         // a game in progress is saved
`define IM_GKIND    7'd67         // play kind bits
`define IM_GPLAYER  7'd68
`define IM_GFRAME   7'd69
`define IM_ROLLS0   7'd70         // 21 rolls of player 1 (0..10, 15 = not thrown)
`define IM_ROLLS1   7'd91         // 21 rolls of player 2
`define IM_NROLL0   7'd112
`define IM_NROLL1   7'd113
`define IM_CRC_HI   7'd126        // CRC-16-CCITT over bytes 0..125
`define IM_CRC_LO   7'd127

// ---------------- text request (any layer -> D's shared text engine) --------
// One string ROM and one copy of each font serve every text on the screen.
// A layer that wants a character at this pixel sends:
`define TX_W        53
`define TX_VALID    0             // this layer has a text cell here
`define TX_LIT      1             // 1: VALUE[5:0] is a glyph code, 0: VALUE is a string ROM address
`define TX_VAL      12:2          // 11 bits
`define TX_FONT     13            // 0 = 5x7 (6x8 cell), 1 = 3x5 (4x6 cell)
`define TX_FX       16:14         // column inside the glyph cell
`define TX_FY       19:17         // row inside the glyph cell
`define TX_FG       35:20
`define TX_BG       51:36
`define TX_BGEN     52            // 1: the cell background is opaque

// ---------------- colours (RGB565) -------------------------------------------
`define C_BLACK     16'h0000
`define C_WHITE     16'hFFFF
`define C_RED       16'hF800
`define C_GREEN     16'h07E0
`define C_BLUE      16'h001F
`define C_YELLOW    16'hFFE0
`define C_CYAN      16'h07FF
`define C_MAGENTA   16'hF81F
`define C_ORANGE    16'hFC00
`define C_GREY      16'h8410
`define C_DGREY     16'h4208

`endif
