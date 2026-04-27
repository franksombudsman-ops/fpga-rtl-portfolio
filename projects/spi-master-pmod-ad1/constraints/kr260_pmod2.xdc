# ==============================================================
# kr260_pmod2.xdc — KR260 Pmod 2 (J3) constraints
# Project: SPI Master / Pmod AD1 (AD7476A 12-bit ADC)
# ==============================================================
# Pmod 2 (J3) pin map (LVCMOS33, 3.3 V bank):
#
#   J3 Pin | Signal  | Ball | Direction | Note
#   -------|---------|------|-----------|----------------------
#     P1   | ad_cs_n | J11  | output    | ADC chip-select (active-low)
#     P2   | ad_sclk | J10  | output    | SPI clock (≤ 20 MHz)
#     P3   | ad_sdo  | K13  | input     | ADC serial data out → MISO
#     P4   | (NC)    |  —   | —         | Pmod AD1 SDI not connected
#     P7   | rst_n   | H11  | input     | Reset button (active-low, PULLUP)
# ==============================================================

# ── SPI outputs ───────────────────────────────────────────────
set_property -dict { PACKAGE_PIN J11  IOSTANDARD LVCMOS33 } [get_ports { ad_cs_n }]
set_property -dict { PACKAGE_PIN J10  IOSTANDARD LVCMOS33 } [get_ports { ad_sclk }]

# ── SPI input ─────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN K13  IOSTANDARD LVCMOS33 } [get_ports { ad_sdo }]

# ── Reset button ──────────────────────────────────────────────
set_property -dict { PACKAGE_PIN H11  IOSTANDARD LVCMOS33  PULLUP TRUE } [get_ports { rst_n }]

# ── Timing constraints ────────────────────────────────────────
# SPI clock is derived from pl_clk0 (100 MHz); SCLK max = 20 MHz
# Use a generated clock for SPI timing analysis.
# Replace "clk_source_pin" with your BD wrapper clock port name.
# create_generated_clock -name sclk_gen \
#     -source [get_ports clk] \
#     -divide_by 10 \
#     [get_ports ad_sclk]
