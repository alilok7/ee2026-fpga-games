# create_project.tcl - make a normal Vivado GUI project that points at our sources
#   In Vivado: Tools -> Run Tcl Script... -> tools/create_project.tcl
#   (or: vivado -mode batch -source tools/create_project.tcl)
# The project is created in vivado/keylight.xpr. Sources are ADDED BY
# REFERENCE (not copied), so editing rtl/ in any editor updates the project.
# After editing songs/ or text/, run "python tools/make_data.py" first.
set root [file normalize [file join [file dirname [info script]] ..]]
set proj [file join $root vivado]

create_project keylight $proj -part xc7a35tcpg236-1 -force
set_property target_language Verilog [current_project]

set srcs {}
foreach dir {top provided a_sound b_input_freeplay_storage c_game d_ui_learn} {
    foreach f [glob -nocomplain [file join $root rtl $dir *.v]] { lappend srcs $f }
}
foreach f [glob -nocomplain [file join $root rtl top *.vh] [file join $root rtl d_ui_learn *.vh]] {
    lappend srcs $f
}
add_files -norecurse $srcs
add_files -norecurse [glob [file join $root data *.mem]]
set_property include_dirs [list [file join $root rtl top] [file join $root rtl d_ui_learn]] \
    [get_filesets sources_1]
set_property top My_Top_Module [get_filesets sources_1]

add_files -fileset constrs_1 -norecurse [list [file join $root constraints Basys3_Master.xdc]]

# testbenches (Flow -> Run Simulation picks the one marked as top)
set tbs [glob -nocomplain [file join $root sim * tb_*.v]]
add_files -fileset sim_1 -norecurse $tbs
add_files -fileset sim_1 -norecurse [glob [file join $root data *.mem]]
set_property include_dirs [list [file join $root rtl top] [file join $root rtl d_ui_learn]] \
    [get_filesets sim_1]
set_property top tb_game [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]
puts "KeyLight project created: [file join $proj keylight.xpr]"
