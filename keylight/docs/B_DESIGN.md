# Part B: input, Free Play, recorder, storage (Student B)

*Status: input conditioner complete and tested, and the Free Play piano works. Phase 3 adds the scope, note names, recorder, playback and MY SONG. Phase 4 adds the QSPI flash save.*

## Block diagram
```
sw[15:0], btn[4:0] --> 2-flop synchroniser --> debounce (5 ms switches / 10 ms buttons)
   switches: level change in EITHER direction --> key_strike[12:0] (chromatic order)
   buttons : button_events --> press / long (1 s) / repeat (400 ms, then every 100 ms)
   U+D held 2 s --> soft_reset_req --> reset_gen
key_strike --> free_play: strike queue --> note events to A; glow timers --> piano screen + LEDs
mux_io: picks LEDs / 7-seg / sound bus by mode
```

## Key decisions
- **Strike on any change**, so a player never resets a switch. A flip down plays, and a flip back up plays again.
- **Stable-count debounce, not a lock-out.** The manual's 200 ms lock-out would block fast repeated notes. A 5 ms stable count only adds 5 ms of fixed delay, which C's judge compensates for (`LAG_MS`).
- **Switches 5 ms, buttons 10 ms:** buttons bounce for longer, and menus don't need speed.
- **No fake strike at reset:** the debouncer loads the current switch level on reset.
- **Soft reset re-arms only after release**, so holding the buttons can't cause a reset loop.
- **Chords:** strikes in the same clock are queued and sent one per clock, so no note is lost.

## How this relates to what we learned
The synchroniser is the two-flip-flop chain from L1 (metastability). The debounce and hold timers are L2 counters enabled by `tick_1ms`, the same idea as the lab's 1 ms detection. Press, long and repeat are a small sequential circuit on the debounced level.

## Tests
`sim/b/tb_input_conditioner.v` covers bounce, both flip directions, no strike at reset, glitch rejection, a 13-key chord, press, long press, auto-repeat and the soft reset (13 checks).

## Likely assessor questions (to complete: 15)
1. *Why two flip-flops?* The first may go metastable. The second gives it a whole clock period to settle.
2. *Why not debounce with a long lock-out?* It would block strikes faster than the lock-out time.
3. *How do you detect both directions?* The `toggled` pulse fires whenever the debounced level changes, whichever way.
4. …
