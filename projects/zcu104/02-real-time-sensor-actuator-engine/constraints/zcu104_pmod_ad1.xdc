# ============================================================
# ZCU104 Project 02
# Real-Time Pmod AD1 Acquisition Engine
# ============================================================


# ------------------------------------------------------------
# 300 MHz differential PL clock
# ------------------------------------------------------------

set_property PACKAGE_PIN AH18 [get_ports clk_300_p]
set_property PACKAGE_PIN AH17 [get_ports clk_300_n]
set_property IOSTANDARD DIFF_SSTL12 [get_ports clk_300_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports clk_300_n]


# ------------------------------------------------------------
# Reset pushbutton - SW15
# ------------------------------------------------------------

set_property PACKAGE_PIN C4 [get_ports pb_reset]
set_property IOSTANDARD LVCMOS33 [get_ports pb_reset]


# ------------------------------------------------------------
# PMOD0 / J55
#
# Pmod AD1:
#   Pin 1 = CS
#   Pin 2 = D0 / ADC A
#   Pin 3 = D1 / ADC B
#   Pin 4 = SCLK
# ------------------------------------------------------------

# J55.1 / PMOD0_0
set_property PACKAGE_PIN G8 [get_ports ad1_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports ad1_cs_n]

# J55.3 / PMOD0_1
set_property PACKAGE_PIN H8 [get_ports ad1_sdata_a]
set_property IOSTANDARD LVCMOS33 [get_ports ad1_sdata_a]

# J55.5 / PMOD0_2
set_property PACKAGE_PIN G7 [get_ports ad1_sdata_b]
set_property IOSTANDARD LVCMOS33 [get_ports ad1_sdata_b]

# J55.7 / PMOD0_3
set_property PACKAGE_PIN H7 [get_ports ad1_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports ad1_sclk]


# ------------------------------------------------------------
# Status LEDs
# ------------------------------------------------------------

# DS40
set_property PACKAGE_PIN B5 [get_ports led_clock_locked]
set_property IOSTANDARD LVCMOS33 [get_ports led_clock_locked]

# DS39
set_property PACKAGE_PIN A5 [get_ports led_overrun]
set_property IOSTANDARD LVCMOS33 [get_ports led_overrun]

# DS38
set_property PACKAGE_PIN D5 [get_ports led_sample_a_msb]
set_property IOSTANDARD LVCMOS33 [get_ports led_sample_a_msb]

# DS37
set_property PACKAGE_PIN D6 [get_ports led_sample_b_msb]
set_property IOSTANDARD LVCMOS33 [get_ports led_sample_b_msb]


# ------------------------------------------------------------
# Asynchronous user reset request
# ------------------------------------------------------------

set_false_path -from [get_ports pb_reset]


# LEDs are observational outputs only.
set_false_path -to [get_ports {led_clock_locked led_overrun led_sample_a_msb led_sample_b_msb}]


# ============================================================
# PMOD AD1 / AD7476A EXTERNAL INTERFACE TIMING
# ============================================================
#
# FPGA fabric clock : 125 MHz
# AD1 SCLK           : 2.5 MHz
# Clock ratio        : 50
#
# AD7476A:
#   SDATA changes after SCLK falling edge.
#   tCO(min) ~= 10 ns at 3.3 V
#   tCO(max)  = 40 ns
#
# The direct PMOD connection is assigned a conservative
# 0..2 ns trace/connector timing budget per direction.
# These trace values are engineering assumptions, not measured
# ZCU104/AD1 PCB flight-time values.
# ============================================================


# ------------------------------------------------------------
# External interface timing parameters
# ------------------------------------------------------------







# ------------------------------------------------------------
# Model the external 2.5 MHz SPI clock.
#
# 125 MHz / 50 = 2.5 MHz
# ------------------------------------------------------------

create_generated_clock -name ad1_sclk_clk -source [get_pins clk_wiz/inst/clkout1_buf/O] -divide_by 50 [get_ports ad1_sclk]


# ------------------------------------------------------------
# ADC DATA RETURN TIMING
#
# AD7476A launches new SDATA after the falling edge of SCLK.
# ------------------------------------------------------------

set_input_delay -clock [get_clocks ad1_sclk_clk] -clock_fall -max 44.000 [get_ports {ad1_sdata_a ad1_sdata_b}]

set_input_delay -clock [get_clocks ad1_sclk_clk] -clock_fall -min 10.000 [get_ports {ad1_sdata_a ad1_sdata_b}]


# ------------------------------------------------------------
# Our RTL captures the returned ADC bit 25 x 125 MHz cycles
# after the corresponding falling SCLK event:
#
# 25 x 8 ns = 200 ns
# ------------------------------------------------------------

set_multicycle_path -setup -from [get_clocks ad1_sclk_clk] -to [get_clocks -of_objects [get_pins clk_wiz/inst/mmcme4_adv_inst/CLKOUT0]] 25

set_multicycle_path -hold -end -from [get_clocks ad1_sclk_clk] -to [get_clocks -of_objects [get_pins clk_wiz/inst/mmcme4_adv_inst/CLKOUT0]] 24


# ------------------------------------------------------------
# CHIP-SELECT TIMING
#
# AD7476A requires at least 10 ns CS-to-SCLK setup.
# ------------------------------------------------------------

set_output_delay -clock [get_clocks ad1_sclk_clk] -max 12.000 [get_ports ad1_cs_n]

set_output_delay -clock [get_clocks ad1_sclk_clk] -min -2.000 [get_ports ad1_cs_n]


# CS is generated from the 125 MHz domain but relates to the
# much slower SPI timing window.

set_multicycle_path -setup -start -from [get_clocks -of_objects [get_pins clk_wiz/inst/mmcme4_adv_inst/CLKOUT0]] -to [get_clocks ad1_sclk_clk] 25

set_multicycle_path -hold -from [get_clocks -of_objects [get_pins clk_wiz/inst/mmcme4_adv_inst/CLKOUT0]] -to [get_clocks ad1_sclk_clk] 24



# ============================================================

set_property MARK_DEBUG true [get_nets acquisition_engine/spi_master/sdata_a]
set_property MARK_DEBUG true [get_nets acquisition_engine/spi_master/sdata_b]
set_property MARK_DEBUG true [get_nets -of_objects [get_pins acquisition_engine/spi_master/cs_n_reg/Q]]
set_property MARK_DEBUG true [get_nets -of_objects [get_pins acquisition_engine/spi_master/sclk_reg/Q]]
create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_wiz/inst/clk_out1]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 12 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {sample_a[0]} {sample_a[1]} {sample_a[2]} {sample_a[3]} {sample_a[4]} {sample_a[5]} {sample_a[6]} {sample_a[7]} {sample_a[8]} {sample_a[9]} {sample_a[10]} {sample_a[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 12 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {sample_b[0]} {sample_b[1]} {sample_b[2]} {sample_b[3]} {sample_b[4]} {sample_b[5]} {sample_b[6]} {sample_b[7]} {sample_b[8]} {sample_b[9]} {sample_b[10]} {sample_b[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list busy]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list acquisition_engine/spi_master/cs_n]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list overrun]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list sample_tick]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 1 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list sample_valid]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 1 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list acquisition_engine/spi_master/sclk]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 1 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list acquisition_engine/spi_master/sdata_a]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 1 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list acquisition_engine/spi_master/sdata_b]]

# ------------------------------------------------------------
# Filtered Channel A ILA probes
# ------------------------------------------------------------

create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 12 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list \
    {filtered_sample[0]} {filtered_sample[1]} {filtered_sample[2]} \
    {filtered_sample[3]} {filtered_sample[4]} {filtered_sample[5]} \
    {filtered_sample[6]} {filtered_sample[7]} {filtered_sample[8]} \
    {filtered_sample[9]} {filtered_sample[10]} {filtered_sample[11]}]]

create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list filtered_valid]]

create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list control_request]]

create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 1 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list actuator_enable]]

create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 8 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list     {pwm_duty[0]} {pwm_duty[1]} {pwm_duty[2]} {pwm_duty[3]}     {pwm_duty[4]} {pwm_duty[5]} {pwm_duty[6]} {pwm_duty[7]}]]

create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 2 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list     {state_code[0]} {state_code[1]}]]

set_property C_CLK_INPUT_FREQ_HZ 125000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_125]

# ------------------------------------------------------------
# PWM output ILA probe
# ------------------------------------------------------------

create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe16]
set_property port_width 1 [get_debug_ports u_ila_0/probe16]
connect_debug_port u_ila_0/probe16 [get_nets [list pwm_output]]

# ------------------------------------------------------------
# Physical actuator PWM output
# J87.1 / PMOD1_0 / XCZU7EV J9
# ------------------------------------------------------------
set_property PACKAGE_PIN J9 [get_ports actuator_pwm_out]
set_property IOSTANDARD LVCMOS33 [get_ports actuator_pwm_out]
set_false_path -to [get_ports actuator_pwm_out]
