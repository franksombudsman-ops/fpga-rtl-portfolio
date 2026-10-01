# Project 06 — Streaming DSP Accelerator SoC

Frank Ouma  
FPGA / SoC / Digital Hardware Engineering

## 1. Target

AMD ZCU104 / Zynq UltraScale+ MPSoC  
Vivado / Vitis 2023.2

## 2. Engineering Mission

Design and physically validate a sustained-streaming FPGA DSP accelerator
that performs pipelined fixed-point computation in programmable logic while
the Cortex-A53 provides configuration, DMA supervision, reference computation
and performance measurement.

Project06 shall move beyond data acquisition and transport into hardware
computation and measurable acceleration.

## 3. Primary Accelerator

The programmable-logic accelerator shall contain:

1. configurable 32-tap FIR filtering;
2. signed fixed-point arithmetic;
3. pipelined multiply-accumulate processing;
4. moving signal-energy calculation;
5. programmable peak/event threshold detection;
6. defined rounding and saturation behavior;
7. hardware performance/event counters.

The accelerator shall be an authored RTL design rather than HLS-generated IP.

## 4. Streaming Contract

Data transport shall use AXI4-Stream.

Requirements:

- valid/ready handshake compliance;
- input data remains stable while TVALID=1 and TREADY=0;
- computation state advances only for accepted samples;
- output backpressure must propagate safely;
- TLAST packet/block boundaries must be preserved;
- no silent sample loss is permitted;
- pipeline latency shall be deterministic;
- target initiation interval is one accepted sample per accelerator clock.

## 5. Numerical Format

Baseline input and coefficient format:

- signed 16-bit Q1.15 samples;
- signed 16-bit Q1.15 coefficients;
- widened internal accumulation;
- explicit rounding;
- explicit output saturation.

Exact accumulator width and rounding point shall be frozen in the
microarchitecture before RTL implementation.

## 6. Memory / DMA Architecture

DDR shall provide source and destination buffers.

Target data path:

DDR
→ AXI DMA Scatter-Gather MM2S
→ custom DSP accelerator
→ AXI DMA Scatter-Gather S2MM
→ DDR

The software architecture shall maintain multiple receive/transmit buffers
through descriptor rings rather than CPU re-arming one packet at a time.

## 7. Control Plane

AXI4-Lite registers shall expose at minimum:

- accelerator enable;
- bypass mode;
- coefficient/configuration control;
- energy/peak threshold;
- status;
- processed-sample count;
- stall-cycle count;
- overflow/error status;
- performance counters;
- interrupt status/control where required.

## 8. Verification Requirements

Verification shall include:

- bit-accurate fixed-point reference model;
- impulse response;
- step response;
- sinusoidal input;
- positive and negative full-scale arithmetic;
- rounding cases;
- positive saturation;
- negative saturation;
- randomized AXI4-Stream backpressure;
- TLAST preservation;
- reset while idle;
- reset/recovery testing where architecturally valid;
- long randomized data streams;
- hardware/software output comparison.

No simulation result shall be represented as physical hardware evidence.

## 9. Performance Objectives

Initial implementation target:

- accelerator clock target: 150 MHz;
- initiation interval target: 1 accepted sample/clock;
- sustained DMA operation without per-sample CPU intervention;
- zero unexplained sample loss in the validated operating envelope.

Measured hardware values shall replace theoretical estimates in final
documentation.

## 10. Physical Hardware Validation

Physical validation shall include:

- ZCU104;
- real analog input through Pmod AD1 / breadboard where useful;
- deliberate physical input variation;
- live accelerator response;
- ILA observation of relevant AXI4-Stream behavior;
- Cortex-A53 result verification;
- throughput and latency measurement.

A deterministic DDR-fed vector workload shall also be used for numerical and
performance benchmarking independent of sensor rate.

## 11. Hardware / Software Benchmark

The same defined DSP workload shall be evaluated using:

1. Cortex-A53 software reference implementation;
2. FPGA streaming accelerator.

The final report shall state measured:

- sample count;
- execution time;
- throughput;
- accelerator clock;
- pipeline latency;
- FPGA resource usage;
- numerical agreement;
- measured acceleration ratio.

## 12. Implementation Signoff

Completion requires:

- self-checking RTL verification PASS;
- synthesis PASS;
- implementation PASS;
- setup/hold/pulse-width timing closure;
- CDC review where applicable;
- DRC/methodology review;
- no unjustified timing exceptions;
- reproducible block-design Tcl;
- successful bitstream;
- successful physical hardware run.

## 13. Evidence Standard

Evidence shall preserve the established portfolio convention:

- numbered descriptive screenshots;
- static evidence for static engineering claims;
- live hardware behavior recorded as short H.264 video;
- Vivado/ILA used where appropriate;
- UART/software output preserved where appropriate;
- engineering application visible;
- evidence stored under `evidence/`.

## 14. Completion Definition

Project06 is complete when a physical ZCU104 demonstrates:

DDR
→ SG DMA
→ custom pipelined DSP accelerator
→ SG DMA
→ DDR
→ Cortex-A53 verification

with correct fixed-point results, preserved AXI4-Stream semantics,
measured throughput/latency, timing closure, hardware evidence and a
reproducible repository state.

Additional sensors are not a Project06 completion requirement.
