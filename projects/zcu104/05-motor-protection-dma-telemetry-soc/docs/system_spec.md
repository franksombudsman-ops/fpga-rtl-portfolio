# Project 05 — Multi-Sensor Motor Protection & DMA Telemetry SoC

Frank Ouma
FPGA / SoC / Digital Hardware Engineering
Email: frankotieno254@gmail.com
Contact: +254725582132
Copyright (c) 2026 Frank Ouma. All rights reserved.

## Target

AMD ZCU104

## Confirmed Physical Hardware

- Pmod AD1
- MPU6050 accelerometer / gyroscope
- HC-SR501 PIR motion sensor
- DC motor
- Two 5 V relay modules
- Potentiometer
- LEDs
- Resistors
- Capacitors
- Diodes
- Breadboard

## Functional Objective

Implement an autonomous FPGA motor protection and condition-monitoring
controller with processor-supervised telemetry.

The PL shall:

1. acquire motion/vibration information from the MPU6050;
2. acquire an adjustable threshold from the potentiometer through Pmod AD1;
3. acquire PIR state as a digital input;
4. execute deterministic READY, RUN, WARNING and TRIP logic;
5. control the normal motor relay;
6. control a secondary motor interlock relay;
7. drive physical status LEDs;
8. generate processor interrupts for important events;
9. generate continuous AXI4-Stream telemetry;
10. transfer telemetry to PS DDR through AXI DMA.

The Cortex-A53 shall provide supervisory event handling and DMA data
processing rather than execute the deterministic protection loop.

## Major Interfaces

- SPI / ADC acquisition
- I2C MPU6050 acquisition
- asynchronous external digital input
- relay and LED GPIO outputs
- AXI4-Lite control/status
- AXI4-Stream telemetry
- AXI DMA
- DDR
- PL-to-PS interrupts

## Physical Demonstration Target

PIR activity permits motor operation.

The MPU6050 provides live vibration/movement measurements.

A potentiometer adjusts the configured vibration threshold.

Abnormal measured movement causes WARNING/TRIP behavior.

A TRIP removes motor power through the secondary interlock relay.

LEDs provide visible system-state indication.

Telemetry preceding and following the event is transferred into DDR.

The Cortex-A53 receives significant PL events through the GIC.

This project is an engineering demonstration and is not a certified
functional-safety system.
