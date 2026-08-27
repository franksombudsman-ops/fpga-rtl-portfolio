set root [file normalize "projects/zcu104/03-axi-lite-control-peripheral"]

open_checkpoint \
    $root/build/axi_lite_control_peripheral_synth.dcp

opt_design

place_design

phys_opt_design

route_design

report_utilization \
    -file $root/reports/implementation_utilization.rpt

report_timing_summary \
    -delay_type min_max \
    -file $root/reports/implementation_timing_summary.rpt

report_timing \
    -delay_type min \
    -max_paths 20 \
    -sort_by group \
    -file $root/reports/implementation_hold_paths.rpt

write_checkpoint -force \
    $root/build/axi_lite_control_peripheral_routed.dcp

puts "=============================================="
puts " AXI-LITE PERIPHERAL IMPLEMENTATION COMPLETE"
puts "=============================================="

exit
