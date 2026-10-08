# Project 07
# Package Physical Gate-2 integration:
#
#   AXI-Lite CSR slave
#   full custom dma_core
#   AXI4-MM DDR master
#   interrupt output

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file normalize "$script_dir/.."]
set rtl_dir    [file normalize "$proj_dir/rtl"]

set pkg_proj_dir [file normalize "$proj_dir/build/ddr_gate_ip_packager"]
set ip_repo_root [file normalize "$proj_dir/build/ddr_gate_ip_repo"]
set ip_root      [file normalize "$ip_repo_root/dma_ddr_gate_top_1_0"]

if {[file exists $pkg_proj_dir]} {
    file delete -force $pkg_proj_dir
}

if {[file exists $ip_root]} {
    file delete -force $ip_root
}

file mkdir $ip_repo_root

create_project -force \
    dma_ddr_gate_ip_package \
    $pkg_proj_dir \
    -part xczu7ev-ffvc1156-2-e

add_files -norecurse [list \
    "$rtl_dir/dma_irq_controller.sv" \
    "$rtl_dir/dma_axil_regs.sv" \
    "$rtl_dir/dma_burst_planner.sv" \
    "$rtl_dir/dma_axi_read_master.sv" \
    "$rtl_dir/dma_axi_write_master.sv" \
    "$rtl_dir/dma_descriptor_parser.sv" \
    "$rtl_dir/dma_ring_manager.sv" \
    "$rtl_dir/dma_descriptor_engine.sv" \
    "$rtl_dir/dma_tx_engine.sv" \
    "$rtl_dir/dma_rx_engine.sv" \
    "$rtl_dir/dma_read_arbiter.sv" \
    "$rtl_dir/dma_write_arbiter.sv" \
    "$rtl_dir/dma_core.sv" \
    "$rtl_dir/dma_ddr_gate_top.sv" \
]

set_property top \
    dma_ddr_gate_top \
    [current_fileset]

update_compile_order -fileset sources_1

ipx::package_project \
    -root_dir $ip_root \
    -vendor coltium.com \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]

set_property name \
    dma_ddr_gate_top \
    $core

set_property display_name \
    {Project 07 Custom DMA DDR Gate} \
    $core

set_property description \
    {Project 07 full custom DMA integration for physical descriptor-fetch validation} \
    $core

set_property version 1.0 $core

# ---------------------------------------------------------------
# Verify inferred AXI interfaces
# ---------------------------------------------------------------

set s_axi [
    ipx::get_bus_interfaces \
        s_axi \
        -of_objects $core
]

if {$s_axi eq ""} {
    error "Packaging failed: s_axi interface not inferred"
}

set m_axi [
    ipx::get_bus_interfaces \
        m_axi \
        -of_objects $core
]

if {$m_axi eq ""} {
    error "Packaging failed: m_axi interface not inferred"
}

puts "FOUND s_axi: $s_axi"
puts "FOUND m_axi: $m_axi"

# ---------------------------------------------------------------
# Explicit CSR memory map
# ---------------------------------------------------------------

set mm [
    ipx::get_memory_maps \
        -quiet \
        s_axi \
        -of_objects $core
]

if {$mm eq ""} {

    ipx::add_memory_map \
        s_axi \
        $core

    set mm [
        ipx::get_memory_maps \
            s_axi \
            -of_objects $core
    ]
}

set_property \
    slave_memory_map_ref \
    s_axi \
    $s_axi

set reg_block [
    ipx::get_address_blocks \
        -quiet \
        Reg \
        -of_objects $mm
]

if {$reg_block eq ""} {

    ipx::add_address_block \
        Reg \
        $mm

    set reg_block [
        ipx::get_address_blocks \
            Reg \
            -of_objects $mm
    ]
}

set_property base_address 0 $reg_block
set_property range        4096 $reg_block
set_property width        32 $reg_block
set_property access       read-write $reg_block
set_property usage        register $reg_block

# ---------------------------------------------------------------
# Clock / reset association
# ---------------------------------------------------------------

ipx::associate_bus_interfaces \
    -busif s_axi \
    -clock aclk \
    $core

ipx::associate_bus_interfaces \
    -busif m_axi \
    -clock aclk \
    $core

ipx::associate_bus_interfaces \
    -clock aclk \
    -reset aresetn \
    $core

ipx::create_xgui_files $core
ipx::update_checksums $core
ipx::save_core $core

puts ""
puts "======================================================="
puts " PROJECT 07 DDR GATE IP PACKAGE: PASS"
puts " VLNV: coltium.com:user:dma_ddr_gate_top:1.0"
puts " s_axi: AXI4-Lite CSR slave"
puts " m_axi: custom AXI4-MM memory master"
puts " CSR range: 4096 bytes"
puts " repo: $ip_repo_root"
puts "======================================================="
puts ""

close_project
