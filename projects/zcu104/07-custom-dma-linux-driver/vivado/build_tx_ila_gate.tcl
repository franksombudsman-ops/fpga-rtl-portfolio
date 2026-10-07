# Project 07 - Physical Gate 2
#
# Full custom DMA + ZCU104 DDR integration.
#
# Control:
#   PS M_AXI_HPM0_FPD
#       -> AXI Interconnect
#       -> Project 07 S_AXI CSR
#
# Memory:
#   Project 07 M_AXI
#       -> AXI SmartConnect
#       -> PS S_AXI_HP0_FPD
#       -> DDR
#
# Interrupt:
#   Project 07 irq
#       -> PS pl_ps_irq0[0]
#       -> GIC SPI 121
#
# Gate-2 target:
# prove physical custom descriptor fetch from DDR.
#
# ZCU104 is NOT required during this build.

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file normalize "$script_dir/.."]

set build_dir  [file normalize "$proj_dir/build/tx_ila_gate"]
set ip_repo    [file normalize "$proj_dir/build/tx_ila_gate_ip_repo"]
set rpt_dir    [file normalize "$proj_dir/reports"]
set hw_dir     [file normalize "$proj_dir/hardware"]

file mkdir $build_dir
file mkdir $rpt_dir
file mkdir $hw_dir

create_project -force \
    dma_tx_ila_gate \
    $build_dir \
    -part xczu7ev-ffvc1156-2-e

set_property BOARD_PART \
    xilinx.com:zcu104:part0:1.1 \
    [current_project]

# ---------------------------------------------------------------
# Packaged Project-07 IP
# ---------------------------------------------------------------

set_property ip_repo_paths \
    [list $ip_repo] \
    [current_project]

update_ip_catalog -rebuild

set gate_vlnv \
    coltium.com:user:dma_ddr_gate_top:1.1

if {[get_ipdefs -all -quiet $gate_vlnv] eq ""} {
    error "Project 07 DDR Gate IP not found: $gate_vlnv"
}

puts "PROJECT07 DDR GATE IP FOUND: $gate_vlnv"

# ---------------------------------------------------------------
# Block design
# ---------------------------------------------------------------

create_bd_design system

# Zynq UltraScale+ MPSoC.
set ps [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 \
    zynq_ultra_ps_e_0]

apply_bd_automation \
    -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} \
    $ps

#
# Preserve the proven control-plane configuration and enable
# S_AXI_HP0_FPD using the same PS setting used by Project 05.
#
set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__USE__IRQ0 {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
] $ps

# ---------------------------------------------------------------
# Reset
# ---------------------------------------------------------------

set rst [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:proc_sys_reset:5.0 \
    proc_sys_reset_0]

set locked [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:xlconstant:1.1 \
    xlconstant_locked]

set_property -dict [list \
    CONFIG.CONST_WIDTH {1} \
    CONFIG.CONST_VAL   {1} \
] $locked

# ---------------------------------------------------------------
# PS -> PL AXI-Lite control path
# ---------------------------------------------------------------

set ctrl_ic [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:axi_interconnect:2.1 \
    ps8_0_axi_periph]

set_property CONFIG.NUM_MI {1} $ctrl_ic

# ---------------------------------------------------------------
# PL DMA master -> PS HP0 DDR path
# ---------------------------------------------------------------

set ddr_smc [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:smartconnect:1.0 \
    dma_ddr_smc]

set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {1} \
] $ddr_smc

# ---------------------------------------------------------------
# Project 07 Gate-2 authored IP
# ---------------------------------------------------------------

set gate [create_bd_cell \
    -type ip \
    -vlnv $gate_vlnv \
    dma_ddr_gate_top_0]


# ---------------------------------------------------------------
# Gate 3B TX AXI4-Stream ILA
# ---------------------------------------------------------------

if {[get_ipdefs -all -quiet xilinx.com:ip:ila:6.2] eq ""} {
    error "Vivado ILA 6.2 IP not available"
}

set tx_ila [create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:ila:6.2 \
    tx_axis_ila]

set_property -dict [list \
    CONFIG.C_ENABLE_ILA_AXI_MON {false} \
    CONFIG.C_MONITOR_TYPE       {Native} \
    CONFIG.C_NUM_OF_PROBES      {5} \
    CONFIG.C_DATA_DEPTH         {1024} \
    CONFIG.C_PROBE0_WIDTH       {64} \
    CONFIG.C_PROBE1_WIDTH       {8} \
    CONFIG.C_PROBE2_WIDTH       {1} \
    CONFIG.C_PROBE3_WIDTH       {1} \
    CONFIG.C_PROBE4_WIDTH       {1} \
] $tx_ila

# ---------------------------------------------------------------
# Verify required interfaces exist before connecting anything.
# ---------------------------------------------------------------

foreach intf {
    dma_ddr_gate_top_0/S_AXI
    dma_ddr_gate_top_0/M_AXI
    zynq_ultra_ps_e_0/M_AXI_HPM0_FPD
    zynq_ultra_ps_e_0/S_AXI_HP0_FPD
} {
    if {[get_bd_intf_pins -quiet $intf] eq ""} {
        error "Required interface missing: $intf"
    }

    puts "FOUND INTERFACE: $intf"
}

# ---------------------------------------------------------------
# AXI connectivity
# ---------------------------------------------------------------

# A53 -> Project 07 CSR.
connect_bd_intf_net \
    [get_bd_intf_pins zynq_ultra_ps_e_0/M_AXI_HPM0_FPD] \
    [get_bd_intf_pins ps8_0_axi_periph/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins ps8_0_axi_periph/M00_AXI] \
    [get_bd_intf_pins dma_ddr_gate_top_0/S_AXI]

# Project 07 custom master -> DDR HP0.
connect_bd_intf_net \
    [get_bd_intf_pins dma_ddr_gate_top_0/M_AXI] \
    [get_bd_intf_pins dma_ddr_smc/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins dma_ddr_smc/M00_AXI] \
    [get_bd_intf_pins zynq_ultra_ps_e_0/S_AXI_HP0_FPD]

# ---------------------------------------------------------------
# Clock
#
# Gate 2 intentionally uses one proven 100-MHz PL clock domain.
# Target 150-MHz DMA closure is deferred until physical DDR access
# has been demonstrated.
# ---------------------------------------------------------------

connect_bd_net \
    [get_bd_pins zynq_ultra_ps_e_0/pl_clk0] \
    [get_bd_pins zynq_ultra_ps_e_0/maxihpm0_fpd_aclk] \
    [get_bd_pins zynq_ultra_ps_e_0/saxihp0_fpd_aclk] \
    [get_bd_pins proc_sys_reset_0/slowest_sync_clk] \
    [get_bd_pins ps8_0_axi_periph/ACLK] \
    [get_bd_pins ps8_0_axi_periph/S00_ACLK] \
    [get_bd_pins ps8_0_axi_periph/M00_ACLK] \
    [get_bd_pins dma_ddr_smc/aclk] \
    [get_bd_pins dma_ddr_gate_top_0/aclk] \
    [get_bd_pins tx_axis_ila/clk]

# ---------------------------------------------------------------
# Reset
# ---------------------------------------------------------------

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
    [get_bd_pins dma_ddr_smc/aresetn] \
    [get_bd_pins dma_ddr_gate_top_0/aresetn]

# ---------------------------------------------------------------
# Interrupt
# ---------------------------------------------------------------

connect_bd_net \
    [get_bd_pins dma_ddr_gate_top_0/irq] \
    [get_bd_pins zynq_ultra_ps_e_0/pl_ps_irq0]


# ---------------------------------------------------------------
# Gate 3B TX stream observation
# ---------------------------------------------------------------

connect_bd_net \
    [get_bd_pins dma_ddr_gate_top_0/dbg_tx_data] \
    [get_bd_pins tx_axis_ila/probe0]

connect_bd_net \
    [get_bd_pins dma_ddr_gate_top_0/dbg_tx_keep] \
    [get_bd_pins tx_axis_ila/probe1]

connect_bd_net \
    [get_bd_pins dma_ddr_gate_top_0/dbg_tx_valid] \
    [get_bd_pins tx_axis_ila/probe2]

connect_bd_net \
    [get_bd_pins dma_ddr_gate_top_0/dbg_tx_ready] \
    [get_bd_pins tx_axis_ila/probe3]

connect_bd_net \
    [get_bd_pins dma_ddr_gate_top_0/dbg_tx_last] \
    [get_bd_pins tx_axis_ila/probe4]

# ---------------------------------------------------------------
# CPU-visible CSR aperture
# ---------------------------------------------------------------

set csr_seg [
    get_bd_addr_segs -quiet \
        dma_ddr_gate_top_0/S_AXI/reg0
]

if {$csr_seg eq ""} {
    error "Project 07 S_AXI/Reg segment missing"
}

puts "PROJECT07 CSR SEGMENT: $csr_seg"

assign_bd_address \
    -offset 0xA0000000 \
    -range 0x00001000 \
    -target_address_space \
        [get_bd_addr_spaces zynq_ultra_ps_e_0/Data] \
        $csr_seg \
    -force

# ---------------------------------------------------------------
# Custom DMA master DDR address map
# ---------------------------------------------------------------

set dma_space [
    get_bd_addr_spaces -quiet \
        dma_ddr_gate_top_0/M_AXI
]

if {$dma_space eq ""} {
    error "Project 07 M_AXI address space missing"
}

set ddr_seg [
    get_bd_addr_segs -quiet \
        zynq_ultra_ps_e_0/SAXIGP2/HP0_DDR_LOW
]

if {$ddr_seg eq ""} {
    error "PS HP0 DDR_LOW segment missing"
}

puts "PROJECT07 DMA ADDRESS SPACE: $dma_space"
puts "PROJECT07 HP0 DDR SEGMENT: $ddr_seg"

#
# ZCU104 low DDR aperture:
#   0x00000000 - 0x7FFFFFFF
#
assign_bd_address \
    -offset 0x00000000 \
    -range 0x80000000 \
    -target_address_space \
        $dma_space \
        $ddr_seg \
    -force

# ---------------------------------------------------------------
# Design validation
# ---------------------------------------------------------------

validate_bd_design
save_bd_design

puts ""
puts "======================================================="
puts " PROJECT 07 GATE-2 BLOCK DESIGN: VALID"
puts " CSR : 0xA0000000 / 4 KiB"
puts " DDR : 0x00000000 - 0x7FFFFFFF via HP0"
puts " CLK : 100 MHz"
puts " IRQ : pl_ps_irq0[0]"
puts "======================================================="
puts ""

# Preserve reconstructible block design.
write_bd_tcl \
    -force \
    "$script_dir/tx_ila_gate_system_bd.tcl"

# ---------------------------------------------------------------
# HDL wrapper
# ---------------------------------------------------------------

set wrapper_files [make_wrapper \
    -files [get_files system.bd] \
    -top]

add_files -norecurse $wrapper_files

set_property top \
    system_wrapper \
    [current_fileset]

update_compile_order -fileset sources_1

# ---------------------------------------------------------------
# Synthesis
# ---------------------------------------------------------------

launch_runs synth_1 -jobs 12
wait_on_run synth_1

set synth_status \
    [get_property STATUS [get_runs synth_1]]

puts "SYNTH STATUS: $synth_status"

if {$synth_status ne "synth_design Complete!"} {
    error "PROJECT 07 GATE-2 SYNTHESIS FAILED"
}

open_run synth_1

report_utilization \
    -file "$rpt_dir/tx_ila_gate_post_synth_utilization.rpt"

# ---------------------------------------------------------------
# Implementation and bitstream
# ---------------------------------------------------------------

launch_runs impl_1 \
    -to_step write_bitstream \
    -jobs 12

wait_on_run impl_1

set impl_status \
    [get_property STATUS [get_runs impl_1]]

puts "IMPL STATUS: $impl_status"

open_run impl_1

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 20 \
    -file "$rpt_dir/tx_ila_gate_timing_summary.rpt"

report_utilization \
    -file "$rpt_dir/tx_ila_gate_post_route_utilization.rpt"

report_bus_skew \
    -file "$rpt_dir/tx_ila_gate_bus_skew.rpt"

report_clock_interaction \
    -delay_type min_max \
    -file "$rpt_dir/tx_ila_gate_clock_interaction.rpt"

report_cdc \
    -details \
    -file "$rpt_dir/tx_ila_gate_cdc.rpt"

report_drc \
    -file "$rpt_dir/tx_ila_gate_drc.rpt"

# ---------------------------------------------------------------
# Gate 3B debug probes
# ---------------------------------------------------------------

write_debug_probes \
    -force \
    "$hw_dir/dma_tx_ila_gate.ltx"

# ---------------------------------------------------------------
# Export bitstream/XSA
# ---------------------------------------------------------------

set bitfile [file normalize \
    "$build_dir/dma_tx_ila_gate.runs/impl_1/system_wrapper.bit"]

if {![file exists $bitfile]} {
    error "Expected bitstream not found: $bitfile"
}

file copy -force \
    $bitfile \
    "$hw_dir/dma_tx_ila_gate.bit"

write_hw_platform \
    -fixed \
    -include_bit \
    -force \
    -file "$hw_dir/dma_tx_ila_gate.xsa"

puts ""
puts "======================================================="
puts " PROJECT 07 PHYSICAL GATE 3B TX ILA BUILD COMPLETE"
puts ""
puts " BIT: $hw_dir/dma_tx_ila_gate.bit"
puts " XSA: $hw_dir/dma_tx_ila_gate.xsa"
puts ""
puts " Hardware has NOT yet been physically validated."
puts "======================================================="
puts ""
