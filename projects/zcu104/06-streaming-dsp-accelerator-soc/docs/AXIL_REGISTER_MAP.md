# Project06 — AXI4-Lite Register Map

## Purpose

Software-visible control and telemetry interface for the
Project06 Streaming DSP Accelerator SoC.

AXI4-Lite data width: 32 bits.

All offsets are relative to the accelerator AXI4-Lite base address.

---

## 0x00 — CONTROL

| Bit | Name | Access | Description |
|---|---|---|---|
| 0 | ENABLE | RW | 1 = accelerator enabled |
| 1 | STATE_CLEAR | W1P | Clear FIR, energy and event history |
| 2 | COUNTER_CLEAR | W1P | Clear telemetry counters |
| 31:3 | RESERVED | - | Write zero |

STATE_CLEAR is only valid while ENABLE = 0.

W1P = write one pulse.

---

## 0x04 — STATUS

| Bit | Name | Access | Description |
|---|---|---|---|
| 0 | ENABLED | RO | Accelerator currently enabled |
| 1 | IDLE | RO | No active streaming transaction |
| 2 | INPUT_ACTIVE | RO | Input stream activity observed |
| 3 | OUTPUT_ACTIVE | RO | Output stream activity observed |
| 31:4 | RESERVED | RO | Zero |

---

## 0x08 — ENERGY_THRESHOLD_LO

Bits [31:0] of the unsigned 37-bit moving-energy threshold.

Access: RW.

---

## 0x0C — ENERGY_THRESHOLD_HI

| Bits | Description |
|---|---|
| 4:0 | Threshold bits [36:32] |
| 31:5 | Reserved / zero |

Access: RW.

Combined threshold:

ENERGY_THRESHOLD = {THRESHOLD_HI[4:0], THRESHOLD_LO[31:0]}

Reset value:

1073741824 decimal = 0x0000000040000000

---

## 0x10 — SAMPLE_COUNT

32-bit accepted-input sample counter.

Increment only when:

S_AXIS_TVALID && S_AXIS_TREADY

Access: RO.

---

## 0x14 — RESULT_COUNT

32-bit accepted-output result counter.

Increment only when:

M_AXIS_TVALID && M_AXIS_TREADY

Access: RO.

---

## 0x18 — EVENT_COUNT

32-bit threshold-event counter.

Increment once for every generated event transferred downstream.

Access: RO.

---

## 0x1C — INPUT_STALL_COUNT

Increment when:

S_AXIS_TVALID && !S_AXIS_TREADY

Access: RO.

---

## 0x20 — OUTPUT_STALL_COUNT

Increment when:

M_AXIS_TVALID && !M_AXIS_TREADY

Access: RO.

---

## Register Semantics

1. Configuration is stable while ENABLE = 1.

2. Software must disable the accelerator and wait for IDLE = 1
   before changing ENERGY_THRESHOLD.

3. STATE_CLEAR is accepted only when ENABLE = 0 and IDLE = 1.

4. STATE_CLEAR clears:
   - FIR sample history
   - moving-energy history
   - moving-energy accumulator
   - event-detector previous-state history

5. STATE_CLEAR does not automatically clear telemetry counters.

6. COUNTER_CLEAR clears:
   - SAMPLE_COUNT
   - RESULT_COUNT
   - EVENT_COUNT
   - INPUT_STALL_COUNT
   - OUTPUT_STALL_COUNT

7. TLAST is transport metadata only.

8. TLAST does not clear DSP state.

9. AXI4-Lite write-address and write-data channels shall be
   handled independently.

10. WSTRB shall be respected for writable registers.

11. Read-only registers shall ignore writes.

12. Reserved bits read as zero.


---

## Enable / Drain / Idle Contract

The accelerator uses drain-to-idle disable semantics.

### ENABLE = 1

- New AXI4-Stream input samples may be accepted.
- All compute stages operate normally.
- Results are produced normally.

### ENABLE transition 1 -> 0

- New input samples stop being accepted.
- Samples already accepted before disable continue through the pipeline.
- Existing results continue to propagate toward the output.
- DSP state is not automatically cleared.

### IDLE

IDLE becomes 1 only when:

- ENABLE = 0, and
- there are no accepted samples still awaiting an output result.

One accepted input sample corresponds to exactly one output result.

### Safe software reconfiguration sequence

1. Write ENABLE = 0.
2. Poll STATUS.IDLE until IDLE = 1.
3. Change ENERGY_THRESHOLD if required.
4. Issue STATE_CLEAR if a clean DSP history is required.
5. Issue COUNTER_CLEAR if a new measurement window is required.
6. Write ENABLE = 1.

Threshold writes while ENABLE = 1 or IDLE = 0 shall be ignored.

STATE_CLEAR while ENABLE = 1 or IDLE = 0 shall be ignored.

COUNTER_CLEAR may be issued while enabled or disabled.
If a counter increment and COUNTER_CLEAR occur in the same clock cycle,
COUNTER_CLEAR takes precedence.
