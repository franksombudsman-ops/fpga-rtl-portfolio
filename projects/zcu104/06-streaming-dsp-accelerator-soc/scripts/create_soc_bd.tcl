# ============================================================================
# Project 06 - Streaming DSP Accelerator SoC
# ZCU104 PS + Scatter-Gather DMA + Controlled Accelerator
#
# Author: Frank Ouma
#
# Vivado: 2023.2
# Board : ZCU104
# Part  : xczu7ev-ffvc1156-2-e
#
# Architecture:
#
#   Cortex-A53 / PS
#         |
#   M_AXI_HPM0_FPD
#         |
#   Control SmartConnect
#       |             |
#   AXI DMA       Accelerator
#   AXI-Lite      AXI-Lite
#
# DDR <- S_AXI_HP0_FPD <- Memory SmartConnect
#                           ^     ^     ^
#                           |     |     |
#                         MM2S   S2MM   SG
#
# DDR -> MM2S -> 16-bit AXIS -> accelerator
#      accelerator -> 64-bit AXIS -> S2MM -> DDR
#
# DMA interrupts -> pl_ps_irq0 -> GIC -> Cortex-A53
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]

set project_dir "$root/build/vivado_soc"
set project_name "project06_soc"
set bd_name "system"

file mkdir "$root/build"
file mkdir "$root/vivado"
file mkdir "$root/reports"

# Generated project only. Safe to rebuild.
if {[file exists $project_dir]} {
    file delete -force $project_dir
}

create_project \
    $project_name \
    $project_dir \
    -part xczu7ev-ffvc1156-2-e \
    -force

set_property board_part \
    xilinx.com:zcu104:part0:1.1 \
    [current_project]

set_property source_mgmt_mode All \
    [current_project]

update_ip_catalog

# ============================================================================
# Authored RTL
# ============================================================================

add_files -norecurse [list \
    "$root/rtl/accelerator_axil_regs.sv" \
    "$root/rtl/fir32_axis.sv" \
    "$root/rtl/moving_energy64_axis.sv" \
    "$root/rtl/dsp_accelerator_core.sv" \
    "$root/rtl/energy_event_axis_cfg.sv" \
    "$root/rtl/dsp_accelerator_controlled.sv" \
    "$root/rtl/dsp_accelerator_bd_wrapper.v" \
]

update_compile_order -fileset sources_1

# ============================================================================
# Block Design
# ============================================================================

create_bd_design $bd_name

# ----------------------------------------------------------------------------
# Zynq UltraScale+ Processing System
# ----------------------------------------------------------------------------

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:zynq_ultra_ps_e:3.5 \
    ps

apply_bd_automation \
    -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} \
    [get_bd_cells ps]

# PS master for PL control.
#
# PS slave HP0 is used for DMA access to DDR.
#
# PL0 = 150 MHz.
#
# IRQ0 enabled for DMA interrupts.

set_property -dict [list \
    CONFIG.PSU__USE__M_AXI_GP0 {1} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__S_AXI_GP2 {1} \
    CONFIG.PSU__USE__IRQ0 {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {150} \
] [get_bd_cells ps]

# ----------------------------------------------------------------------------
# Processor system reset
# ----------------------------------------------------------------------------

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:proc_sys_reset:5.0 \
    rst_150m

# Reset polarity is derived by proc_sys_reset; do not override read-only configuration.

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:xlconstant:1.1 \
    const_zero

set_property -dict [list \
    CONFIG.CONST_WIDTH {1} \
    CONFIG.CONST_VAL {0} \
] [get_bd_cells const_zero]

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:xlconstant:1.1 \
    const_one

set_property -dict [list \
    CONFIG.CONST_WIDTH {1} \
    CONFIG.CONST_VAL {1} \
] [get_bd_cells const_one]

# ----------------------------------------------------------------------------
# Scatter-Gather AXI DMA
# ----------------------------------------------------------------------------

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:axi_dma:7.1 \
    axi_dma_0

set_property -dict [list \
    CONFIG.c_include_sg {1} \
    CONFIG.c_include_mm2s {1} \
    CONFIG.c_include_s2mm {1} \
    CONFIG.c_include_mm2s_dre {0} \
    CONFIG.c_include_s2mm_dre {0} \
    CONFIG.c_m_axi_mm2s_data_width {64} \
    CONFIG.c_m_axi_s2mm_data_width {64} \
    CONFIG.c_m_axis_mm2s_tdata_width {16} \
    CONFIG.c_s_axis_s2mm_tdata_width {64} \
    CONFIG.c_sg_include_stscntrl_strm {0} \
    CONFIG.c_sg_length_width {23} \
] [get_bd_cells axi_dma_0]

# ----------------------------------------------------------------------------
# Controlled accelerator - verified authored RTL
# ----------------------------------------------------------------------------

create_bd_cell \
    -type module \
    -reference dsp_accelerator_bd_wrapper \
    accelerator_0

# ----------------------------------------------------------------------------
# AXI SmartConnect - PS control plane
#
# One PS master:
#   S00 = M_AXI_HPM0_FPD
#
# Two slaves:
#   M00 = AXI DMA control
#   M01 = accelerator control
# ----------------------------------------------------------------------------

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:smartconnect:1.0 \
    control_sc

set_property -dict [list \
    CONFIG.NUM_SI {1} \
    CONFIG.NUM_MI {2} \
] [get_bd_cells control_sc]

# ----------------------------------------------------------------------------
# AXI SmartConnect - DMA memory plane
#
# Three DMA masters:
#   S00 = MM2S memory read
#   S01 = S2MM memory write
#   S02 = SG descriptor access
#
# One PS DDR slave:
#   M00 = S_AXI_HP0_FPD
# ----------------------------------------------------------------------------

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:smartconnect:1.0 \
    memory_sc

set_property -dict [list \
    CONFIG.NUM_SI {3} \
    CONFIG.NUM_MI {1} \
] [get_bd_cells memory_sc]

# ----------------------------------------------------------------------------
# AXI4-Stream register slices
#
# These isolate READY paths around the accelerator and DMA.
# ----------------------------------------------------------------------------

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:axis_register_slice:1.1 \
    axis_in_rs

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:axis_register_slice:1.1 \
    axis_out_rs

# ----------------------------------------------------------------------------
# DMA IRQ aggregation
#
# pl_ps_irq0 is an 8-bit PS interrupt vector.
# In0 = MM2S interrupt
# In1 = S2MM interrupt
# In2..In7 = zero
# ----------------------------------------------------------------------------

create_bd_cell \
    -type ip \
    -vlnv xilinx.com:ip:xlconcat:2.1 \
    irq_concat

set_property -dict [list \
    CONFIG.NUM_PORTS {8} \
] [get_bd_cells irq_concat]

# ============================================================================
# CLOCKING
#
# Single PL clock domain for initial architecture:
#     ps/pl_clk0 = 150 MHz
# ============================================================================

connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins rst_150m/slowest_sync_clk]

# PS AXI clocks.
connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins ps/maxihpm0_fpd_aclk]

connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins ps/saxihp0_fpd_aclk]

# SmartConnect clocks.
connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins control_sc/aclk]

connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins memory_sc/aclk]

# DMA clocks.
connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins axi_dma_0/s_axi_lite_aclk]

connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins axi_dma_0/m_axi_sg_aclk]

connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins axi_dma_0/m_axi_mm2s_aclk]

connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins axi_dma_0/m_axi_s2mm_aclk]

# Stream slices.
connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins axis_in_rs/aclk]

connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins axis_out_rs/aclk]

# Accelerator.
connect_bd_net \
    [get_bd_pins ps/pl_clk0] \
    [get_bd_pins accelerator_0/aclk]

# ============================================================================
# RESET
# ============================================================================

connect_bd_net \
    [get_bd_pins ps/pl_resetn0] \
    [get_bd_pins rst_150m/ext_reset_in]

connect_bd_net \
    [get_bd_pins const_zero/dout] \
    [get_bd_pins rst_150m/aux_reset_in]

connect_bd_net \
    [get_bd_pins const_zero/dout] \
    [get_bd_pins rst_150m/mb_debug_sys_rst]

connect_bd_net \
    [get_bd_pins const_one/dout] \
    [get_bd_pins rst_150m/dcm_locked]

# AXI interconnect reset.
connect_bd_net \
    [get_bd_pins rst_150m/interconnect_aresetn] \
    [get_bd_pins control_sc/aresetn]

connect_bd_net \
    [get_bd_pins rst_150m/interconnect_aresetn] \
    [get_bd_pins memory_sc/aresetn]

# Peripheral reset.
connect_bd_net \
    [get_bd_pins rst_150m/peripheral_aresetn] \
    [get_bd_pins axi_dma_0/axi_resetn]

connect_bd_net \
    [get_bd_pins rst_150m/peripheral_aresetn] \
    [get_bd_pins accelerator_0/aresetn]

connect_bd_net \
    [get_bd_pins rst_150m/peripheral_aresetn] \
    [get_bd_pins axis_in_rs/aresetn]

connect_bd_net \
    [get_bd_pins rst_150m/peripheral_aresetn] \
    [get_bd_pins axis_out_rs/aresetn]

# ============================================================================
# CONTROL PLANE
# ============================================================================

connect_bd_intf_net \
    [get_bd_intf_pins ps/M_AXI_HPM0_FPD] \
    [get_bd_intf_pins control_sc/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins control_sc/M00_AXI] \
    [get_bd_intf_pins axi_dma_0/S_AXI_LITE]

connect_bd_intf_net \
    [get_bd_intf_pins control_sc/M01_AXI] \
    [get_bd_intf_pins accelerator_0/S_AXI]

# ============================================================================
# DMA MEMORY PLANE
# ============================================================================

connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXI_MM2S] \
    [get_bd_intf_pins memory_sc/S00_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXI_S2MM] \
    [get_bd_intf_pins memory_sc/S01_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXI_SG] \
    [get_bd_intf_pins memory_sc/S02_AXI]

connect_bd_intf_net \
    [get_bd_intf_pins memory_sc/M00_AXI] \
    [get_bd_intf_pins ps/S_AXI_HP0_FPD]

# ============================================================================
# STREAMING DATAPATH
#
# DDR
#   ->
# DMA MM2S
#   ->
# 16-bit AXIS
#   ->
# register slice
#   ->
# accelerator
#   ->
# 64-bit AXIS
#   ->
# register slice
#   ->
# DMA S2MM
#   ->
# DDR
# ============================================================================

connect_bd_intf_net \
    [get_bd_intf_pins axi_dma_0/M_AXIS_MM2S] \
    [get_bd_intf_pins axis_in_rs/S_AXIS]

connect_bd_intf_net \
    [get_bd_intf_pins axis_in_rs/M_AXIS] \
    [get_bd_intf_pins accelerator_0/S_AXIS]

connect_bd_intf_net \
    [get_bd_intf_pins accelerator_0/M_AXIS] \
    [get_bd_intf_pins axis_out_rs/S_AXIS]

connect_bd_intf_net \
    [get_bd_intf_pins axis_out_rs/M_AXIS] \
    [get_bd_intf_pins axi_dma_0/S_AXIS_S2MM]

# ============================================================================
# DMA INTERRUPTS
# ============================================================================

connect_bd_net \
    [get_bd_pins axi_dma_0/mm2s_introut] \
    [get_bd_pins irq_concat/In0]

connect_bd_net \
    [get_bd_pins axi_dma_0/s2mm_introut] \
    [get_bd_pins irq_concat/In1]

foreach n {2 3 4 5 6 7} {
    connect_bd_net \
        [get_bd_pins const_zero/dout] \
        [get_bd_pins irq_concat/In${n}]
}

connect_bd_net \
    [get_bd_pins irq_concat/dout] \
    [get_bd_pins ps/pl_ps_irq0]

# ============================================================================
# ADDRESS ASSIGNMENT
#
# First integration build uses Vivado address assignment.
# We will freeze the resulting software-visible map after validation.
# ============================================================================

assign_bd_address

# ============================================================================
# VALIDATION
# ============================================================================

regenerate_bd_layout
save_bd_design

puts ""
puts "============================================================"
puts " PROJECT06 BLOCK DESIGN VALIDATION"
puts "============================================================"

validate_bd_design

save_bd_design

puts ""
puts "BLOCK DESIGN VALIDATION: PASS"

# ============================================================================
# Capture address map
# ============================================================================

set addr_file \
    [open "$root/reports/soc_bd_address_map.txt" w]

puts $addr_file \
    "PROJECT06 SOC BLOCK DESIGN ADDRESS MAP"

puts $addr_file \
    "=================================="

foreach space [get_bd_addr_spaces] {

    puts $addr_file ""
    puts $addr_file "ADDRESS SPACE: $space"

    foreach seg [
        get_bd_addr_segs \
        -quiet \
        -of_objects $space
    ] {

        set offset ""
        set range  ""

        catch {
            set offset [get_property OFFSET $seg]
        }

        catch {
            set range [get_property RANGE $seg]
        }

        puts $addr_file \
            "  $seg  OFFSET=$offset  RANGE=$range"
    }
}

close $addr_file

# ============================================================================
# Reproducible BD Tcl
# ============================================================================

write_bd_tcl \
    -force \
    "$root/vivado/system_bd.tcl"

# ============================================================================
# Generate BD output products and HDL wrapper
# ============================================================================

set bd_file [
    get_files \
    "$project_dir/$project_name.srcs/sources_1/bd/$bd_name/$bd_name.bd"
]

generate_target all $bd_file

set wrapper_files [
    make_wrapper \
    -files $bd_file \
    -top
]

add_files -norecurse $wrapper_files

update_compile_order -fileset sources_1

save_bd_design

puts ""
puts "============================================================"
puts " PROJECT06 SOC BLOCK DESIGN CREATED"
puts "============================================================"
puts "Project:"
puts "  $project_dir/$project_name.xpr"
puts ""
puts "Reproducible BD Tcl:"
puts "  $root/vivado/system_bd.tcl"
puts ""
puts "Address map:"
puts "  $root/reports/soc_bd_address_map.txt"
puts ""
puts "PL clock:"
puts "  [get_property CONFIG.PSU__CRL_APB__PL0_REF_CTRL__ACT_FREQMHZ [get_bd_cells ps]] MHz"
puts ""
puts "Architecture:"
puts "  DDR -> SG DMA MM2S -> Accelerator -> SG DMA S2MM -> DDR"
puts "============================================================"

close_project
exit
