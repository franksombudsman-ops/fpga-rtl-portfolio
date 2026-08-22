# Deterministic Event & Control Engine
## Microarchitecture Definition

**Project:** ZCU104-01  
**Platform:** AMD ZCU104 — Zynq UltraScale+ MPSoC  
**Author:** Frank Ouma  
**Engineering Contact:** frankotieno254@gmail.com  
**Contact:** +254725582132  

---

## 1. Architecture Overview

The design converts an asynchronous physical event into a qualified,
clock-synchronous hardware event and a deterministic timed output response.

Primary signal path:

    event_async
        |
        v
    input synchronizer
        |
        v
    debounce filter
        |
        v
    rising-edge detector
        |
        v
    event_pulse
       / \
      /   \
     v     v
event     output
counter   controller
             |
             v
        output_active

All functional logic following the synchronization boundary operates in the
125 MHz system clock domain.

---

## 2. Input Synchronizer

Purpose:

- isolate functional logic from the asynchronous external input;
- reduce the probability of metastability propagating into the design;
- provide a clock-domain-aligned signal for subsequent processing.

Initial architecture:

    event_async -> FF1 -> FF2 -> event_sync

The synchronizer contains two sequential registers clocked from the 125 MHz
system clock.

Implementation attributes appropriate to synchronization registers shall be
applied during RTL implementation.

---

## 3. Debounce Filter

The debounce filter compares the synchronized input against the currently
accepted debounced state.

Registers:

    event_debounced
    debounce_counter[20:0]

Algorithm:

    if event_sync equals event_debounced:
        debounce_counter = 0

    else:
        increment debounce_counter

        if the disagreement remains for DEBOUNCE_CYCLES:
            event_debounced = event_sync
            debounce_counter = 0

For a 125 MHz clock and 10 ms debounce interval:

    DEBOUNCE_CYCLES = 1,250,000

A 21-bit counter is sufficient because:

    2^20 = 1,048,576
    2^21 = 2,097,152

Both input assertion and input release are qualified by the same mechanism.

---

## 4. Rising-Edge Detector

The edge detector converts a qualified LOW-to-HIGH transition into one
clock-cycle event pulse.

Stored state:

    event_debounced_d

Logic relationship:

    event_pulse = event_debounced AND NOT event_debounced_d

The delayed state is updated once per system clock.

A continuously asserted input therefore produces one event rather than one
event on every system clock.

---

## 5. Event Counter

The event counter records every qualified event pulse.

Width:

    16 bits

Operation:

    if event_pulse:
        event_count = event_count + 1

Overflow behavior is modulo 65536.

Reset clears event_count to zero.

---

## 6. Output Controller

The initial controller is a two-state non-retriggerable architecture.

States:

    IDLE
    ACTIVE

IDLE behavior:

    output_active = 0
    output_timer = 0

On event_pulse:

    IDLE -> ACTIVE

ACTIVE behavior:

    output_active = 1
    output_timer increments

Events received during ACTIVE continue to increment the event counter but do
not restart or extend the active interval.

When OUTPUT_ACTIVE_CYCLES expires:

    ACTIVE -> IDLE

---

## 7. Output Timer

Required active time:

    500 ms

At 125 MHz:

    OUTPUT_ACTIVE_CYCLES = 62,500,000

Counter-width requirement:

    2^25 = 33,554,432
    2^26 = 67,108,864

Therefore a 26-bit counter is sufficient.

---

## 8. Reset Architecture

The reset architecture shall provide controlled reset release into the
125 MHz clock domain.

All state-holding functional blocks shall return to their specified inactive
state during reset.

Reset architecture details shall be finalized before RTL implementation.

---

## 9. Expected Sequential Resources

Approximate register requirements before synthesis:

    Input synchronizer       2 bits
    Debounced state          1 bit
    Debounce counter        21 bits
    Edge history             1 bit
    Event counter           16 bits
    Controller state       1-2 bits
    Output timer            26 bits
    Reset synchronization   ~2 bits

Expected sequential storage is approximately 70 flip-flops before
implementation optimizations and instrumentation.

---

## 10. Architecture Boundary

The asynchronous input shall only enter the synchronization structure.

Functional logic shall consume event_sync or signals derived from event_sync.

Architectural ordering:

    asynchronous input
        ->
    synchronizer
        ->
    debounce filter
        ->
    edge detector
        ->
    event/control logic

This synchronization boundary is mandatory to prevent asynchronous behavior
from propagating into the functional synchronous architecture.

---

Frank Ouma  
FPGA / SoC / Digital Hardware Engineering  
Email: frankotieno254@gmail.com  
Contact: +254725582132  

Copyright (c) 2026 Frank Ouma. All rights reserved.
