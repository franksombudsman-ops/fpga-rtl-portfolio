# Project 06 - Software-controlled streaming DSP accelerator
# Out-of-context synthesis target: 150 MHz

create_clock \
    -name accelerator_clk \
    -period 6.667 \
    [get_ports aclk]
