# Project 06 — Physical Validation Status

Date: 2026-10-05  
Platform: AMD/Xilinx ZCU104

## Verified

The following Project 06 engineering stages were completed successfully:

- fixed-point DSP numerical contract;
- Python reference model;
- 32-tap streaming FIR RTL;
- moving 64-sample energy calculation;
- threshold-crossing event detection;
- AXI4-Stream backpressure behavior;
- AXI4-Lite control/status register interface;
- self-checking RTL verification;
- 4,672 samples across impulse, step, alternating full-scale and random campaigns;
- accelerator synthesis;
- full ZCU104 SoC synthesis and implementation;
- 150 MHz timing closure;
- DRC / CDC / methodology review;
- SG-DMA SoC architecture implementation;
- bitstream generation;
- XSA generation;
- bare-metal SG-DMA validation software build.

The implemented accelerator used 41 DSP48E2 resources and achieved positive post-route timing margin.

## Physical Validation Attempt

Physical validation progressed to programming the ZCU104 and executing Cortex-A53 software intended to access the AXI DMA and accelerator control registers.

The Cortex-A53 was unable to complete accesses to the PL AXI control-plane peripherals.

Direct XSDB/JTAG memory accesses were also used during diagnosis.

Debugging included investigation of:

- PL clock activity;
- PL reset state;
- PS/PL isolation;
- programmed bitstream identity;
- generated PS initialization;
- AXI address mapping;
- HPM0 FPD control access;
- an experimental HPM0 LPD control configuration.

The physical control-plane issue was not resolved during this Project 06 run.

The experimental address/interface modifications used during diagnosis are not retained as the canonical Project 06 architecture.

## Engineering Boundary

The failure point was physical PS-to-PL AXI control-plane access.

This does not invalidate the independently verified:

- DSP mathematics;
- accelerator RTL;
- AXI4-Stream protocol behavior;
- AXI4-Lite RTL behavior;
- synthesis;
- implementation;
- timing closure.

However, because physical register access was not established, the following are explicitly **not claimed**:

- successful physical SG-DMA transfer through the Project 06 accelerator;
- physical DDR-to-accelerator-to-DDR processing;
- measured FPGA throughput;
- measured Cortex-A53 versus FPGA performance;
- lossless sustained physical streaming.

## Project Status

Project 06 is preserved as a technically substantial but physically incomplete SoC integration project.

Status:

**RTL / verification / implementation: PASS**

**Physical PS-to-PL SoC integration: BLOCKED**

The unresolved physical integration issue is documented rather than hidden or represented as successful hardware validation.

Project 06 remains available for future recovery after establishment of a reusable physically validated ZCU104 PS/PL platform.
