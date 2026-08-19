# FPGA / SoC RTL Engineering Portfolio

A portfolio of synthesizable digital hardware, FPGA, and heterogeneous SoC
designs developed in SystemVerilog across AMD/Xilinx Zynq UltraScale+
platforms.

The repository documents the progression from standalone RTL architectures
and peripheral controllers through timing-constrained FPGA implementation,
physical hardware interfaces, processor/programmable-logic integration,
embedded Linux control, high-throughput datapaths, and ASIC-oriented reusable
RTL IP.

## Platform Progression

### Kria KR260

The initial project series established RTL design and verification experience
using the Xilinx Kria KR260 Robotics Starter Kit.

| Project | Status | Key Techniques |
|---|---|---|
| [Debounced LED Controller](projects/debounced-led-controller/) | RTL complete, simulation verified, constraints complete | CDC synchronization, debounce logic, edge detection, Johnson counter |
| [SPI Master Controller](spi-master-controller/) | RTL complete, simulation verified | SPI Mode 0, parameterized clock generation, FSM control, shift registers, AD7476A frame handling |

### AMD ZCU104

Current development targets the AMD ZCU104 based on the Zynq UltraScale+
MPSoC architecture.

The ZCU104 project series expands into:

- deterministic hardware control
- physical GPIO and external electronics
- timing analysis and timing closure
- embedded FPGA instrumentation
- PWM and motor-control architectures
- serial sensor and peripheral interfaces
- AXI4-Lite and AXI4-Stream systems
- programmable-logic / processing-system integration
- DMA and high-throughput data movement
- interrupts and Linux-controlled custom hardware
- reusable ASIC-oriented RTL architectures

See [projects/zcu104](projects/zcu104/) for the current engineering series.

## Engineering Workflow

Projects are developed using a specification-driven hardware workflow:

1. Functional requirements and interface definition
2. Hardware microarchitecture
3. SystemVerilog RTL implementation
4. Testbench development and functional verification
5. FPGA synthesis
6. Implementation and static timing analysis
7. Resource-utilization analysis
8. Bitstream generation
9. Physical hardware integration
10. On-device instrumentation and debugging
11. Hardware validation against expected behavior
12. Documentation and reproducibility

Generated tool state is excluded from source control. The repository retains
the RTL, constraints, verification environments, automation scripts, selected
implementation reports, and hardware-validation evidence required to
understand and reproduce each design.

## Current Toolchain

- RTL: SystemVerilog
- FPGA Toolchain: AMD Vivado / Vitis 2023.2
- Embedded Linux: PetaLinux 2023.2
- Primary Platform: AMD ZCU104
- Previous Platform: Xilinx Kria KR260
- Simulation: Vivado XSim / compatible SystemVerilog simulators
- Source Control: Git / GitHub

## Repository Conventions

Individual engineering projects may contain:

- `rtl/` — synthesizable RTL
- `tb/` — verification and testbench sources
- `constraints/` — board and timing constraints
- `scripts/` — reproducible build and automation scripts
- `docs/` — architecture and engineering documentation
- `reports/` — selected synthesis, implementation, timing, and validation evidence

Tool-generated Vivado working directories are intentionally excluded from
version control.

---

Frank Ouma  
FPGA / SoC / Digital Hardware Engineering  
Email: frankotieno254@gmail.com  
Contact: +254725582132  

Copyright (c) 2026 Frank Ouma. All rights reserved.
