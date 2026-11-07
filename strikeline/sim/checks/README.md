# Isolated Verilog-2001 checks

Install Icarus Verilog (iverilog and vvp), then run `sh sim/checks/run.sh` from strikeline.

The runner first compiles every delivered .v RTL file with -g2001 -Wall. It then runs tb_controls, tb_ui, tb_startup, tb_datapaths and the supplied tb_gesture in a temporary directory. Failed checks use the Verilog $stop task; vvp -N exits with failure without opening an interactive prompt.

The tests cover timer and reset behaviour, all 65,536 8-bit division combinations, startup suppression, signed 17-bit multiplication including boundary cases, all 9-bit and 16-bit BCD inputs, and all original gesture assertions.

support/strike_defs.vh contains artificial game state, button, geometry, text-bus and colour definitions. support/speed_curve.mem is an artificial monotonic speed table. These let this incomplete archive simulate; they do not belong in the full game's RTL or ROM directories.

For full integration testing, use the complete project's actual strike_defs.vh and .mem files and run the Vivado build. The fixture-based tests cannot verify original speed calibration or FPGA fit/timing.
