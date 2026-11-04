# build.tcl - KeyLight batch build (synthesis -> implementation -> bitstream)
#   From the project root:   vivado -mode batch -source tools/build.tcl
# Vivado works in a local temp folder (OneDrive folders and paths with
# spaces upset it), then the bitstream and reports are copied to build/:
#   keylight.bit, utilization.rpt, timing.rpt, drc.rpt, synth_warnings.txt
set root  [file normalize [file join [file dirname [info script]] ..]]
set dest  [file join $root build]
set work  [file normalize [file join $::env(TEMP) keylight_build]]
set part  xc7a35tcpg236-1
file mkdir $dest
file mkdir $work
cd $work

# $readmemh looks for the .mem files next to the run, so copy them here
foreach f [glob [file join $root data *.mem]] { file copy -force $f $work }

set srcs {}
foreach dir {top provided a_sound b_input_freeplay_storage c_game d_ui_learn} {
    foreach f [glob -nocomplain [file join $root rtl $dir *.v]] { lappend srcs $f }
}
read_verilog $srcs
read_xdc [list [file join $root constraints Basys3_Master.xdc]]   ;# list: the path has spaces

synth_design -top My_Top_Module -part $part \
    -include_dirs [list [file join $root rtl top] [file join $root rtl d_ui_learn]]
report_utilization -file post_synth_utilization.rpt
opt_design
place_design
phys_opt_design
route_design
report_utilization    -file utilization.rpt
report_timing_summary -file timing.rpt -max_paths 10
report_drc            -file drc.rpt
write_bitstream -force keylight.bit

set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
# every failing endpoint, worst first (empty file = timing met)
set fh [open failing_paths.txt w]
foreach p [get_timing_paths -max_paths 5000 -nworst 1 -slack_lesser_than 0 -setup] {
    puts $fh "[get_property SLACK $p]  [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p]"
}
close $fh
foreach f {keylight.bit utilization.rpt post_synth_utilization.rpt timing.rpt drc.rpt failing_paths.txt} {
    file copy -force [file join $work $f] $dest
}
puts "KEYLIGHT BUILD DONE  WNS=$wns ns"
