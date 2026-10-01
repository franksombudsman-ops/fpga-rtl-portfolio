# Project 06 — Numerical and Datapath Contract

## 1. Purpose

This document freezes the arithmetic behavior of the Project06 streaming DSP
accelerator before RTL implementation.

The RTL, reference model, testbench and Cortex-A53 software implementation
shall use the same numerical contract.

## 2. Input Representation

Input samples are:

- signed 16-bit two's-complement;
- 15 fractional bits;
- raw integer range: -32768 to +32767;
- represented numerical range: -1.000000 to approximately +0.999969.

Coefficients use the same representation.

## 3. FIR Configuration

Number of taps:

    32

For sample x[n] and coefficient h[k]:

    y[n] = SUM(k=0..31) x[n-k] * h[k]

The first implementation shall be capable of accepting one new sample per
accelerator clock when downstream flow control permits.

## 4. Multiplication

Each multiplication is:

    signed 16-bit × signed 16-bit

The full product is retained as:

    signed 32-bit
    30 fractional bits

No product truncation is permitted before accumulation.

## 5. Accumulator

Thirty-two full-precision products are summed.

The FIR accumulator shall therefore be:

    signed 37-bit
    30 fractional bits

The additional five bits provide the growth required for a 32-term sum.

Intermediate addition shall not silently wrap.

## 6. Output Quantization

The 37-bit accumulator shall be converted to a signed 16-bit output.

The conversion sequence is:

    full-precision accumulator
            ↓
    round to 15 fractional bits
            ↓
    saturation check
            ↓
    signed 16-bit output

Wraparound is prohibited.

Positive overflow shall produce:

    0x7FFF

Negative overflow shall produce:

    0x8000

## 7. Rounding

Baseline rounding behavior:

    round to nearest

The RTL and software reference model shall implement equivalent behavior.

Half-way and negative-number cases shall be explicitly tested.

## 8. Sample Delay Architecture

The FIR shall retain the previous 31 accepted samples plus the current
accepted sample.

The sample history advances only when an AXI4-Stream input transfer occurs:

    S_AXIS_TVALID && S_AXIS_TREADY

Backpressure must not alter sample history.

## 9. Pipeline Architecture

The datapath shall be pipelined.

Target:

    initiation interval = 1 accepted sample / clock

The implementation may use:

- registered multiplier outputs;
- balanced pipelined addition tree;
- registered quantization;
- registered result output.

Exact verified latency shall be recorded after RTL implementation.

Latency and throughput are separate requirements.

A pipeline may have multiple cycles of latency while still accepting one
sample every clock.

## 10. AXI4-Stream Stall Semantics

If the downstream consumer cannot accept an output, the accelerator shall
not corrupt or reorder samples.

Pipeline control shall preserve:

- sample data;
- TVALID;
- TLAST;
- associated metadata.

Input TREADY shall respond correctly to pipeline capacity.

The design shall never advance data merely because TVALID is asserted.

Transfers occur only on:

    TVALID && TREADY

## 11. Packet Boundary Metadata

TLAST shall travel through the accelerator with the corresponding sample.

Computation shall never change packet ordering or packet boundaries.

## 12. Moving Energy

The post-FIR path shall calculate a moving energy metric over:

    64 filtered samples

For filtered sample y[n]:

    energy_sample[n] = y[n] * y[n]

The moving metric is:

    E[n] = SUM(i=0..63) y[n-i]^2

A square-root operation is not required.

This is signal energy, not RMS.

Internal width shall preserve sufficient precision to prevent silent
overflow over the defined operating range.

The exact energy accumulator width shall be verified mathematically before
implementation.

## 13. Peak / Event Detection

A programmable unsigned energy threshold shall be provided.

An event is generated when the moving-energy value crosses the configured
threshold according to the final control contract.

Event behavior shall avoid generating uncontrolled repeated events while the
signal remains continuously above threshold.

Exact hysteresis/event semantics shall be frozen before the event RTL is
implemented.

## 14. Coefficients

Thirty-two coefficients shall be programmable.

A coefficient update must not silently create a filter in which part of one
sample is computed using old coefficients and another part using new
coefficients.

The architecture shall therefore provide defined coefficient-update
semantics.

The preferred implementation is:

    shadow coefficient bank
            ↓
    explicit COMMIT command
            ↓
    atomic active-bank update

The final register map shall define this precisely.

## 15. Required Arithmetic Verification

The self-checking environment shall include at minimum:

- zero input;
- positive impulse;
- negative impulse;
- step input;
- alternating maximum/minimum input;
- positive full scale;
- negative full scale;
- positive saturation;
- negative saturation;
- rounding boundaries;
- random signed samples;
- random legal coefficients;
- long continuous streams;
- randomized output backpressure.

Expected results shall come from a bit-accurate reference model implementing
this same contract.

## 16. Performance Target

Initial implementation target:

    accelerator clock = 150 MHz
    initiation interval = 1 sample/clock

Therefore the theoretical arithmetic acceptance capability at full rate is:

    150 million samples/second

This is an architectural target, not a claimed measured result.

Final documentation shall contain measured hardware throughput.

## 17. Frozen Rounding Tie Rule

The Project06 rounding mode is:

    round to nearest, ties away from zero

For conversion from the 30-fraction-bit FIR accumulator to Q1.15:

Positive values:

    rounded = (accumulator + 2^14) >> 15

Negative values:

    rounded = -(((-accumulator) + 2^14) >> 15)

This definition shall be used identically by:

- Python reference model;
- SystemVerilog RTL;
- testbench scoreboard;
- Cortex-A53 software reference implementation.

## 18. Frozen Moving-Energy Width

A signed Q1.15 filtered output has raw magnitude up to 32768.

Maximum squared raw value:

    32768^2 = 2^30

For a 64-sample energy window:

    64 × 2^30 = 2^36

Therefore the moving-energy accumulator shall be:

    unsigned 37-bit

No silent energy accumulator overflow is permitted.

## 19. Frozen Event Semantics

The baseline hardware event is a threshold-crossing event.

An event shall be generated once when:

    previous_energy < threshold
    current_energy  >= threshold

The detector shall not repeatedly generate events while energy remains above
threshold.

The detector rearms only after:

    current_energy < threshold

This creates one event for each below-to-above threshold excursion.
