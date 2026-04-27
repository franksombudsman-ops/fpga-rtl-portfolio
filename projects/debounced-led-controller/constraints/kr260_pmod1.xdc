# ==============================================================
# top.xdc — KR260 Pmod 1 (J2) constraints
# Project: Debounced LED Controller (3-bit Johnson counter)
# ==============================================================

# ── LEDs ──────────────────────────────────────────────────────
# P1 = H12, P3 = D10, P2 = E10




set_property -dict { PACKAGE_PIN H12  IOSTANDARD LVCMOS33 } [get_ports { leds[0] }]
set_property -dict { PACKAGE_PIN D10  IOSTANDARD LVCMOS33 } [get_ports { leds[1] }]
set_property -dict { PACKAGE_PIN E10  IOSTANDARD LVCMOS33 } [get_ports { leds[2] }]

# ── Advance button on Pmod P4 ────────────────────────────────
# Active-high: button connects pin to 3.3V, internal pull-down
set_property -dict { PACKAGE_PIN C11  IOSTANDARD LVCMOS33  PULLDOWN TRUE } [get_ports { btn_raw }]

# ── Reset button on Pmod P7 ──────────────────────────────────
# Active-low: button connects pin to GND, internal pull-up
set_property -dict { PACKAGE_PIN B10  IOSTANDARD LVCMOS33  PULLUP TRUE } [get_ports { rst_n }]


