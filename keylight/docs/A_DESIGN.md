# Part A: sound engine (Student A)

*Status: vertical slice, with one square-wave DDS voice. Phase 3 adds 4 voices, ADSR, instruments, SFX ROM and metronome.*

## Block diagram
```
ev_valid/ev_note --> note_rom (MIDI -> 24-bit increment) --> phase accumulator (+inc per tick_sample)
                                                               | phase[23] = square wave
tick_1ms --> envelope (amp, linear decay) --> x volume --> sample (8-bit, 128 = silence)
sample --> audio_out (8-bit PWM @ 390 kHz) --> JA1 (Pmod AMP2 AIN)
       \--> scope_sample (to B's Free Play scope)
```

## Key decisions
- **DDS, not a counter per note.** `f_out = inc × 48828.125 / 2^24`, so one adder makes any pitch, and the table is data from `tools/gen_note_table.py`. The resolution is 48828.125 / 2^24 = 0.0029 Hz.
- **Why 48.828 kHz:** it is 100 MHz / 2048, a power of two, so the sample tick is a wrapping 11-bit counter. It is above twice the highest audible frequency.
- **PWM output:** the AMP2 low-pass filters a fast PWM into an analogue level. 8 bits at 100 MHz / 256 = 390 kHz, far above hearing. Only `audio_out.v` knows which Pmod is fitted.
- **`timebase.v`** (shared, explained by A): one divider makes every tick, used as clock enables.

## How this relates to what we learned
`timebase` is the Lab 4 clock-divider counter, but its output is a one-cycle *enable* instead of a new clock, so the design stays in one clock domain (L1/L2). The phase accumulator is a counter (L2) that counts by `inc` instead of 1.

## Tests
`sim/a/tb_sound_engine.v` counts square-wave cycles over one second of samples: A4 = 440, C5 = 523. It also checks that mute gives silence.

## Resource use
See the log in `docs/INTERFACES.md`.

## Likely assessor questions (to complete: 15)
1. *How does DDS make a 440 Hz tone?* The accumulator adds `inc = 151183` every 1/48828 s. It wraps 2^24 / 151183 ≈ 111 samples per cycle, so 48828 / 111 ≈ 440 Hz.
2. *What is the frequency resolution?* Fs / 2^24 ≈ 0.003 Hz.
3. *Why PWM and not a DAC?* The AMP2 takes a single-bit input and filters it, so no DAC chip is needed.
4. *What happens with no Pmod connected?* Nothing breaks: the pins are outputs, and the game is visual.
5. …
