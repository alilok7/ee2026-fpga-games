# Changes — 7 November 2026

This is an AI-assisted rewrite produced with OpenAI Codex from the user's supplied EE2026 topic list. It is not a claim of independent student authorship.

The previous restyle widened hardware counters to integer/32-bit registers. That was a mistake for a nearly-full FPGA. The new version has explicit width parameters with defaults selected for the actual timer values. The 21 debounce counters are four bits each. No hardware counter is declared integer. The source bit counts do not establish a mapped FPGA resource result.

Debounce now establishes its initial level from the two-flop synchronized input during a short, silent startup phase. Button event generation waits for that phase. This fixes startup events without loading raw din into level. Dedicated tests cover a one-clock cold reset, a longer reset with inputs already high, held inputs through another reset, and a subsequent real button press.

The supplied RAM/ROM storage is retained as authorized. The other modules have been rewritten or expanded into explicit combinational blocks, registers, synchronous counters, structural instances and FSM control. There are no functions, loops or generate blocks in the active .v modules. The original two helper-header interfaces remain available to other project parts; their implementations contain only explicit combinational wiring, comparisons, shifts and additions.

The mouse scale helpers are explicit combinational blocks. Display BCD conversion is structural. Repeated debounce/event instances and trail comparisons/wiring/shifts are written out. Text requests are structural wiring blocks. Nested multiplexers are expanded into if/else logic. Replay signals have descriptive names and snapshot outputs are unpacked individually. The seven-segment decoder and supplied ROM interfaces keep their behaviour.

Gesture products use one shared signed 17-by-17-bit sequential shift/add/subtract unit, with a 34-bit result. The midpoint cross product is 34 bits and squared chord length is 33 bits. A shared 45-bit unsigned sequential divider handles aim and spin. Both the signed multiplier and unsigned divider emit one-clock completion pulses. Existing module ports and the original leading parameter names/order are preserved. Additional width parameters are optional. Helper modules are defined in existing source files.

All Verilog comments remain removed, and the RTL is Verilog-2001. The reset max_fanout and synchronizer ASYNC_REG attributes remain.

# Verification

- All supplied gesture behavioural assertions pass. None were weakened or removed.
- All 65,536 unsigned 8-bit numerator/divisor combinations pass, including divide-by-zero behaviour, exact W-clock latency and the completion pulse.
- Signed sequential multiplication passes boundary cases and 500 randomized operand pairs with exact 17-clock latency.
- All 512 9-bit BCD inputs and all 65,536 16-bit BCD inputs pass. The structural and compatibility converters are checked.
- Startup tests pass with all switches/buttons initially high. No false toggle or press appears. Release and a later real press still work.
- Timing, pause/slow-motion gating, reset durations, display output and the Left + Right reset combo pass the isolated checks.
- Mouse, rendering, replay and seven-segment controller outputs match the previous version for 20,000 simulation cycles using common inputs. This regression comparison uses the prior source snapshot and is separate from the portable test runner.
- All delivered RTL files compile together with warnings enabled in Icarus Verilog's -g2001 mode using the isolated definitions fixture.

See SIMULATION_RESULTS.txt for simulation output and EE2026_DESIGN.md for the lecture mapping and counter widths.

# Verification limits

The archive is only Part A. The full game's strike_defs.vh, original .mem files, other parts, top-level design and Vivado project are absent. The separate sim/checks/support files are artificial definitions and a monotonic speed table used only for isolated tests. They must not replace the game's real files. The synthetic speed ROM cannot establish the original mph calibration.

No complete Vivado utilization, placement, timing or board test was possible here. In particular, the 94.5% device utilization and the roughly 250-LUT change budget cannot be confirmed from this partial archive. Run the full project's implementation flow before accepting this for the bitstream.
