# create_project.tcl - a normal Vivado GUI project that points at the StrikeLine sources
#   In Vivado: Tools -> Run Tcl Script... -> strikeline/tools/create_project.tcl
# Created in strikeline/vivado/strikeline.xpr. Sources are added BY REFERENCE,
# so editing rtl/ in any editor updates the project.
# After editing text/ or the generators, run "python tools/make_data.py" first.
set root [file normalize [file join [file dirname [info script]] ..]]
set proj [file join $root vivado]
create_project strikeline $proj -part xc7a35tcpg236-1 -force
set_property target_language Verilog [current_project]

set srcs {}
foreach dir {top provided a_gesture b_ball c_pins d_game_ui} {
    foreach f [glob -nocomplain [file join $root rtl $dir *.v] [file join $root rtl $dir *.vh] [file join $root rtl $dir *.vhd]] {
        lappend srcs $f
    }
}
add_files -norecurse $srcs
add_files -norecurse [glob [file join $root data *.mem]]
set_property include_dirs [list [file join $root rtl top] [file join $root rtl d_game_ui] [file join $root rtl c_pins]] [get_filesets sources_1]
set_property top My_Top_Module [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [list [file join $root constraints Basys3_StrikeLine.xdc]]

set tbs [glob -nocomplain [file join $root sim * *.v]]
add_files -fileset sim_1 -norecurse $tbs
add_files -fileset sim_1 -norecurse [glob [file join $root data *.mem]]
set_property include_dirs [list [file join $root rtl top] [file join $root rtl d_game_ui] [file join $root rtl c_pins]] [get_filesets sim_1]
set_property verilog_define {SIM} [get_filesets sim_1]
set_property top tb_physics [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]
puts "StrikeLine project created: [file join $proj strikeline.xpr]"
