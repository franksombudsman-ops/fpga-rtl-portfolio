# Project 04 Register Map

- **Author:** Frank Ouma
- **Engineering:** FPGA / SoC / Digital Hardware Engineering
- **Platform:** AMD ZCU104 / Zynq UltraScale+ MPSoC
- **Email:** frankotieno254@gmail.com
- **Contact:** +254725582132
- **Copyright:** (c) 2026 Frank Ouma. All rights reserved.

---

- Base address: `0xA4000000`
- High address: `0xA400FFFF`
- Range: `64 KiB`
- Bus: AXI4-Lite
- Data width: 32-bit

| Offset | Register | Access | Purpose |
|--------|----------|--------|---------|
| 0x00 | CONTROL | RW | bit0 ENGINE_ENABLE |
| 0x04 | STATUS | RO | live control/FSM status |
| 0x08 | THRESHOLD_HIGH | RW | upper ADC threshold |
| 0x0C | THRESHOLD_LOW | RW | lower ADC threshold |
| 0x10 | PWM_DUTY | RW | commanded PWM duty |
| 0x14 | SENSOR_RAW | RO | live 12-bit ADC sample |
| 0x18 | SENSOR_FILTERED | RO | live filtered ADC sample |
| 0x1C | VERSION | RO | hardware version |
| 0x20 | IRQ_ENABLE | RW | bit0 sensor/control interrupt enable |
| 0x24 | IRQ_STATUS | RO | bit0 pending interrupt |
| 0x28 | IRQ_CLEAR | WO | write bit0=1 to clear pending interrupt |
| 0x2C | EVENT_COUNT | RO | number of interrupt-generating events |

## Interrupt Behaviour

- FPGA asserts IRQ when a defined sensor/control event occurs.
- IRQ_STATUS remains asserted until software acknowledges it.
- ARM interrupt handler reads IRQ_STATUS and live sensor/status registers.
- ARM clears the interrupt by writing 1 to IRQ_CLEAR bit0.
- IRQ_ENABLE allows software to mask/unmask the interrupt.
