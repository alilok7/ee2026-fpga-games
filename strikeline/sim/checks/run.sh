#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
checks="$PWD/sim/checks"
rtl="$PWD/rtl"
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
iverilog -g2001 -Wall -I "$checks/support" -I "$rtl/d_game_ui" -o "$build/all" "$rtl"/*/*.v
echo "PASS compile_all: all Part A RTL in Verilog-2001 mode"
iverilog -g2001 -Wall -s tb_controls -o "$build/controls" "$checks/tb_controls.v" "$rtl/d_game_ui/debounce.v" "$rtl/d_game_ui/button_events.v" "$rtl/top/reset_gen.v" "$rtl/a_gesture/div_seq.v"
vvp -N "$build/controls"
iverilog -g2001 -Wall -I "$checks/support" -I "$rtl/d_game_ui" -s tb_ui -o "$build/ui" "$checks/tb_ui.v" "$rtl/top/timebase.v" "$rtl/d_game_ui/input_conditioner.v" "$rtl/d_game_ui/debounce.v" "$rtl/d_game_ui/button_events.v" "$rtl/d_game_ui/seg7_ctrl.v" "$rtl/d_game_ui/seg7_driver.v"
vvp -N "$build/ui"
iverilog -g2001 -Wall -I "$checks/support" -s tb_startup -o "$build/startup" "$checks/tb_startup.v" "$rtl/d_game_ui/input_conditioner.v" "$rtl/d_game_ui/debounce.v" "$rtl/d_game_ui/button_events.v"
vvp -N "$build/startup"
iverilog -g2001 -Wall -I "$checks/support" -I "$rtl/d_game_ui" -s tb_datapaths -o "$build/datapaths" "$checks/tb_datapaths.v" "$rtl/a_gesture/div_seq.v" "$rtl/d_game_ui/seg7_ctrl.v"
vvp -N "$build/datapaths"
iverilog -g2001 -Wall -I "$checks/support" -s tb_gesture -o "$build/gesture" "$PWD/sim/a/tb_gesture.v" "$rtl/a_gesture/swipe_capture.v" "$rtl/a_gesture/gesture_features.v" "$rtl/a_gesture/div_seq.v"
cp "$checks/support/speed_curve.mem" "$build/"
cd "$build"
vvp -N "$build/gesture"
