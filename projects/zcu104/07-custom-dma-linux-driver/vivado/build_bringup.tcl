# Project 07
# Minimal ZCU104 physical bring-up design
#
# PS M_AXI_HPM0_FPD -> AXI Interconnect -> dma_bringup_shell
# dma_bringup_shell IRQ -> PS pl_ps_irq0
#
# No custom DMA DDR master is connected in this design.

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file normalize "$script_dir/.."]
set build_dir  [file normalize "$proj_dir/build/bringup"]
set rtl_dir    [file normalize "$proj_dir/rtl"]
set rpt_dir    [file normalize "$proj_dir/reports"]
set hw_dir     [file normalize "$proj_dir/hardware"]

file mkdir $build_dir
file mkdir $rpt_dir
file mkdir $hw_dir

create_project -force \
    dma_bringup \
    $build_dir \
    -part xczu7ev-ffvc1156-2-e

set_property BOARD_PART \
    xilinx.com:zcu104:part0:1.1 \
    [current_project]

# ----------------------------------------------------------------
# Authored RTL
# ----------------------------------------------------------------

# Packaged Project-07 bring-up peripheral.
set ip_repo [file normalize "$proj_dir/build/ip_repo"]

set_property ip_repo_paths \
    [list $ip_repo] \
    [current_project]

update_ip_catalog -rebuild

if {[get_ipdefs -all -quiet coltium.com:user:dma_bringup_shell:1.0] eq ""} {
    error "Project 07 bring-up packaged IP not found"
}

# ----------------------------------------------------------------
# Block design
# ----------------------------------------------------------------

create_bd_design system

# Zynq UltraScale+ MPSoC
set ps [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 \
    zynq_ultra_ps_e_0]

# Apply ZCU104 board preset.
apply_bd_automation \
    -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} \
    $ps

# Preserve the known-good P05 control-plane choices.
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__IRQ0 {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] $ps

# Processor-system reset.
set rst [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:proc_sys_reset:5.0 \
    proc_sys_reset_0]

# Reset controller requires DCM locked = 1 for this PS-generated clock.
set locked [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:xlconstant:1.1 \
    xlconstant_locked]

set_property -dict [list \
    CONFIG.CONST_WIDTH {1} \
    CONFIG.CONST_VAL   {1} \
] $locked

# AXI control interconnect.
set ic [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:axi_interconnect:2.1 \
    ps8_0_axi_periph]

set_property CONFIG.NUM_MI {1} $ic

# Authored bring-up RTL.
set shell [create_bd_cell \
    -type ip \
    -vlnv coltium.com:user:dma_bringup_shell:1.0 \
    dma_bringup_shell_0]

# ----------------------------------------------------------------
# AXI connectivity
# ----------------------------------------------------------------

connect_bd_intf_net \
    [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
    [get_bd_intf_pins ps8_0_axi_periph/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins ps8_0_axi_periph/M00_AXI] \
    [get_bd_intf_pins dma_bringup_shell_0/S_AXI]

# ----------------------------------------------------------------
# Clock
# ----------------------------------------------------------------

connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk] \
    [get_bd_pins ps8_0_axi_periph/ACLK] \
    [get_bd_pins ps8_0_axi_periph/S00_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M00_ACLK] \
    [get_bd_pins dma_bringup_shell_0/aclk]

# ----------------------------------------------------------------
# Reset
# ----------------------------------------------------------------

connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_resetn0] \
    [get_bd_pins proc_sys_reset_0/ext_reset_in]

connect_bd_net \
    [get_bd_pins xlconstant_locked/dout] \
    [get_bd_pins proc_sys_reset_0/dcm_locked]

connect_bd_net \
    [get_bd_pins proc_sys_reset_0/peripheral_aresetn] \
    [get_bd_pins ps8_0_axi_periph/ARESETN] \
    [get_bd_pins ps8_0_axi_periph/S00_ARESETN] \
    [get_bd_pins ps8_0_axi_periph/M00_ARESETN] \
    [get_bd_pins dma_bringup_shell_0/aresetn]

# ----------------------------------------------------------------
# PL -> PS interrupt
# ----------------------------------------------------------------

connect_bd_net \
    [get_bd_pins dma_bringup_shell_0/irq] \
    [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]

# ----------------------------------------------------------------
# CPU-visible address
#
# Same control base previously proven in Project 05.
# Only 4 KiB is required by our CSR register contract.
# ----------------------------------------------------------------

set csr_segment [
    get_bd_addr_segs -quiet \
        dma_bringup_shell_0/S_AXI/Reg
]

if {$csr_segment eq ""} {
    error "Bring-up IP S_AXI/Reg address segment was not created"
}

puts "PROJECT07 CSR SLAVE SEGMENT: $csr_segment"

assign_bd_address \
    -offset 0xA0000000 \
    -range 0x00001000 \
    -target_address_space \
        [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
        [get_bd_addr_segs dma_bringup_shell_0/S_AXI/Reg] \
    -force

# ----------------------------------------------------------------
# Validate and preserve reproducible BD
# ----------------------------------------------------------------

validate_bd_design
save_bd_design

write_bd_tcl \
    -force \
    "$script_dir/bringup_system_bd.tcl"

# Generate HDL wrapper.
set wrapper_files [make_wrapper \
    -files [get_files system.bd] \
    -top]

add_files -norecurse $wrapper_files

set_property top system_wrapper [current_fileset]

update_compile_order -fileset sources_1

# ----------------------------------------------------------------
# Synthesis
# ----------------------------------------------------------------

launch_runs synth_1 -jobs 12
wait_on_run synth_1

if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "SYNTHESIS FAILED"
}

open_run synth_1

report_utilization \
    -file "$rpt_dir/bringup_post_synth_utilization.rpt"

# ----------------------------------------------------------------
# Implementation + bitstream
# ----------------------------------------------------------------

launch_runs impl_1 \
    -to_step write_bitstream \
    -jobs 12

wait_on_run impl_1

open_run impl_1

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 20 \
    -file "$rpt_dir/bringup_timing_summary.rpt"

report_utilization \
    -file "$rpt_dir/bringup_post_route_utilization.rpt"

report_drc \
    -file "$rpt_dir/bringup_drc.rpt"

# ----------------------------------------------------------------
# Export hardware
# ----------------------------------------------------------------

set bitfile [file normalize \
    "$build_dir/dma_bringup.runs/impl_1/system_wrapper.bit"]

if {![file exists $bitfile]} {
    error "Expected bitstream not found: $bitfile"
}

puts "PROJECT07 BITSTREAM SOURCE: $bitfile"

file copy -force \
    $bitfile \
    "$hw_dir/dma_bringup.bit"

write_hw_platform \
    -fixed \
    -include_bit \
    -force \
    -file "$hw_dir/dma_bringup.xsa"

puts ""
puts "======================================================="
puts " PROJECT 07 MINIMAL BRING-UP BUILD COMPLETE"
puts " BIT: $hw_dir/dma_bringup.bit"
puts " XSA: $hw_dir/dma_bringup.xsa"
puts " CSR: 0xA0000000"
puts "======================================================="
puts ""
