# Part D: UI framework, Learn mode, system control (Student D)

*Status: mode FSM, text engine, title, menu, song select, results, hint bar, pause overlay, 7-seg driver and theme/brightness post-processing are done. Phase 3 adds settings, high scores, initials, Learn mode and fades.*

## Block diagram
```
btn events --> mode_fsm (state reg + next-state + output logic) --> mode, song, difficulty, settings
px_x/px_y --> text_grid (col = x*43>>8, row = y>>3) --> layout per screen --> string_rom --> font_rom --> pixel
ui_renderer: D's screens + overlay (hint bar on every screen, pause banner)
mux_video: pick the renderer by mode --> overlay --> theme --> brightness --> capture --> OLED
ui_status --> 7-seg word / LED chase;  seg7_driver: 1 digit per ms (250 Hz per digit)
results_latch: latch C's results, convert to BCD (bin2bcd, sequential)
```

## Mode FSM (L3 style)
TITLE –C→ MENU –C→ SONGSEL –C→ PLAY –(song end)→ RESULTS –R→ PLAY (retry). From RESULTS, C goes to SONGSEL and L to MENU. MENU also leads to FREE, SCORES and SETTINGS, and every one of them goes back with L. A long press of L goes to MENU from anywhere. A long press of D on TITLE opens the colour-bar TEST.

## Key decisions
- **Text is data.** All words are in `text/strings.txt` and the font is in `text/font5x7.txt`. Python generates the ROMs and `strings_map.vh` (the addresses), so the screens never compare against hard-coded characters.
- **Divider-free grid:** x/6 = (x × 43) >> 8, exact for x < 96. y / 96 in `pixel_xy` uses 96 = 32 × 3 and n / 3 = (n × 171) >> 9. Both are verified exhaustively.
- **One overlay layer** draws the hint bar on every screen (the UX criterion) without each part drawing its own.
- **Post-processing once, at the end:** brightness ×1, ¾, ½ or ¼ uses shifts only. The theme swaps black and white.
- **Video timing:** the renderers are combinational and longer than 10 ns. `mux_video` captures the colour 7 clocks after the pixel position changes, and the XDC gives those paths 6 clocks. `tb_top` checks every pixel of a frame at the OLED's latch edge.

## How this relates to what we learned
`mode_fsm` is exactly the L3 structure (state register, next-state logic, output logic). The menu cursor and song list are sub-FSMs (L4, modular FSMs). The 7-seg driver is the lab's multiplexing: one anode at a time, at about 250 Hz per digit.

## Tests
- `sim/d/tb_mode_fsm.v` covers the demo path, wrap-around, MY SONG appearing and disappearing, and the long-L rule.
- `sim/d/tb_pixel_xy.v` checks all 6144 pixels and the text grid.
- `sim/top/tb_top.v` covers the whole chip, including the pixel timing.

## Likely assessor questions (to complete: 15)
1. *How does a pixel become a letter?* Its cell is col = x / 6 and row = y / 8. The layout says which string and character go there. The font ROM gives the 5-bit row for that glyph, and bit (4 − fx) is the pixel.
2. *Why 250 Hz per digit?* Four digits at 1 kHz is above the flicker threshold, and inside the manual's 200–500 Hz hint.
3. *How does brightness work in RGB565?* Each channel is scaled separately with shifts: x − x/4, x/2 or x/4.
4. …
