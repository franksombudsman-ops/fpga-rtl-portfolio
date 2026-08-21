# Deterministic Event & Control Engine
## Engineering Specification

**Project:** ZCU104-01  
**Platform:** AMD ZCU104 — Zynq UltraScale+ MPSoC  
**RTL:** SystemVerilog  
**Toolchain:** AMD Vivado 2023.2  
**Author:** Frank Ouma  
**Engineering Contact:** frankotieno254@gmail.com  
**Contact:** +254725582132  
**Copyright:** Copyright (c) 2026 Frank Ouma. All rights reserved.

---

## 1. Purpose

The Deterministic Event & Control Engine is a synchronous digital hardware
controller designed to acquire an asynchronous physical input, reject
electrical or mechanical instability, identify qualified events, maintain
event state, and generate precisely timed hardware responses.

The design provides a reusable control architecture applicable to physical
switches, digital sensors, relay contacts, limit switches, interrupt sources,
fault inputs, and other asynchronous external events.

---

## 2. Engineering Objectives

The design shall:

- safely acquire an asynchronous single-bit external input;
- reduce metastability propagation through an input synchronization stage;
- reject mechanical switch bounce and short-duration disturbances;
- generate exactly one qualified event for one valid physical activation;
- prevent a continuously asserted input from generating repeated events;
- maintain a hardware event count;
- generate a deterministic timed output response;
- provide defined behavior when events occur during an active output period;
- recover to a defined state following reset;
- support simulation, synthesis, timing analysis, FPGA implementation,
  embedded instrumentation, and physical hardware validation.

---

## 3. System Clock

Nominal system clock frequency:

    125 MHz

Nominal clock period:

    8 ns

All control logic following the asynchronous input synchronization boundary
shall operate synchronously from the system clock.

The final physical clock package-pin assignment and clock constraint shall be
verified against the official ZCU104 board documentation before implementation.

---

## 4. External Inputs

### 4.1 Event Input

Signal:

    event_async

The event input is an asynchronous physical signal and shall not be consumed
directly by the synchronous control logic.

The initial physical implementation will use an active-high pushbutton input.

Logical interpretation:

    LOW  = inactive
    HIGH = physical event request

### 4.2 Reset Input

Signal:

    reset_async

Reset shall place the complete design into a defined inactive condition.

Reset handling shall provide controlled release into the system clock domain.

---

## 5. Input Synchronization

The asynchronous event input shall pass through a minimum two-stage register
synchronizer before entering the functional control logic.

Synchronizer registers shall be identified appropriately for the FPGA
implementation tools so that the synchronization structure is preserved and
placed for improved metastability reliability.

The synchronizer does not perform mechanical debounce.

---

## 6. Debounce Requirement

The synchronized input shall not change the qualified input state until the
candidate input level has remained continuously stable for:

    DEBOUNCE_TIME = 10 ms

At a 125 MHz system clock this corresponds to:

    DEBOUNCE_CYCLES = 1,250,000 clock cycles

If the candidate input changes before the debounce interval completes, the
debounce timing process shall restart.

Both assertion and release shall be qualified.

---

## 7. Event Qualification

A qualified event shall be generated only when the debounced input makes a
validated LOW-to-HIGH transition.

The resulting internal event pulse shall:

- be synchronous to the system clock;
- remain asserted for exactly one system clock cycle;
- occur only once for a continuous physical button press.

A new event shall not be generated until the physical input has been released,
the release has passed debounce qualification, and another validated
LOW-to-HIGH transition occurs.

---

## 8. Event Counter

A 16-bit event counter shall record qualified events.

Signal:

    event_count[15:0]

The counter shall increment once for every qualified event pulse.

Counter arithmetic shall use modulo-65536 behavior.

Therefore:

    16'hFFFF + one valid event = 16'h0000

Reset shall clear the counter to zero.

---

## 9. Deterministic Output Response

Signal:

    output_active

Each qualified event received while the output controller is idle shall cause
output_active to assert for:

    OUTPUT_ACTIVE_TIME = 500 ms

At a 125 MHz system clock this corresponds to:

    OUTPUT_ACTIVE_CYCLES = 62,500,000 clock cycles

The output duration shall be generated entirely from synchronous clock-based
timing.

---

## 10. Events During Active Output

Qualified input events occurring while output_active is already asserted shall:

- continue to increment event_count;
- not restart the output timer;
- not extend the current output-active interval;
- not create a second concurrent output operation.

This defines the initial output controller as a non-retriggerable one-shot
control architecture.

---

## 11. Reset Behavior

Following reset:

    qualified input state = inactive
    event pulse           = 0
    event count           = 0
    output_active         = 0
    control state         = idle
    timing counters       = 0

Reset during an active output operation shall immediately terminate the active
operation and return the controller to its defined reset state.

Reset release shall be synchronized before normal state-machine operation
resumes.

---

## 12. Parameterization

The RTL architecture shall avoid embedding unexplained fixed timing constants.

The design shall expose or internally define parameters representing at least:

    CLK_FREQ_HZ
    DEBOUNCE_TIME_MS
    OUTPUT_ACTIVE_TIME_MS
    EVENT_COUNT_WIDTH
    SYNCHRONIZER_STAGES

Clock-cycle counts and required register widths shall be derived from these
engineering parameters where practical.

---

## 13. Verification Requirements

The verification environment shall test at minimum:

- reset and reset recovery;
- clean button assertion and release;
- mechanical-style input bounce;
- glitches shorter than the debounce interval;
- prolonged button assertion;
- prolonged button release;
- multiple valid button presses;
- asynchronous transitions at different positions relative to the clock;
- events occurring while output_active is asserted;
- correct 500 ms output timing;
- correct event-counter operation;
- event-counter rollover;
- reset during an active output event.

Verification shall include automated pass/fail checking rather than relying
only on visual waveform inspection.

---

## 14. FPGA Implementation Requirements

The design shall be synthesizable SystemVerilog.

Implementation shall include:

- clock constraints;
- physical I/O constraints;
- appropriate CDC implementation attributes;
- synthesis;
- place and route;
- static timing analysis;
- utilization analysis;
- bitstream generation.

The design shall achieve timing closure at the defined system clock frequency.

---

## 15. Physical Hardware Validation

Hardware validation shall be performed in two stages.

### Stage A — On-Board Validation

The design shall first be validated using suitable ZCU104 on-board user I/O.

This stage establishes the complete:

    RTL
    -> synthesis
    -> implementation
    -> bitstream
    -> FPGA fabric
    -> physical I/O

development path.

### Stage B — External Hardware Validation

The design shall subsequently interface with external electronics including:

- breadboard;
- jumper wiring;
- mechanical pushbutton;
- defined pull resistor;
- external LED;
- LED current-limiting resistor.

Connector orientation, package-pin assignment, I/O bank voltage, I/O standard,
and electrical limits shall be verified from the ZCU104 board documentation
before external wiring is connected.

---

## 16. Embedded Instrumentation

An Integrated Logic Analyzer implementation shall be used during hardware
validation to observe selected internal signals.

Candidate probes include:

    event_async
    event_sync
    event_debounced
    event_pulse
    output_active
    controller_state
    debounce_counter
    event_count

Physical measurements and ILA observations shall be compared against expected
simulation behavior.

---

## 17. Design Acceptance Criteria

The project is considered functionally complete when:

- one valid physical press creates exactly one qualified event;
- input bounce does not create additional events;
- short disturbances are rejected;
- event counting matches qualified physical events;
- output timing matches the specified deterministic interval;
- reset behavior satisfies this specification;
- synthesis completes successfully;
- implementation completes successfully;
- static timing requirements are met;
- physical hardware behavior agrees with the verified RTL behavior.

---

## 18. Engineering References

Primary device and implementation references include:

- AMD ZCU104 Board User Guide — UG1267
- AMD UltraFast Design Methodology Guide — UG949
- AMD Vivado Design Suite User Guide: Using Constraints — UG903
- AMD UltraScale Architecture Configurable Logic Block User Guide — UG574

---

Frank Ouma  
FPGA / SoC / Digital Hardware Engineering  
Email: frankotieno254@gmail.com  
Contact: +254725582132  

Copyright (c) 2026 Frank Ouma. All rights reserved.
