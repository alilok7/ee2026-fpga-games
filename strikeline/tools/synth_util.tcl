# synth_util.tcl - synthesis only, with a per-module LUT/FF report (resource squeeze)
#   From strikeline/:   vivado -mode batch -source tools/synth_util.tcl
#   -> build/hier_utilization.rpt
set root  [file normalize [file join [file dirname [info script]] ..]]
set dest  [file join $root build]
set work  [file normalize [file join $::env(TEMP) strikeline_synth]]
file delete -force $work
file mkdir $dest
file mkdir $work
cd $work
foreach f [glob [file join $root data *.mem]] { file copy -force $f $work }
set srcs {}
foreach dir {top provided a_gesture b_ball c_pins d_game_ui} {
    foreach f [glob -nocomplain [file join $root rtl $dir *.v]] { lappend srcs $f }
}
read_verilog $srcs
read_vhdl [list [file join $root rtl provided Ps2Interface.vhd] [file join $root rtl provided Mouse_Control.vhd]]
read_xdc [list [file join $root constraints Basys3_StrikeLine.xdc]]
synth_design -top My_Top_Module -part xc7a35tcpg236-1 -flatten_hierarchy rebuilt \
    -include_dirs [list [file join $root rtl top] [file join $root rtl d_game_ui] [file join $root rtl c_pins]]
report_utilization -hierarchical -hierarchical_depth 1 -file hier_utilization.rpt
file copy -force hier_utilization.rpt $dest
puts "SYNTH_UTIL DONE"
