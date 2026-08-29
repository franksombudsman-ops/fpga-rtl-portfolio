# Project 04 Architecture

- **Author:** Frank Ouma
- **Engineering:** FPGA / SoC / Digital Hardware Engineering
- **Platform:** AMD ZCU104 / Zynq UltraScale+ MPSoC
- **Email:** frankotieno254@gmail.com
- **Contact:** +254725582132
- **Copyright:** (c) 2026 Frank Ouma. All rights reserved.

---

Project 04 integrates the previously validated real-time sensor/control datapath
with the Zynq Processing System.

Physical signal path:

Potentiometer -> Pmod AD1 -> SPI acquisition -> filtering -> hysteresis ->
control FSM -> PWM -> external physical output.

Processor interaction:

Cortex-A53 <-> AXI4-Lite <-> custom control/status peripheral.

Event interaction:

Programmable Logic -> interrupt output -> Zynq PS GIC -> Cortex-A53 ISR.

The processor configures thresholds, PWM duty, engine enable and interrupt
control. The FPGA independently performs deterministic acquisition and control.

The processor is notified only when significant hardware events occur rather
than continuously polling the FPGA.
