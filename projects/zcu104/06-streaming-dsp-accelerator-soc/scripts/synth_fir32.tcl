# ============================================================================
# Project 06 - Streaming DSP Accelerator SoC
# Standalone FIR32 synthesis / architecture inspection
#
# Author: Frank Ouma
# Platform: AMD ZCU104
# Part: xczu7ev-ffvc1156-2-e
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]

file mkdir $root/build
file mkdir $root/reports

read_verilog -sv \
    $root/rtl/fir32_axis.sv

read_xdc \
    $root/constraints/fir32_ooc.xdc

synth_design \
    -top fir32_axis \
    -part xczu7ev-ffvc1156-2-e \
    -mode out_of_context

# --------------------------------------------------------------------------
# Reports
# --------------------------------------------------------------------------

report_utilization \
    -file $root/reports/fir32_synthesis_utilization.rpt

report_utilization \
    -hierarchical \
    -file $root/reports/fir32_synthesis_utilization_hierarchical.rpt

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 20 \
    -file $root/reports/fir32_synthesis_timing_summary.rpt

report_methodology \
    -file $root/reports/fir32_synthesis_methodology.rpt

report_drc \
    -file $root/reports/fir32_synthesis_drc.rpt

# --------------------------------------------------------------------------
# Primitive architecture inventory
# --------------------------------------------------------------------------

# Count physical primitives only.
# Do not use REF_NAME =~ DSP* because that also matches the internal
# decomposed DSP_ALU/DSP_MULTIPLIER/etc. cell views of each DSP48E2.
set dsp_cells [get_cells -hierarchical -quiet -filter {REF_NAME == DSP48E2}]

set ramb18_cells [get_cells -hierarchical -quiet -filter {REF_NAME == RAMB18E2}]
set ramb36_cells [get_cells -hierarchical -quiet -filter {REF_NAME == RAMB36E2}]
set bram_cells [concat $ramb18_cells $ramb36_cells]

set fp [open $root/reports/fir32_architecture_inventory.rpt w]

puts $fp "PROJECT06 FIR32 SYNTHESIZED ARCHITECTURE"
puts $fp "========================================="
puts $fp "Part              : xczu7ev-ffvc1156-2-e"
puts $fp "Target clock      : 150 MHz / 6.667 ns"
puts $fp "DSP primitive count : [llength $dsp_cells]"
puts $fp "BRAM primitive count: [llength $bram_cells]"
puts $fp ""
puts $fp "DSP CELLS:"
foreach c $dsp_cells {
    puts $fp "  $c  REF=[get_property REF_NAME $c]"
}

close $fp

write_checkpoint -force \
    $root/build/fir32_synth.dcp

puts ""
puts "============================================================"
puts " PROJECT06 FIR32 SYNTHESIS COMPLETE"
puts "============================================================"
puts "Target : 150 MHz"
puts "DSPs   : [llength $dsp_cells]"
puts "BRAMs  : [llength $bram_cells]"
puts "Reports: $root/reports"
puts "============================================================"
puts ""

exit
