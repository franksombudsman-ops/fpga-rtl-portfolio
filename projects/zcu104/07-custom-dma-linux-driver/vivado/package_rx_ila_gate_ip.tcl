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

set pkg_proj_dir [file normalize "$proj_dir/build/rx_ila_gate_ip_packager"]
set ip_repo_root [file normalize "$proj_dir/build/rx_ila_gate_ip_repo"]
set ip_root      [file normalize "$ip_repo_root/dma_ddr_gate_top_1_2"]

if {[file exists $pkg_proj_dir]} {
    file delete -force $pkg_proj_dir
}

if {[file exists $ip_root]} {
    file delete -force $ip_root
}

file mkdir $ip_repo_root

create_project -force \
    dma_rx_ila_gate_ip_package \
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
    {Project 07 Custom DMA RX ILA Gate} \
    $core

set_property description \
    {Project 07 custom DMA integration with observation-only RX AXI4-Stream probes for physical ILA validation} \
    $core

set_property version 1.2 $core

# ---------------------------------------------------------------
# Verify inferred AXI interfaces
#
# Vivado may normalize inferred interface names to lowercase.
# Discover the actual objects rather than relying on case.
# ---------------------------------------------------------------

set s_axi ""
set m_axi ""

foreach bi [ipx::get_bus_interfaces -quiet -of_objects $core] {

    set bi_name [get_property NAME $bi]

    if {[string equal -nocase $bi_name "s_axi"]} {
        set s_axi $bi
    }

    if {[string equal -nocase $bi_name "m_axi"]} {
        set m_axi $bi
    }
}

if {$s_axi eq ""} {
    error "Packaging failed: S_AXI interface not inferred"
}

if {$m_axi eq ""} {
    error "Packaging failed: M_AXI interface not inferred"
}

set s_axi_name [get_property NAME $s_axi]
set m_axi_name [get_property NAME $m_axi]

puts "FOUND S_AXI: $s_axi_name"
puts "FOUND M_AXI: $m_axi_name"

#
# Gate-4B debug wires must NOT be inferred as an AXI4-Stream
# protocol interface. They are observation-only scalar/vector ports.
#
set dbg_axis [
    ipx::get_bus_interfaces \
        -quiet \
        dbg_rx \
        -of_objects $core
]

if {$dbg_axis ne ""} {
    error "Packaging failed: debug probes unexpectedly inferred as AXI4-Stream"
}

puts "DEBUG PROBES: discrete observation ports"

# ---------------------------------------------------------------
# Explicit CSR memory map
# ---------------------------------------------------------------

set mm ""

foreach candidate [ipx::get_memory_maps -quiet -of_objects $core] {

    set candidate_name [get_property NAME $candidate]

    if {[string equal -nocase $candidate_name $s_axi_name]} {
        set mm $candidate
        break
    }
}

if {$mm eq ""} {

    ipx::add_memory_map \
        $s_axi_name \
        $core

    set mm [
        ipx::get_memory_maps \
            $s_axi_name \
            -of_objects $core
    ]
}

set mm_name [get_property NAME $mm]

set_property \
    slave_memory_map_ref \
    $mm_name \
    $s_axi

#
# Vivado may automatically create reg0 for an inferred AXI slave.
# Reuse the existing single block instead of depending on its name.
#
set blocks [
    ipx::get_address_blocks \
        -quiet \
        -of_objects $mm
]

if {[llength $blocks] == 0} {

    ipx::add_address_block \
        Reg \
        $mm

    set blocks [
        ipx::get_address_blocks \
            -quiet \
            -of_objects $mm
    ]
}

if {[llength $blocks] != 1} {
    error "Packaging failed: expected exactly one CSR address block"
}

set reg_block [lindex $blocks 0]

set_property base_address 0          $reg_block
set_property range        4096       $reg_block
set_property width        32         $reg_block
set_property access       read-write $reg_block
set_property usage        register   $reg_block

puts "CSR MEMORY MAP: $mm_name"
puts "CSR ADDRESS BLOCK: [get_property NAME $reg_block]"

# ---------------------------------------------------------------
# Clock / reset association
# ---------------------------------------------------------------

ipx::associate_bus_interfaces \
    -busif $s_axi_name \
    -clock aclk \
    $core

ipx::associate_bus_interfaces \
    -busif $m_axi_name \
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
puts " VLNV: coltium.com:user:dma_ddr_gate_top:1.2"
puts " S_AXI: AXI4-Lite CSR slave"
puts " M_AXI: custom AXI4-MM memory master"
puts " CSR range: 4096 bytes"
puts " repo: $ip_repo_root"
puts "======================================================="
puts ""

close_project
