# How this code relates to EE2026

| Code | Building blocks from the supplied syllabus |
|---|---|
| debounce | Two D flip-flops, a 2-bit startup counter, an input-level register, magnitude/equality comparison, a small synchronous counter |
| button_events | State register, combinational next-state logic, three named states, counters, registered output pulses |
| reset_gen | Two initialized synchronous counters and reset output registers |
| timebase | Mod-N synchronous counters, two 2-bit divide-by-four counters, clock-enable pulses |
| seg7_driver | A 2-bit digit counter, a four-input multiplexer, and a glyph-to-segment decoder |
| seg7_ctrl | State-controlled multiplexers, registered display outputs, structural BCD converter stages |
| input_conditioner | Explicit structural module instances and a reset-combo counter with a rearm flip-flop |
| div_seq | Shift registers, a magnitude comparator, a subtractor and a down-counter |
| gesture_multiply | Shift registers, an adder/subtractor and a 5-bit down-counter |
| gesture_features | A modular FSM controlling sample selection and the shared arithmetic blocks |
| mouse_setup | A setup FSM, position registers, adders/subtractors, multiplexers and boundary comparisons |
| swipe_capture | Position registers, additions and shifts for averaging, counters, supplied ring/trail storage |
| gesture_render | Magnitude comparisons, priority multiplexers, fixed wiring and small display registers |
| replay_buffer | Two small control sub-machines, shift registers, counters and supplied snapshot RAM |
| text_engine/string_rom | Supplied font/string ROMs and pixel-selection multiplexers |
| strings_map.vh | Constant values for addresses |

The existing bcd_fns.vh and txt_helpers.vh interfaces are retained so other project parts can still include and call them. A helper function here is only a named combinational expression; its implementation uses comparisons, additions and shifts. Neither helper header is included by the rewritten Part A .v modules.

## Startup

During reset, the synchronizer flip-flops continue sampling the pins. After reset, debounce counts three clocks and loads level from the second synchronizer flip-flop. This initial load does not assert toggled. Normal millisecond debouncing then begins.

button_events waits four clocks after reset before generating events. This gives debounce time to establish its startup level. It enters HELD if the button was already high and IDLE if it was low. Later releases and presses produce the normal events. These few startup clocks establish the baseline; they are not a millisecond debounce interval for a new press.

## Default counter sizes

| Register | Bits | Values required at the default settings |
|---|---:|---|
| Each debounce count | 4 | 0–4 for switches; 0–9 for buttons |
| Debounce startup | 2 | 0–3 |
| Button hold_ms | 10 | 0–1000; stops at 1000 |
| Button repeat_ms | 9 | 0–399, then 0–99 |
| Button startup | 3 | 0–4 |
| Input combo_ms | 11 | 0–1999 |
| Power-up reset counter | 20 | 0–999999 |
| Ordinary reset counter | 20 | 0–999999 |
| Millisecond divider | 17 | 0–99999 |
| Physics divider | 17 | 0–97655 |
| Sample divider | 19 | 0–499999 |
| Each slow-motion phase | 2 | 0–3 |
| Sequential divider count | 6 | 0–40 normally; 0–45 in gesture_features |
| Sequential multiplier count | 5 | 0–17 |

Width parameters are explicit: debounce.W; input_conditioner.SW_W, BTN_W, COMBO_W; button_events.HOLD_W, REPEAT_W; reset_gen.COUNT_W; timebase.MS_W, PHYS_W, SMP_W; div_seq.COUNT_W.

If you increase a timing value, choose enough bits for the counter's largest stored value. A B-bit unsigned counter represents 0 through 2^B - 1. Most timers store duration - 1. The button hold timer stores LONG_MS itself, and the divider's bit counter stores W itself. Timing parameters and widths must be positive. div_seq.W may be increased beyond 63 if COUNT_W is increased accordingly.

## Gesture arithmetic

Speed is the largest forward displacement over a 16-sample window near the end of the trimmed swipe. Short swipes use their full forward displacement. A ROM maps the resulting index to speed.

Aim divides the magnitude of sideways displacement times 256 by forward displacement. Small ratios fall in the dead zone. The shared multiplier scales the remaining ratio by speed.

For spin, let (dx, df) be the total swipe displacement and (mx, mf) the middle sample's displacement from the start. The signed midpoint offset is proportional to:

`cross = mx * df - mf * dx`

The divider calculates `abs(cross) * 2048 / (dx*dx + df*df)`. Comparators, shifts and a small multiplexer apply the dead zone, sensitivity and limit of 31. The whole ratio is capped at 256 before the small 9-bit sensitivity logic: any larger value would already saturate at 31 for every sensitivity setting.

The multiplier processes one multiplier bit per clock. For two's-complement numbers, the final multiplier bit has negative weight. Therefore the first 16 bits add the shifted multiplicand when set, and the final sign bit subtracts it when set. This uses one stored partial product rather than a parallel array of adders.

The midpoint method can miss an S-shaped curve whose middle point lies on the start-to-end line. It preserves the supplied gesture test behaviours, but it does not reproduce the old whole-path signed-area method for every possible trajectory.
