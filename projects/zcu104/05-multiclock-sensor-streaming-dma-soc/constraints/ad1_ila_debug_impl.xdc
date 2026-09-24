# AD1 direct serial-input observation paths.
# Exclude ILA endpoints only; preserve functional ADC capture timing.

set ad1_debug_eps [filter \
    [all_fanout -flat -endpoints_only \
        -from [get_ports {ad1_sdata_a ad1_sdata_b}]] \
    {NAME =~ *ila_ad1_0*}]

set_false_path \
    -from [get_ports {ad1_sdata_a ad1_sdata_b}] \
    -to $ad1_debug_eps
