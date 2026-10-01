# ============================================================================
# Project 06 - Streaming DSP Accelerator SoC
# Full compute accelerator synthesis
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
    $root/rtl/fir32_axis.sv \
    $root/rtl/moving_energy64_axis.sv \
    $root/rtl/dsp_accelerator_core.sv \
    $root/rtl/energy_event_axis.sv \
    $root/rtl/dsp_accelerator_full.sv

read_xdc \
    $root/constraints/full_accelerator_ooc.xdc

synth_design \
    -top dsp_accelerator_full \
    -part xczu7ev-ffvc1156-2-e \
    -mode out_of_context

# --------------------------------------------------------------------------
# Standard reports
# --------------------------------------------------------------------------

report_utilization \
    -file $root/reports/full_accelerator_synthesis_utilization.rpt

report_utilization \
    -hierarchical \
    -file $root/reports/full_accelerator_synthesis_utilization_hierarchical.rpt

report_timing_summary \
    -delay_type min_max \
    -report_unconstrained \
    -check_timing_verbose \
    -max_paths 30 \
    -file $root/reports/full_accelerator_synthesis_timing_summary.rpt

report_methodology \
    -file $root/reports/full_accelerator_synthesis_methodology.rpt

report_drc \
    -file $root/reports/full_accelerator_synthesis_drc.rpt

# --------------------------------------------------------------------------
# Physical primitive inventory
# --------------------------------------------------------------------------

set dsp_cells \
    [get_cells -hierarchical -quiet -filter {REF_NAME == DSP48E2}]

set ramb18_cells \
    [get_cells -hierarchical -quiet -filter {REF_NAME == RAMB18E2}]

set ramb36_cells \
    [get_cells -hierarchical -quiet -filter {REF_NAME == RAMB36E2}]

set uram_cells \
    [get_cells -hierarchical -quiet -filter {REF_NAME == URAM288}]

set fp \
    [open $root/reports/full_accelerator_architecture_inventory.rpt w]

puts $fp "PROJECT06 FULL ACCELERATOR SYNTHESIZED ARCHITECTURE"
puts $fp "===================================================="
puts $fp "Part       : xczu7ev-ffvc1156-2-e"
puts $fp "Target     : 150 MHz / 6.667 ns"
puts $fp ""
puts $fp "DSP48E2    : [llength $dsp_cells]"
puts $fp "RAMB18E2   : [llength $ramb18_cells]"
puts $fp "RAMB36E2   : [llength $ramb36_cells]"
puts $fp "URAM288    : [llength $uram_cells]"
puts $fp ""
puts $fp "DSP CELLS:"

foreach c $dsp_cells {
    puts $fp "  $c"
}

close $fp

write_checkpoint -force \
    $root/build/full_accelerator_synth.dcp

puts ""
puts "============================================================"
puts " PROJECT06 FULL ACCELERATOR SYNTHESIS COMPLETE"
puts "============================================================"
puts "DSP48E2  : [llength $dsp_cells]"
puts "RAMB18E2 : [llength $ramb18_cells]"
puts "RAMB36E2 : [llength $ramb36_cells]"
puts "URAM288  : [llength $uram_cells]"
puts "============================================================"

exit
