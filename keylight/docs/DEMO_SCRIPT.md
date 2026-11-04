# KeyLight demo script (2 to 5 minutes)

Every step is at most three button presses from the previous one. ✅ marks steps that work in the current bitstream; 🔜 marks later phases.

| # | Presenter | Action | Show | Status |
|---|---|---|---|---|
| 1 | D | Power on | Animated title: falling notes, light sweep over KEYLIGHT, LED chase. The 7-seg shows `HEL0`. | ✅ |
| 2 | D → C | C, C, C (menu → Play → Twinkle, Normal) | Song select with BPM, difficulty and best score, and the hint bar | ✅ |
| 3 | C | Play Twinkle | LED guides glow brighter as notes approach. Perfect/Good/Miss pop-ups, lane flash, star burst. Combo and multiplier on the 7-seg, combo meter on `led[7:3]`. Each hit plays the melody (A). | ✅ (single voice) |
| 4 | C → D | Song ends | Results: score, grade, counts, accuracy. Then NEW RECORD, initials and "SAVING…" | ✅ results / 🔜 record, initials, save |
| 5 | B | Long-L → Free Play | Chords on 13 keys, live scope, octave switch | ✅ piano / 🔜 scope |
| 6 | B | R: record 8 bars with count-in, play back, save as MY SONG | Recording status bar, `led[2]` blinking | 🔜 |
| 7 | D | Learn → MY SONG | The tune just recorded is taught note by note | 🔜 |
| 8 | B | Reprogram the FPGA | The high score and MY SONG are still there | 🔜 |
| 9 | A | Settings | Change the instrument and volume, then show brightness and theme | 🔜 |

Backup if the audio Pmod fails: the game is fully playable on visuals and LEDs alone. Say so, and show the scope in Free Play.
