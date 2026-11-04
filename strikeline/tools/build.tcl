# build.tcl - StrikeLine batch build (synthesis -> implementation -> bitstream)
#   From strikeline/:   vivado -mode batch -source tools/build.tcl
# Vivado works in a local temp folder (OneDrive folders and paths with spaces
# upset it); the bitstream and reports are copied to build/:
#   strikeline.bit, utilization.rpt, post_synth_utilization.rpt, timing.rpt,
#   drc.rpt, failing_paths.txt (empty = timing met)
set root  [file normalize [file join [file dirname [info script]] ..]]
set dest  [file join $root build]
# a fresh work folder per run: a locked .Xil folder from an older run cannot block it
set work  [file normalize [file join $::env(TEMP) strikeline_build_[clock seconds]]]
set part  xc7a35tcpg236-1
file delete -force $work
file mkdir $dest
file mkdir $work
cd $work

# $readmemh looks for the .mem files next to the run, so copy them here
foreach f [glob [file join $root data *.mem]] { file copy -force $f $work }

set srcs {}
foreach dir {top provided a_gesture b_ball c_pins d_game_ui} {
    foreach f [glob -nocomplain [file join $root rtl $dir *.v]] { lappend srcs $f }
}
read_verilog $srcs
read_vhdl [list [file join $root rtl provided Ps2Interface.vhd] [file join $root rtl provided Mouse_Control.vhd]]
read_xdc [list [file join $root constraints Basys3_StrikeLine.xdc]]

synth_design -top My_Top_Module -part $part \
    -include_dirs [list [file join $root rtl top] [file join $root rtl d_game_ui]]
report_utilization -file post_synth_utilization.rpt
opt_design
place_design
phys_opt_design
route_design
report_utilization    -file utilization.rpt
report_timing_summary -file timing.rpt -max_paths 10
report_drc            -file drc.rpt
write_bitstream -force strikeline.bit

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set fh [open failing_paths.txt w]
foreach p [get_timing_paths -max_paths 5000 -nworst 1 -slack_lesser_than 0 -setup] {
    puts $fh "[get_property SLACK $p]  [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p]"
}
close $fh
foreach f {strikeline.bit utilization.rpt post_synth_utilization.rpt timing.rpt drc.rpt failing_paths.txt} {
    if {[file exists [file join $work $f]]} { file copy -force [file join $work $f] $dest }
}
puts "STRIKELINE BUILD DONE  WNS=$wns ns"
