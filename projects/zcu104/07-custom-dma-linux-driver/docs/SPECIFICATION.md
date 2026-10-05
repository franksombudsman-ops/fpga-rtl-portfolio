# Project 07 — Custom Descriptor-Ring DMA Engine + Linux Driver

## 1. Mission

Design, implement, verify and physically validate a custom FPGA DMA subsystem
on the AMD/Xilinx ZCU104.

The subsystem shall move data autonomously between Cortex-A53 accessible DDR
and AXI4-Stream interfaces without using AMD AXI DMA as the data-movement
engine.

The project shall include:

- authored DMA RTL;
- AXI4 memory-mapped master logic;
- descriptor-ring processing;
- AXI4-Stream transmit and receive channels;
- AXI-Lite control/status interface;
- interrupt generation;
- completion handling;
- AXI error detection;
- performance instrumentation;
- Linux kernel integration;
- device-tree integration;
- DMA-safe memory handling;
- physical throughput and correctness measurements.

The project objective is not merely data transfer.

The objective is ownership of the hardware/software boundary of a real
SoC data-movement subsystem.

---

## 2. Platform

Target board:

AMD/Xilinx ZCU104

Processing system:

Cortex-A53 running Linux.

PL target clock:

150 MHz.

Known-good PS/PL clock, reset and DDR infrastructure shall be derived from the
physically validated Project 05 platform rather than from the incomplete
Project 06 integration.

---

## 3. Functional Architecture

The DMA shall implement two logical channels.

### TX channel

DDR -> AXI4-Stream

The hardware reads payload data from DDR using an AXI4 memory-mapped master
and emits the data on an AXI4-Stream master interface.

### RX channel

AXI4-Stream -> DDR

The hardware accepts AXI4-Stream payload data and writes it to DDR through an
AXI4 memory-mapped master.

Both channels shall be driven by descriptor rings stored in DDR.

---

## 4. Control Plane

Software shall control the DMA through an AXI4-Lite register interface.

The control interface shall expose at minimum:

- global enable;
- soft reset;
- TX ring base;
- TX ring size;
- TX producer/tail index;
- TX hardware head index;
- RX ring base;
- RX ring size;
- RX producer/tail index;
- RX hardware head index;
- interrupt enable;
- interrupt status;
- error status;
- error address/information;
- byte counters;
- descriptor counters;
- cycle counters;
- stall counters.

Software must never modify hardware-owned state directly.

---

## 5. Descriptor Rings

TX and RX shall use independent rings.

Each descriptor shall occupy exactly 64 bytes and shall be 64-byte aligned.

Descriptor addresses shall be represented as 64-bit values in the software ABI.

The initial hardware implementation shall support the Zynq UltraScale+
physical address range required by the target platform.

Each descriptor shall contain enough information to represent:

- payload buffer address;
- requested transfer length;
- control flags;
- software cookie/tag;
- hardware completion status;
- actual transferred length;
- error result.

Descriptors shall have explicit ownership semantics.

Software shall fully construct a descriptor before transferring ownership to
hardware.

Hardware shall not process a descriptor that is not owned by hardware.

Completion status shall become visible before hardware publishes completion.

Memory ordering requirements shall be explicitly documented for Linux.

---

## 6. AXI4 Memory-Mapped Requirements

The DMA shall author its own AXI4 memory-mapped transaction logic.

The implementation shall support:

- INCR bursts;
- legal AWLEN/ARLEN generation;
- address advancement;
- burst splitting;
- 4-KiB AXI boundary enforcement;
- WLAST generation;
- RLAST checking;
- BRESP checking;
- RRESP checking;
- backpressure on all AXI channels;
- stable payload/control while VALID && !READY;
- deterministic completion accounting.

No generated burst may cross a 4-KiB boundary.

Malformed AXI responses shall place the affected channel into an error state
and produce software-visible diagnostic information.

---

## 7. Data Widths

Initial implementation:

AXI4-MM data width: 64 bits.

AXI4-Stream TX width: 64 bits.

AXI4-Stream RX width: 64 bits.

Payload buffers shall initially be 8-byte aligned.

Transfer lengths shall initially be multiples of 8 bytes.

Unaligned transfer support is outside the first implementation milestone and
may later be implemented as an explicit data-realignment extension.

---

## 8. AXI4-Stream Requirements

### TX

Once TVALID is asserted, TDATA/TKEEP/TLAST shall remain stable until the
TVALID && TREADY handshake occurs.

TX shall not lose, duplicate or reorder accepted payload bytes.

TLAST shall identify the final AXI4-Stream beat belonging to one descriptor.

### RX

RX shall apply backpressure using TREADY when internal buffering cannot accept
additional data.

The implementation shall detect descriptor-buffer exhaustion.

No silent payload overwrite is permitted.

Unexpected TLAST or descriptor length mismatches shall be explicitly handled
and reported.

---

## 9. Interrupts

The DMA shall expose an interrupt output to the processing system.

Interrupt causes shall include at minimum:

- TX completion;
- RX completion;
- TX error;
- RX error.

Interrupt status shall be latched.

Software shall acknowledge causes explicitly.

Completion and error events shall never depend on polling alone.

---

## 10. Performance Instrumentation

Hardware counters shall include at minimum:

- TX bytes transferred;
- RX bytes transferred;
- TX descriptors completed;
- RX descriptors completed;
- active cycles;
- AXI read stall cycles;
- AXI write stall cycles;
- AXIS TX stall cycles;
- AXIS RX stall cycles;
- interrupt count;
- error count.

Counter behavior on overflow and counter-clear operations shall be defined.

---

## 11. Error Handling

The design shall detect and expose at minimum:

- descriptor alignment error;
- payload alignment error;
- illegal zero-length descriptor;
- unsupported address;
- AXI read SLVERR/DECERR;
- AXI write SLVERR/DECERR;
- malformed read completion;
- descriptor ownership violation;
- RX length overflow;
- internal protocol/state error.

Errors shall never silently corrupt subsequent descriptors.

A channel shall either recover in a defined manner or enter a software-visible
halted/error state.

---

## 12. Verification Requirements

Before physical hardware integration the RTL shall pass self-checking
verification covering:

- single descriptor;
- descriptor rings;
- ring wraparound;
- random AXI backpressure;
- random AXIS backpressure;
- minimum transfer;
- large transfer;
- maximum legal burst;
- 4-KiB boundary split;
- multiple burst transfer;
- TX TLAST generation;
- RX TLAST handling;
- descriptor ownership;
- completion writeback;
- ring exhaustion;
- invalid descriptors;
- AXI error injection;
- reset during idle;
- reset/error recovery.

Scoreboards shall compare every transferred byte.

Waveform inspection alone shall not constitute verification.

---

## 13. Physical Bring-Up Gates

Physical integration shall proceed incrementally.

Gate 1:
A53 reads a custom identification register.

Gate 2:
A53 writes and reads a scratch register.

Gate 3:
PL interrupt reaches the A53/Linux interrupt handler.

Gate 4:
one descriptor is fetched from DDR.

Gate 5:
one aligned TX DMA transfer completes.

Gate 6:
one aligned RX DMA transfer completes.

Gate 7:
descriptor-ring wraparound completes correctly.

Gate 8:
sustained bidirectional operation.

No later gate shall be attempted until the previous gate is proven.

---

## 14. Linux Requirements

A custom Linux platform driver shall be developed.

The driver shall:

- bind through Device Tree;
- map AXI-Lite registers;
- request the device interrupt;
- allocate/manage descriptor memory;
- use Linux DMA APIs correctly;
- enforce required memory barriers;
- handle interrupt acknowledgement;
- recover/report errors;
- expose a controlled userspace interface;
- collect performance statistics.

Direct userspace /dev/mem register poking is not the final software
architecture.

---

## 15. Cache and Coherency Requirements

The design shall initially assume a non-coherent PL DMA path unless physical
platform configuration proves otherwise.

Descriptor and payload ownership transitions shall use the Linux DMA API and
required memory-ordering primitives.

Software shall not assume that normal cached virtual memory is automatically
coherent with the FPGA DMA master.

Cache correctness is part of functional correctness.

---

## 16. Performance Goal

Correctness is the first milestone.

After correctness is proven, the system shall measure:

- sustained TX throughput;
- sustained RX throughput;
- descriptor processing rate;
- interrupt rate;
- AXI stall percentage;
- AXIS stall percentage;
- CPU utilization.

Results shall distinguish:

- hardware transfer time;
- driver/software overhead;
- userspace end-to-end latency.

No theoretical bandwidth shall be represented as measured throughput.

---

## 17. Completion Criteria

Project 07 is complete only when:

1. authored DMA RTL is verified;
2. AXI protocol behavior is verified;
3. implementation timing is closed;
4. physical AXI-Lite access is proven;
5. descriptor fetch is proven in hardware;
6. TX and RX DDR transfers are proven;
7. Linux driver operates using the DMA API;
8. interrupts are physically demonstrated;
9. descriptor ring wraparound is demonstrated;
10. measured throughput is reported;
11. failure/error behavior is demonstrated;
12. evidence and reconstruction scripts are committed.

