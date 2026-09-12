# Project 05 — Multi-Clock Sensor Streaming & DMA SoC

Frank Ouma
FPGA / SoC / Digital Hardware Engineering
Email: frankotieno254@gmail.com
Contact: +254725582132
Copyright (c) 2026 Frank Ouma. All rights reserved.

## Target

AMD ZCU104

## Engineering Objective

Design and physically validate a multi-source FPGA acquisition architecture
that captures real sensor data concurrently, crosses clock domains safely,
buffers and packetizes samples, handles downstream backpressure, and transfers
continuous telemetry into PS DDR through AXI DMA.

The Cortex-A53 operates as a supervisory and data-processing layer rather than
performing deterministic sample acquisition.

## Confirmed Physical Sources

- Pmod AD1 with potentiometer analog input
- MPU6050 accelerometer / gyroscope
- HC-SR501 PIR motion sensor
- LEDs
- resistors, capacitors and diodes
- breadboard

Two relay modules and a DC motor are available as an optional physical
application output. They are not dependencies for successful completion of
the streaming architecture.

## Core PL Architecture

### Sensor acquisition

- SPI acquisition from Pmod AD1
- I2C acquisition from MPU6050
- synchronized asynchronous PIR input

### Data architecture

- independent acquisition timing
- timestamps and sequence numbers
- clock-domain crossing
- asynchronous FIFO buffering
- source arbitration
- telemetry packet formatting
- AXI4-Stream transport
- TVALID/TREADY backpressure handling
- overflow/error detection
- AXI DMA transfer to PS DDR

### Control plane

AXI4-Lite registers shall configure and expose:

- acquisition enable
- sampling parameters
- stream status
- FIFO status
- overflow/error flags
- event counters
- interrupt status/control

### Processor interaction

Critical hardware events shall reach the Cortex-A53 through the Zynq GIC.

DMA completion and telemetry processing shall be handled in Vitis software.

## Physical Validation Target

During hardware validation:

1. analog input shall be changed physically using the potentiometer;
2. MPU6050 shall be moved/tilted to generate changing acceleration data;
3. PIR activity shall generate asynchronous hardware events;
4. samples from multiple sources shall be timestamped and streamed;
5. temporary downstream stalls shall exercise backpressure and buffering;
6. DMA shall transfer telemetry blocks into DDR;
7. Cortex-A53 software shall verify sequence and data integrity;
8. FIFO overflow/error behavior shall be intentionally tested;
9. ILA shall be used where useful to observe AXI4-Stream and CDC behavior.

## Primary Engineering Concepts

- multi-clock FPGA architecture
- CDC
- asynchronous FIFOs
- I2C
- SPI
- AXI4-Lite
- AXI4-Stream
- packetization
- arbitration
- buffering
- backpressure
- DMA
- DDR
- interrupts
- hardware/software partitioning
- timing closure
- physical validation

