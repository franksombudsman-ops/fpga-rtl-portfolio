set script_dir [file dirname [file normalize [info script]]]
set proj_dir   [file normalize "$script_dir/.."]
set build_dir  [file normalize "$proj_dir/build/bringup"]
set hw_dir     [file normalize "$proj_dir/hardware"]

file mkdir $hw_dir

open_project \
    "$build_dir/dma_bringup.xpr"

open_run impl_1

set bitfile [file normalize \
    "$build_dir/dma_bringup.runs/impl_1/system_wrapper.bit"]

if {![file exists $bitfile]} {
    error "Bitstream not found: $bitfile"
}

file copy -force \
    $bitfile \
    "$hw_dir/dma_bringup.bit"

write_hw_platform \
    -fixed \
    -include_bit \
    -force \
    -file "$hw_dir/dma_bringup.xsa"

puts ""
puts "======================================================="
puts " PROJECT 07 BRING-UP ARTIFACT EXPORT: PASS"
puts " BIT: $hw_dir/dma_bringup.bit"
puts " XSA: $hw_dir/dma_bringup.xsa"
puts "======================================================="
puts ""

close_project
