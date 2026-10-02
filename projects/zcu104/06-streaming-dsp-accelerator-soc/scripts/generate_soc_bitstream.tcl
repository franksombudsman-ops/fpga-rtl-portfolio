# ============================================================================
# Project 06 - Streaming DSP Accelerator SoC
# Final implementation bitstream + XSA export
#
# Author: Frank Ouma
# ============================================================================

set script_dir [file dirname [file normalize [info script]]]
set root       [file normalize [file join $script_dir ..]]

set project_file \
    "$root/build/vivado_soc/project06_soc.xpr"

set canonical_bit \
    "$root/build/project06_soc.bit"

set xsa_file \
    "$root/build/project06_soc.xsa"

puts ""
puts "============================================================"
puts " PROJECT06 BITSTREAM + XSA FINALIZATION"
puts "============================================================"

open_project $project_file

set impl_status [get_property STATUS [get_runs impl_1]]
puts "INITIAL IMPLEMENTATION STATUS: $impl_status"

if {![string match "*route_design Complete*" $impl_status] &&
    ![string match "*write_bitstream Complete*" $impl_status]} {
    error "Implementation has not completed route_design"
}

# ============================================================================
# Run the official implementation-run write_bitstream step.
#
# This is important because write_hw_platform -include_bit expects the
# bitstream to belong to impl_1, not merely exist as an independently written
# file.
# ============================================================================

puts ""
puts "=== IMPLEMENTATION RUN -> WRITE_BITSTREAM ==="

launch_runs impl_1 \
    -to_step write_bitstream \
    -jobs 12

wait_on_run impl_1

set final_status [get_property STATUS [get_runs impl_1]]

puts "FINAL IMPLEMENTATION STATUS: $final_status"

if {![string match "*write_bitstream Complete*" $final_status]} {
    error "impl_1 write_bitstream step did not complete successfully"
}

# ============================================================================
# Locate the run-owned bitstream and copy it to our canonical artifact path.
# ============================================================================

set run_dir [get_property DIRECTORY [get_runs impl_1]]
set bit_candidates [glob -nocomplain "$run_dir/*.bit"]

if {[llength $bit_candidates] == 0} {
    error "No implementation-run BIT file found in $run_dir"
}

set run_bit [lindex $bit_candidates 0]

file copy -force \
    $run_bit \
    $canonical_bit

puts ""
puts "BITSTREAM: PASS"
puts "RUN BIT  : $run_bit"
puts "BIT FILE : $canonical_bit"

# ============================================================================
# Export hardware platform including the run-owned bitstream.
# ============================================================================

write_hw_platform \
    -fixed \
    -include_bit \
    -force \
    -file $xsa_file

if {![file exists $xsa_file]} {
    error "XSA export did not produce $xsa_file"
}

puts ""
puts "HARDWARE PLATFORM EXPORT: PASS"
puts "XSA FILE : $xsa_file"

puts ""
puts "============================================================"
puts " PROJECT06 HARDWARE ARTIFACTS COMPLETE"
puts "============================================================"

close_project
exit
