# ------------------------------------------------------------
# Pmod AD1 on J55
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
# External actuator PWM on J87 pin 1
# FPGA package ball J9
# ------------------------------------------------------------

set_property PACKAGE_PIN J9 [get_ports actuator_pwm_out]
set_property IOSTANDARD LVCMOS33 [get_ports actuator_pwm_out]


# ------------------------------------------------------------
# External protocol-timed interfaces
#
# AD1 serial data is captured by the 100 MHz PL clock using an
# internally qualified SPI sampling enable. ad1_sclk is not used
# as a fabric capture clock.
#
# Therefore these external protocol paths are intentionally
# excluded from synchronous PL clock STA. Their timing is
# validated by the SPI protocol timing and physical hardware test.
# ------------------------------------------------------------

set_false_path -from [get_ports {ad1_sdata_a ad1_sdata_b}]

set_false_path -to [get_ports {
    ad1_cs_n
    ad1_sclk
    actuator_pwm_out
}]
