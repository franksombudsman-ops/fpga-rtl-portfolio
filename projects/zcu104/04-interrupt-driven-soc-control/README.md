# Project 04 - Interrupt-Driven Sensor Control SoC

- **Author:** Frank Ouma
- **Engineering:** FPGA / SoC / Digital Hardware Engineering
- **Platform:** AMD ZCU104 / Zynq UltraScale+ MPSoC
- **Toolchain:** AMD Vivado / Vitis 2023.2
- **Email:** frankotieno254@gmail.com
- **Contact:** +254725582132
- **Copyright:** (c) 2026 Frank Ouma. All rights reserved.

---

## Overview

Project 04 implements an interrupt-driven heterogeneous sensor-control
architecture on the AMD ZCU104.

The programmable logic performs deterministic sensor acquisition, digital
filtering, hysteresis evaluation, control-state sequencing and PWM generation.

The Cortex-A53 processing system supervises the programmable logic through
AXI4-Lite and receives event notifications through the Zynq UltraScale+
interrupt infrastructure.

The architecture is event-driven. Significant programmable-logic state
transitions generate a persistent interrupt rather than requiring continuous
processor polling.

## System Architecture

    Pmod AD1
        |
        v
    SPI Acquisition
        |
        v
    Moving-Average Filter
        |
        v
    Programmable Hysteresis
        |
        +----------------------> Event Detection
        |                             |
        v                             v
    Control FSM                Sticky IRQ Pending
        |                             |
        v                             v
    PWM Output                 pl_ps_irq0[0]
                                      |
                                      v
                                 Zynq PS GIC
                                      |
                                      v
                                Cortex-A53 ISR

Processor configuration and hardware status are exposed through AXI4-Lite:

    Cortex-A53
        |
    M_AXI_HPM0_FPD
        |
    AXI Interconnect
        |
    Custom Sensor-Control Peripheral
        |
    0xA4000000 - 0xA400FFFF

## Programmable-Logic Functions

The programmable logic implements:

- dual-channel Pmod AD1 acquisition;
- SPI transaction timing;
- 12-bit ADC sample extraction;
- moving-average filtering;
- programmable upper and lower hysteresis thresholds;
- deterministic actuator-control FSM;
- programmable PWM duty control;
- transition-based event detection;
- sticky interrupt-pending state;
- write-one-to-clear interrupt acknowledgement;
- hardware event counting;
- AXI4-Lite control and status access.

## AXI4-Lite Interface

The custom peripheral occupies:

- Base address: `0xA4000000`
- High address: `0xA400FFFF`
- Range: `64 KiB`
- Data width: 32 bits
- PL clock: 100 MHz

The complete software/hardware register contract is documented in
`docs/register_map.md`.

## Interrupt Architecture

The verified interrupt path is:

    soc_sensor_control_bd_0/irq_out
                |
                v
    zynq_ultra_ps_e_0/pl_ps_irq0[0]
                |
                v
         Zynq UltraScale+ GIC
                |
                v
        Interrupt ID 121
                |
                v
          Cortex-A53

The programmable-logic interrupt is active-high and level-sensitive.

The interrupt remains asserted until software acknowledges the pending event
through the write-one-to-clear interrupt register.

## Verification and Implementation Status

The following engineering milestones have been completed and verified:

- Project 04 sensor/control architecture implemented;
- self-checking interrupt-controller simulation completed;
- AXI4-Lite interrupt-control path verified;
- integrated live sensor/control simulation completed;
- Pmod AD1 acquisition path verified;
- moving-average filtering verified;
- hysteresis control verified;
- deterministic FSM and PWM integration verified;
- AXI4-Lite register interface integrated;
- Zynq Processing System integrated;
- PS-to-PL AXI connection verified;
- PL-to-PS interrupt connection verified;
- interrupt ID independently verified as `121`;
- active-high level-sensitive interrupt configuration verified;
- ZCU104 physical I/O constraints applied;
- synthesis completed successfully;
- implementation and routing completed successfully;
- routed timing closure achieved;
- Vivado block design exported to reproducible Tcl;
- complete Vivado project reconstruction verified from repository sources;
- Vitis platform generated;
- standalone Cortex-A53 interrupt application built successfully.

## Routed Timing

Verified post-route timing:

    WNS = +3.949 ns
    TNS =  0.000 ns

    WHS = +0.019 ns
    THS =  0.000 ns

The routed design therefore satisfies the implemented setup and hold timing
requirements.

The preserved methodology report contains three LUTAR-1 warnings originating
inside the Vivado-generated AXI downsizer/interconnect implementation. These
warnings are retained unchanged as part of the implementation evidence.

## Physical Interface

| Signal | Package Pin | Function |
|---|---|---|
| `ad1_cs_n` | G8 | Pmod AD1 chip select |
| `ad1_sdata_a` | H8 | Pmod AD1 channel A serial data |
| `ad1_sdata_b` | G7 | Pmod AD1 channel B serial data |
| `ad1_sclk` | H7 | Pmod AD1 serial clock |
| `actuator_pwm_out` | J9 | External actuator PWM output |

The actuator PWM signal is routed to ZCU104 physical connector J87 pin 1.

## Repository Evidence

The repository currently preserves:

- architecture documentation;
- register-map documentation;
- owned RTL;
- self-checking verification environments;
- simulation logs;
- ZCU104 physical constraints;
- routed timing evidence;
- methodology evidence;
- reproducible Vivado project-generation flow;
- reproducible Zynq PS/PL block-design description.

Physical validation evidence is maintained under `evidence/` as the
board-validation campaign proceeds.

## Hardware Validation Status

Project 04 has been physically validated on the AMD ZCU104.

The validated hardware execution chain was:

    Pmod AD1
        |
        v
    SPI acquisition
        |
        v
    moving-average filtering
        |
        v
    programmable hysteresis
        |
        +---------------------> control FSM -> PWM -> J87 output
        |
        v
    sticky interrupt pending
        |
        v
    pl_ps_irq0[0]
        |
        v
    Zynq UltraScale+ GIC
        |
        v
    Interrupt ID 121
        |
        v
    Cortex-A53 ISR

### Hardware Startup Validation

The standalone Cortex-A53 application successfully executed on the physical
ZCU104 and reported:

- AXI peripheral base: `0xA4000000`
- peripheral version: `0x00010000`
- PL interrupt ID: `121`
- GIC initialization: PASS
- PL interrupt enable: PASS
- control engine enable: PASS

The physical PWM output on J87 was also observed driving the external LED
test load.

### Live Interrupt and Hysteresis Validation

Repeated physical potentiometer sweeps produced deterministic hysteresis
transitions and Cortex-A53 interrupts.

Observed transition sequence:

| ISR Count | Event Count | Filtered ADC | Control Request |
|---:|---:|---:|---|
| 2 | 2 | `0x700` | INACTIVE |
| 3 | 3 | `0x900` | ACTIVE |
| 4 | 4 | `0x700` | INACTIVE |
| 5 | 5 | `0x900` | ACTIVE |
| 6 | 6 | `0x700` | INACTIVE |
| 7 | 7 | `0x900` | ACTIVE |

The ISR count remained equal to the hardware event count throughout the
recorded sequence.

Repeated threshold crossings generated one interrupt event per control-state
transition and the system successfully re-armed for subsequent events,
demonstrating the intended sticky-interrupt and software acknowledgement
behavior in real hardware.

### Preserved Hardware Evidence

The repository includes:

- hardware startup UART log;
- repeated interrupt/hysteresis UART log;
- recorded hardware-validation UART session;
- terminal screenshot showing live ACTIVE/INACTIVE transitions;
- screen recording of the Project 04 hardware-validation session.

These artifacts are preserved under `evidence/`.

No simulated result is represented as physical hardware evidence.

## Repository Structure

    04-interrupt-driven-soc-control/
    ├── constraints/
    ├── docs/
    ├── evidence/
    │   └── screenshots/
    ├── reports/
    ├── rtl/
    ├── scripts/
    └── tb/

The standalone Cortex-A53 software source will be preserved with the physical
hardware-validation milestone after runtime behavior has been verified.

## Engineering Provenance

The original RTL, verification environments, control architecture, AXI
integration, interrupt architecture, constraints, project integration flow and
engineering documentation in this project are authored by Frank Ouma.

AMD Vivado-generated reports and exported tool-generated structures retain
their vendor provenance and are preserved as engineering evidence rather than
represented as independently authored source.

---

Frank Ouma
FPGA / SoC / Digital Hardware Engineering
Email: frankotieno254@gmail.com
Contact: +254725582132

Copyright (c) 2026 Frank Ouma. All rights reserved.
