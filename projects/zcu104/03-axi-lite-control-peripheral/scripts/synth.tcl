set root [file normalize "projects/zcu104/03-axi-lite-control-peripheral"]

read_verilog -sv $root/rtl/axi_lite_control_peripheral.sv
read_xdc $root/constraints/axi_lite_control_peripheral.xdc

synth_design \
    -top axi_lite_control_peripheral \
    -part xczu7ev-ffvc1156-2-e

report_utilization \
    -file $root/reports/synthesis_utilization.rpt

report_timing_summary \
    -file $root/reports/synthesis_timing_summary.rpt

write_checkpoint -force \
    $root/build/axi_lite_control_peripheral_synth.dcp

puts "=============================================="
puts " AXI-LITE PERIPHERAL SYNTHESIS COMPLETE"
puts "=============================================="

exit
