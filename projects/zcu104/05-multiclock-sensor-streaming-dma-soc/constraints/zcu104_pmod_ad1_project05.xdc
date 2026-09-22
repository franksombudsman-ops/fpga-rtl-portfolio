
# ============================================================
# Project 05 - Multi-Clock Sensor Streaming & DMA SoC
# ZCU104 Pmod AD1 interface
# Frank Ouma
# ============================================================

# ------------------------------------------------------------
# PMOD0 / J55 physical pins
# ------------------------------------------------------------

set_property PACKAGE_PIN G8 [get_ports ad1_cs_n]
set_property IOSTANDARD LVCMOS33 [get_ports ad1_cs_n]

set_property PACKAGE_PIN H8 [get_ports ad1_sdata_a]
set_property IOSTANDARD LVCMOS33 [get_ports ad1_sdata_a]

set_property PACKAGE_PIN G7 [get_ports ad1_sdata_b]
set_property IOSTANDARD LVCMOS33 [get_ports ad1_sdata_b]

set_property PACKAGE_PIN H7 [get_ports ad1_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports ad1_sclk]

# ------------------------------------------------------------
# AD1 SPI timing
#
# Acquisition clock = 25 MHz / 40 ns
# SPI SCLK          = 2.5 MHz / 400 ns
# Half-period       = 200 ns = 5 acquisition clocks
# ------------------------------------------------------------

create_generated_clock -name ad1_sclk_clk -source [get_pins system_i/pmod_ad1_acquisition_0/inst/spi_master/sclk_reg/C] -divide_by 10 [get_ports ad1_sclk]

# ADC return-data timing.
# 44 ns max = ADC timing plus conservative PMOD/PCB margin.
set_input_delay -clock [get_clocks ad1_sclk_clk] -clock_fall -max 44.000 [get_ports {ad1_sdata_a ad1_sdata_b}]
set_input_delay -clock [get_clocks ad1_sclk_clk] -clock_fall -min 10.000 [get_ports {ad1_sdata_a ad1_sdata_b}]

# Restrict multicycle exception to the ADC capture registers.
set ad1_shift_regs [get_cells -hier -quiet -filter {NAME =~ *pmod_ad1_acquisition_0*spi_master*shift_a_reg* || NAME =~ *pmod_ad1_acquisition_0*spi_master*shift_b_reg*}]

set_multicycle_path -setup 5 -from [get_clocks ad1_sclk_clk] -to $ad1_shift_regs
set_multicycle_path -hold 4 -end -from [get_clocks ad1_sclk_clk] -to $ad1_shift_regs

# ------------------------------------------------------------
# ILA debug-only timing exception
#
# Raw AD1 serial inputs are also observed directly by ILA.
# These debug observation paths are not functional ADC capture
# paths. Functional SDATA -> shift-register timing remains fully
# constrained above.
# ------------------------------------------------------------

set ila_ad1_cells [get_cells -hier -quiet -filter {NAME =~ *ila_ad1_0*}]

set_false_path  -from [get_ports {ad1_sdata_a ad1_sdata_b}]  -to $ila_ad1_cells


# ------------------------------------------------------------
# MPU6050 / J87 I2C interface
# ------------------------------------------------------------

# J87.1
set_property PACKAGE_PIN J9 [get_ports mpu6050_scl]
set_property IOSTANDARD LVCMOS33 [get_ports mpu6050_scl]

# J87.3
set_property PACKAGE_PIN K9 [get_ports mpu6050_sda]
set_property IOSTANDARD LVCMOS33 [get_ports mpu6050_sda]
