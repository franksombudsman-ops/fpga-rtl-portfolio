# =============================================================================
# build.tcl — Non-project-mode build for spi-master-pmod-ad1
# Target : Xilinx Kria KR260 (xczu5eg-sfvc784-2-e)
# Toolchain: Vivado 2022.x
#
# Usage:
#   vivado -mode batch -source build.tcl
# =============================================================================

set top_module  top
set part        xczu5eg-sfvc784-2-e
set output_dir  ./output

set script_dir  [file dirname [file normalize [info script]]]
set rtl_dir     [file normalize "$script_dir/../rtl"]
set con_dir     [file normalize "$script_dir/../constraints"]

set rtl_files [list \
    "$rtl_dir/spi_master.sv"      \
    "$rtl_dir/pmod_ad1_ctrl.sv"   \
    "$rtl_dir/top.sv"             \
]

set xdc_files [list \
    "$con_dir/kr260_pmod2.xdc"    \
]

file mkdir $output_dir

puts "=== Synthesising $top_module ==="
synth_design \
    -top      $top_module \
    -part     $part       \
    -mode     out_of_context \
    -include_dirs $rtl_dir \
    -files    $rtl_files

read_xdc {*}$xdc_files
opt_design

puts "=== Place & Route ==="
place_design
route_design

puts "=== Writing reports ==="
report_timing_summary -file "$output_dir/timing_summary.rpt"
report_utilization    -file "$output_dir/utilization.rpt"
report_drc            -file "$output_dir/drc.rpt"
report_cdc            -file "$output_dir/cdc.rpt"

puts "=== Build complete. Reports in $output_dir/ ==="
