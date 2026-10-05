# Project 07
# Package the minimal bring-up shell as a reusable AXI4-Lite IP.
#
# Required because Vivado Module Reference can infer the AXI bus
# pins but does not provide the explicit slave memory-map/address
# block required for deterministic PS address assignment.

set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file normalize "$script_dir/.."]
set rtl_dir    [file normalize "$proj_dir/rtl"]

set pkg_proj_dir [file normalize "$proj_dir/build/ip_packager"]
set ip_repo_root [file normalize "$proj_dir/build/ip_repo"]
set ip_root      [file normalize "$ip_repo_root/dma_bringup_shell_1_0"]

file mkdir "$proj_dir/build"

if {[file exists $pkg_proj_dir]} {
    file delete -force $pkg_proj_dir
}

if {[file exists $ip_root]} {
    file delete -force $ip_root
}

file mkdir $ip_repo_root

create_project -force \
    dma_bringup_ip_package \
    $pkg_proj_dir \
    -part xczu7ev-ffvc1156-2-e

add_files -norecurse [list \
    "$rtl_dir/dma_irq_controller.sv" \
    "$rtl_dir/dma_axil_regs.sv" \
    "$rtl_dir/dma_bringup_shell.sv" \
    "$rtl_dir/dma_bringup_shell_bd.v" \
]

set_property top \
    dma_bringup_shell_bd \
    [current_fileset]

update_compile_order -fileset sources_1

# ---------------------------------------------------------------
# Create IP-XACT package.
# ---------------------------------------------------------------

ipx::package_project \
    -root_dir $ip_root \
    -vendor coltium.com \
    -library user \
    -taxonomy /UserIP \
    -import_files \
    -set_current true

set core [ipx::current_core]

set_property name \
    dma_bringup_shell \
    $core

set_property display_name \
    {Project 07 DMA Bring-up Shell} \
    $core

set_property description \
    {Minimal Project 07 AXI4-Lite and interrupt physical bring-up peripheral} \
    $core

set_property version \
    1.0 \
    $core

# ---------------------------------------------------------------
# Verify inferred AXI slave interface.
# ---------------------------------------------------------------

set s_axi [
    ipx::get_bus_interfaces \
        S_AXI \
        -of_objects $core
]

if {$s_axi eq ""} {
    error "Packaging failed: S_AXI interface was not inferred"
}

# ---------------------------------------------------------------
# Explicit slave memory map.
#
# This creates the resource that becomes:
#
#   dma_bringup_shell_0/S_AXI/Reg
#
# inside the block design.
# ---------------------------------------------------------------

set mm [
    ipx::get_memory_maps \
        -quiet \
        S_AXI \
        -of_objects $core
]

if {$mm eq ""} {

    ipx::add_memory_map \
        S_AXI \
        $core

    set mm [
        ipx::get_memory_maps \
            S_AXI \
            -of_objects $core
    ]
}

set_property \
    slave_memory_map_ref \
    S_AXI \
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

# Explicit clock/reset relationship.
ipx::associate_bus_interfaces \
    -busif S_AXI \
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
puts " PROJECT 07 BRING-UP IP PACKAGED"
puts " VLNV: coltium.com:user:dma_bringup_shell:1.0"
puts " AXI slave: S_AXI"
puts " register range: 4096 bytes"
puts " repo: $ip_repo_root"
puts "======================================================="
puts ""

close_project
