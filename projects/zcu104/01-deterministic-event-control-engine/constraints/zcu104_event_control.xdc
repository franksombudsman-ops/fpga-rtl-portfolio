# ============================================================================
# Deterministic Event & Control Engine
# ZCU104 Physical and Timing Constraints
#
# Author:    Frank Ouma
# Email:     frankotieno254@gmail.com
# Contact:   +254725582132
# Copyright: (c) 2026 Frank Ouma. All rights reserved.
# ============================================================================


# ----------------------------------------------------------------------------
# ZCU104 300 MHz differential programmable clock
# ----------------------------------------------------------------------------

set_property PACKAGE_PIN AH18 [get_ports clk_300_p]
set_property PACKAGE_PIN AH17 [get_ports clk_300_n]

set_property IOSTANDARD DIFF_SSTL12 [get_ports clk_300_p]
set_property IOSTANDARD DIFF_SSTL12 [get_ports clk_300_n]

# J55 pin 1 / PMOD0_0
set_property PACKAGE_PIN G8 [get_ports pmod_led]
set_property IOSTANDARD LVCMOS33 [get_ports pmod_led]



# 300 MHz = 3.333333 ns period
#create_clock #   -name clk_300mhz #  -period 3.333333 # -waveform {0.000 1.666667} #[get_ports clk_300_p]


# ----------------------------------------------------------------------------
# User Pushbuttons
# ----------------------------------------------------------------------------
# PB0: event input
# PB1: application reset request
# ----------------------------------------------------------------------------

set_property PACKAGE_PIN B4 [get_ports pb_event]
set_property IOSTANDARD LVCMOS33 [get_ports pb_event]

set_property PACKAGE_PIN C4 [get_ports pb_reset]
set_property IOSTANDARD LVCMOS33 [get_ports pb_reset]


# ----------------------------------------------------------------------------
# User LEDs
# ----------------------------------------------------------------------------
# LED0: deterministic timed output
# LED1: event-counter bit 0
# LED2: accepted/debounced event state
# LED3: Clocking Wizard locked indication
# ----------------------------------------------------------------------------

set_property PACKAGE_PIN D5 [get_ports led_active]
set_property IOSTANDARD LVCMOS33 [get_ports led_active]

set_property PACKAGE_PIN D6 [get_ports led_count_lsb]
set_property IOSTANDARD LVCMOS33 [get_ports led_count_lsb]

set_property PACKAGE_PIN A5 [get_ports led_event_qualified]
set_property IOSTANDARD LVCMOS33 [get_ports led_event_qualified]

set_property PACKAGE_PIN B5 [get_ports led_clock_locked]
set_property IOSTANDARD LVCMOS33 [get_ports led_clock_locked]



# ----------------------------------------------------------------------------
# Asynchronous external controls
# ----------------------------------------------------------------------------
# Pushbuttons have no timing relationship to the 125 MHz system clock.
# Synchronization is performed explicitly in RTL.

set_false_path -from [get_ports {pb_event pb_reset}]


# ----------------------------------------------------------------------------
# Human-visible diagnostic outputs
# ----------------------------------------------------------------------------
# LEDs are not sampled by an external synchronous device and therefore
# require no board-level output timing relationship.

set_false_path -to [get_ports {led_active led_count_lsb led_event_qualified led_clock_locked pmod_led}]

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
connect_debug_port u_ila_0/clk [get_nets [list u_zcu104_clk_wiz/inst/clk_out1]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 16 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {event_count[0]} {event_count[1]} {event_count[2]} {event_count[3]} {event_count[4]} {event_count[5]} {event_count[6]} {event_count[7]} {event_count[8]} {event_count[9]} {event_count[10]} {event_count[11]} {event_count[12]} {event_count[13]} {event_count[14]} {event_count[15]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 1 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list event_debounced]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 1 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list event_pulse]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 1 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list event_sync]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 1 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list output_active]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_125]
