# Project 07 — Verification Plan

## Verification Objective

Project 07 shall be verified from independently testable blocks upward.

Waveform inspection alone is not considered proof.

Every functional block shall use self-checking verification and shall produce
an explicit PASS or FAIL result.

## Verification Levels

### Level 1 — Unit Verification

Independently verify:

1. dma_burst_planner
2. dma_axil_regs
3. dma_irq_controller
4. dma_ring_manager
5. dma_descriptor_parser
6. dma_axi_read_master
7. dma_axi_write_master
8. dma_tx_engine
9. dma_rx_engine

### Level 2 — Memory-System Verification

Verify descriptor and payload access using a behavioral AXI memory model.

Required cases:

- AXI READY backpressure;
- delayed read data;
- delayed write response;
- read SLVERR;
- read DECERR;
- write SLVERR;
- write DECERR;
- malformed RLAST;
- multiple consecutive bursts.

### Level 3 — Descriptor-Ring Verification

Required cases:

- one descriptor;
- multiple descriptors;
- ring wraparound;
- producer catches consumer;
- empty ring;
- descriptor ownership transition;
- descriptor validation failure;
- completion writeback;
- software cookie preservation;
- independent TX/RX rings.

### Level 4 — Integrated DMA Verification

A scoreboard shall compare every transferred payload byte.

Required TX tests:

- 8-byte transfer;
- one complete burst;
- multiple bursts;
- 4-KiB split;
- AXIS backpressure;
- TLAST position;
- long descriptor;
- multiple descriptors.

Required RX tests:

- 8-byte transfer;
- multiple bursts;
- DDR backpressure;
- AXIS backpressure propagation;
- TLAST handling;
- RX buffer exhaustion;
- length mismatch;
- descriptor ring wraparound.

### Level 5 — Error Injection

Verify that faults become explicit software-visible errors.

Required:

- bad descriptor alignment;
- bad payload alignment;
- zero length;
- unsupported address;
- AXI read error;
- AXI write error;
- unexpected RLAST;
- RX overflow;
- internal state violation.

No injected error may be reported as successful completion.

### Level 6 — Implementation Signoff

Before bitstream:

- synthesis PASS;
- implementation PASS;
- setup timing PASS;
- hold timing PASS;
- pulse-width timing PASS;
- unconstrained internal endpoints = 0;
- CDC review complete;
- DRC critical/error issues = 0;
- methodology critical/error issues reviewed;
- route status complete.

### Level 7 — Physical Bring-Up

Physical gates are sequential.

GATE 1:
A53 reads ID = 0x43444D41.

GATE 2:
A53 writes and reads SCRATCH exactly.

GATE 3:
PL-generated interrupt reaches software.

GATE 4:
hardware fetches one descriptor from DDR.

GATE 5:
one TX transfer completes.

GATE 6:
one RX transfer completes.

GATE 7:
descriptor ring wraparound completes.

GATE 8:
continuous multi-descriptor operation.

No later physical gate shall be attempted before the previous gate passes.

### Level 8 — Linux Validation

Verify:

- Device Tree binding;
- platform-driver probe/remove;
- MMIO mapping;
- IRQ registration;
- DMA memory allocation;
- descriptor synchronization;
- memory barriers;
- completion handling;
- error handling;
- userspace interface.

### Level 9 — Performance Characterization

Measure separately:

- TX throughput;
- RX throughput;
- descriptor rate;
- interrupt rate;
- CPU utilization;
- AXI stall cycles;
- AXIS stall cycles;
- driver overhead;
- end-to-end latency.

Theoretical bandwidth shall never be presented as measured bandwidth.
