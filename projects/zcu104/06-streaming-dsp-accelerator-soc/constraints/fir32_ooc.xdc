# Project 06 - FIR32 standalone synthesis constraint
# 150 MHz accelerator target

create_clock \
    -name accelerator_clk \
    -period 6.667 \
    [get_ports aclk]
