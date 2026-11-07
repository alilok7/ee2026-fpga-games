# StrikeLine Part A — EE2026 revision

This version follows the supplied EE2026 topics: Boolean logic, multiplexers, comparators, adders/subtractors, binary and BCD arithmetic, registers, synchronous counters, shift registers, structural module instances and FSMs. The existing RAM/ROM storage and memory-file loading are retained with the user's approval.

The active .v modules contain no functions, generate loops, for loops, hardware multiplication/division operators, $clog2 calls or integer counters. The two .vh helper libraries retain their existing function interfaces for other project parts; their bodies are explicit combinational add/compare/shift/wiring logic. Part A's active modules use structural blocks instead of these helper functions.

All source is Verilog-2001. There are no Verilog comments. The ASYNC_REG and max_fanout synthesis attributes are preserved because they affect implementation.

## Main corrections

- The 16 switch and 5 button debouncers default to 4-bit counters: 84 counter bits total, rather than 672.
- All other counters have explicit widths. Width parameters are ordinary constants, with no automatic size calculation.
- Startup waits for the two synchronizer flip-flops, silently seeds the initial input level, and suppresses button events while the baseline settles. A switch or button already ON at power-up does not create a toggle or press. Raw din only feeds the first synchronizer flip-flop.
- The gesture multiplier is a shared 17-step shift/add/subtract machine. Its signed 17-bit operands produce a 34-bit product. The divider for gesture ratios is 45 bits wide and emits one quotient bit per clock. No combinational multiplier or divider is inferred by these modules.
- BCD conversion uses nine explicitly instantiated comparator/add/shift stages.
- Repeated input instances and trail wiring are written out explicitly. Existing replay, text, font, speed and swipe storage is retained.

See docs/EE2026_DESIGN.md for the lecture mapping and width table, and docs/CHANGES.md for changes and verification limits.

## Using these files

The source remains in the original strikeline/rtl directory structure. Existing top-level module ports are unchanged. The small structural helper modules are in the existing .v files, so there are no extra RTL files to add to a project file list.

This ZIP is still only Part A. Use the full project's actual strike_defs.vh and .mem files for integration. The separate sim/checks/support files are artificial simulation fixtures and must not be copied into the game's RTL or ROM directories.

Run the isolated checks with `sh sim/checks/run.sh` from strikeline after installing Icarus Verilog. The runner explicitly selects Verilog-2001 and returns failure when an assertion stops simulation.
