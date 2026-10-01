# Project 06 - Complete streaming accelerator
# Standalone out-of-context target: 150 MHz

create_clock \
    -name accelerator_clk \
    -period 6.667 \
    [get_ports aclk]
