# Project 07 — DMA Microarchitecture

## 1. Top-Level Blocks

The DMA shall be divided into independently verifiable blocks.

### dma_axil_regs

AXI4-Lite slave.

Responsibilities:

- control;
- ring configuration;
- interrupt configuration;
- status;
- error reporting;
- performance-counter access.

It shall not contain the primary data-movement state machines.

---

### dma_ring_manager

Maintains software/hardware ownership of TX and RX rings.

Responsibilities:

- head tracking;
- tail observation;
- descriptor availability;
- ring wraparound;
- descriptor dispatch;
- completion retirement.

TX and RX ring state shall remain independent.

---

### dma_descriptor_engine

Moves descriptor information between DDR and internal hardware state.

Responsibilities:

- descriptor fetch requests;
- descriptor parsing;
- ownership validation;
- descriptor completion writeback;
- descriptor-error reporting.

Descriptor traffic shall use the same external AXI4 memory system as payload
traffic but shall remain logically distinct from payload movement.

---

### dma_tx_engine

Moves payload:

DDR -> AXI4-Stream.

Responsibilities:

- consume a validated TX descriptor;
- generate AXI read requests;
- split transfers into legal bursts;
- enforce 4-KiB boundaries;
- buffer returning AXI read data;
- generate AXI4-Stream output;
- generate TKEEP/TLAST;
- count completed bytes;
- return descriptor completion/error.

---

### dma_rx_engine

Moves payload:

AXI4-Stream -> DDR.

Responsibilities:

- consume a validated RX descriptor;
- accept AXI4-Stream data;
- apply backpressure;
- buffer payload;
- generate AXI write bursts;
- enforce 4-KiB boundaries;
- generate WLAST;
- check BRESP;
- handle TLAST/length conditions;
- return descriptor completion/error.

---

### dma_axi_master

Owns the external AXI4 memory-mapped master interface.

Responsibilities:

- AR channel;
- R channel;
- AW channel;
- W channel;
- B channel;
- arbitration between descriptor and payload requests;
- AXI IDs where implemented;
- outstanding-transaction accounting;
- protocol assertions;
- response routing.

The rest of the DMA shall issue internal memory-operation requests rather than
directly manipulating external AXI signals.

This separation prevents descriptor logic, TX logic and RX logic from each
implementing incompatible AXI behavior.

---

### dma_irq_controller

Responsibilities:

- latch interrupt causes;
- mask/unmask causes;
- expose pending state;
- generate one PS interrupt output;
- explicit software acknowledgement.

Interrupt causes:

- TX completion;
- RX completion;
- TX error;
- RX error.

---

### dma_perf_counters

Counts:

- transferred bytes;
- completed descriptors;
- active cycles;
- AXI stalls;
- AXIS stalls;
- interrupts;
- errors.

Counters shall not participate in functional decisions.

---

## 2. Internal Transaction Abstraction

Descriptor and payload engines shall request memory operations through a
defined internal interface.

A memory read request shall include:

- requester ID;
- address;
- byte count;
- completion destination.

A memory write request shall include:

- requester ID;
- address;
- byte count;
- write-data stream;
- completion destination.

This internal contract allows the AXI master implementation to be verified
independently from descriptor semantics.

---

## 3. TX Data Flow

1. Software constructs TX descriptor.
2. Software transfers ownership to hardware.
3. Software advances TX tail.
4. Ring manager observes descriptor availability.
5. Descriptor engine fetches descriptor.
6. Descriptor is validated.
7. TX engine receives buffer address and length.
8. TX engine calculates legal AXI burst.
9. AXI master reads DDR.
10. Read data enters TX buffering.
11. TX engine emits AXI4-Stream data.
12. Backpressure is absorbed by buffering and propagated to AXI request issue.
13. Final beat asserts TLAST.
14. Descriptor completion is generated.
15. Completion status is written to DDR.
16. Hardware head advances.
17. Completion interrupt may be raised.

---

## 4. RX Data Flow

1. Software supplies empty RX buffer descriptor.
2. Software transfers ownership to hardware.
3. Software advances RX tail.
4. Descriptor engine fetches and validates descriptor.
5. RX engine accepts AXI4-Stream payload.
6. Payload is buffered.
7. RX engine generates legal DDR write bursts.
8. AXI master writes DDR.
9. BRESP is checked.
10. Transfer terminates according to descriptor/TLAST contract.
11. Actual received length is recorded.
12. Completion status is written.
13. Hardware head advances.
14. Completion interrupt may be raised.

---

## 5. Burst Planner

A dedicated burst planner shall determine the next legal AXI burst.

Inputs:

- current byte address;
- bytes remaining;
- maximum configured burst beats;
- AXI beat size.

Output:

- burst start address;
- number of beats;
- bytes represented by burst.

It shall enforce:

- no 4-KiB crossing;
- maximum AXI burst length;
- configured alignment rules;
- no transfer beyond descriptor length.

The burst planner shall be independently unit tested.

---

## 6. Buffering

External AXI and AXI4-Stream interfaces may independently stall.

Therefore direct combinational coupling between the interfaces is prohibited.

TX shall contain buffering between AXI read responses and AXIS output.

RX shall contain buffering between AXIS input and AXI write data.

Buffer occupancy shall participate in request throttling.

No accepted byte may be silently discarded because the opposite interface
stalled.

---

## 7. Channel Independence

TX and RX shall have:

- independent ring head/tail state;
- independent errors;
- independent completion accounting;
- independent enable/halt state.

A fault in TX shall not silently destroy RX state and vice versa.

Global reset may reset both channels.

---

## 8. Reset Strategy

Reset shall place all external AXI VALID outputs low.

After reset:

- channels disabled;
- no descriptors owned internally;
- interrupts cleared;
- errors cleared;
- counters reset according to defined policy;
- AXI outstanding count zero.

Software shall explicitly configure ring bases and sizes before enabling a
channel.

---

## 9. Verification Partitioning

The following units shall have independent self-checking testbenches:

1. burst planner;
2. AXI4-Lite register block;
3. descriptor parser/ring manager;
4. AXI read master;
5. AXI write master;
6. TX engine;
7. RX engine;
8. interrupt controller;
9. integrated DMA.

Integrated verification shall include randomized READY/VALID timing and an
AXI memory model.


## Descriptor Retirement Publication Rule

HW_HEAD is the authoritative software-visible descriptor retirement boundary.

Clearing a descriptor OWN bit is not, by itself, sufficient publication of
completion.

The required successful sequence is:

    payload completion
        ->
    STATUS / ACTUAL_LENGTH write
        ->
    successful BRESP
        ->
    OWN-clear write
        ->
    successful BRESP
        ->
    HW_HEAD advance

If either writeback receives a non-OKAY BRESP, HW_HEAD remains unchanged and
the descriptor channel enters a faulted state.

Because an AXI error response does not imply rollback of an already accepted
write-data beat, software shall treat the affected descriptor memory as
untrusted after such a failure and shall use HW_HEAD as the authoritative
reclamation boundary.
