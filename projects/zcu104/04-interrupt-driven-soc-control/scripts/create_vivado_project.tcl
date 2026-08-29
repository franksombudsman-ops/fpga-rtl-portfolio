set script_dir [file dirname [file normalize [info script]]]
set proj_root  [file normalize [file join $script_dir ..]]

if {[info exists ::env(PROJECT04_VIVADO_DIR)] && $::env(PROJECT04_VIVADO_DIR) ne ""} {
    set vivado_dir [file normalize $::env(PROJECT04_VIVADO_DIR)]
} else {
    set vivado_dir [file normalize ~/amd-lab/vivado/zcu104/zcu104_interrupt_driven_soc_control]
}

create_project zcu104_interrupt_driven_soc_control \
    $vivado_dir \
    -part xczu7ev-ffvc1156-2-e \
    -force

set_property board_part xilinx.com:zcu104:part0:1.1 [current_project]

set rtl_files [list \
    [file join $proj_root rtl sample_rate_generator.sv] \
    [file join $proj_root rtl pmod_ad1_spi_master.sv] \
    [file join $proj_root rtl pmod_ad1_acquisition_engine.sv] \
    [file join $proj_root rtl adc_moving_average.sv] \
    [file join $proj_root rtl threshold_hysteresis.sv] \
    [file join $proj_root rtl actuator_control_fsm.sv] \
    [file join $proj_root rtl pwm_generator.sv] \
    [file join $proj_root rtl irq_controller.sv] \
    [file join $proj_root rtl soc_control_axi_peripheral.sv] \
    [file join $proj_root rtl soc_sensor_control_top.sv] \
    [file join $proj_root rtl soc_sensor_control_bd.v] \
]

add_files -norecurse $rtl_files
update_compile_order -fileset sources_1

# Add physical I/O constraints.
add_files -fileset constrs_1 -norecurse \
    [file join $proj_root constraints zcu104_soc_io.xdc]

# Recreate the verified Project 04 PS/PL block design.
source [file join $script_dir system_bd.tcl]

set bd_file [get_files -quiet */bd/system/system.bd]
if {[llength $bd_file] != 1} {
    error "Expected exactly one system.bd, found [llength $bd_file]"
}

# Generate the same top-level wrapper used by the verified implementation.
make_wrapper -files $bd_file -top

set wrapper_file [file join \
    $vivado_dir \
    zcu104_interrupt_driven_soc_control.gen \
    sources_1 \
    bd \
    system \
    hdl \
    system_wrapper.v]

if {![file exists $wrapper_file]} {
    error "system_wrapper.v was not generated"
}

add_files -norecurse $wrapper_file
set_property TOP system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1

puts ""
puts "=============================================="
puts " PROJECT 04 VIVADO PROJECT CREATED"
puts "=============================================="
puts "Board : ZCU104"
puts "Part  : xczu7ev-ffvc1156-2-e"
puts "BD    : system"
puts "=============================================="
puts ""
