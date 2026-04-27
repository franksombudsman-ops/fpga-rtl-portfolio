# =============================================================================
# build.tcl — Non-project-mode build script for debounced-led-controller
# Target : Xilinx Kria KR260 (xczu5eg-sfvc784-2-e)
# Toolchain: Vivado 2022.x
#
# Usage (from this directory):
#   vivado -mode batch -source build.tcl
# =============================================================================

# ── Configuration ─────────────────────────────────────────────────────────────
set top_module  top
set part        xczu5eg-sfvc784-2-e
set output_dir  ./output

# Resolve script location so the script works regardless of CWD
set script_dir  [file dirname [file normalize [info script]]]
set rtl_dir     [file normalize "$script_dir/../rtl"]
set con_dir     [file normalize "$script_dir/../constraints"]

# ── Source files ──────────────────────────────────────────────────────────────
set rtl_files [list \
    "$rtl_dir/debouncer.sv"      \
    "$rtl_dir/johnson_counter.sv" \
    "$rtl_dir/top.sv"            \
]

set xdc_files [list \
    "$con_dir/kr260_pmod1.xdc"   \
]

# ── Output directory ──────────────────────────────────────────────────────────
file mkdir $output_dir

# ── Synthesis ─────────────────────────────────────────────────────────────────
puts "=== Synthesising $top_module ==="
synth_design \
    -top      $top_module \
    -part     $part       \
    -mode     out_of_context \
    -verilog_define SYNTHESIS \
    -include_dirs $rtl_dir \
    -files    $rtl_files

# Apply constraints
read_xdc {*}$xdc_files

opt_design

# ── Implementation ─────────────────────────────────────────────────────────────
puts "=== Place & Route ==="
place_design
route_design

# ── Reports ───────────────────────────────────────────────────────────────────
puts "=== Writing reports ==="
report_timing_summary -file "$output_dir/timing_summary.rpt"
report_utilization    -file "$output_dir/utilization.rpt"
report_drc            -file "$output_dir/drc.rpt"

# ── Bitstream ──────────────────────────────────────────────────────────────────
# NOTE: The KR260 PL clock is sourced from the Zynq PS (pl_clk0).
# A full bitstream generation requires a Block Design with the Zynq MPSoC IP
# to provide the clock. The synthesis above is out-of-context for RTL
# verification only. Update this script with the BD wrapper when ready.
puts "=== Build complete. Check $output_dir/ for reports. ==="
