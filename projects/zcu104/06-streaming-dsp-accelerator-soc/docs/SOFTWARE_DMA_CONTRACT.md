# Project06 — Cortex-A53 / Scatter-Gather DMA Software Contract

## Hardware Platform

Board: AMD ZCU104
Processor: Cortex-A53
PL clock: 150 MHz

Accelerator AXI4-Lite base:
0xA0000000

AXI DMA AXI4-Lite base:
0xA0010000

DMA mode:
Scatter-Gather

DMA memory interfaces:
- M_AXI_MM2S -> DDR
- M_AXI_S2MM -> DDR
- M_AXI_SG -> DDR

DMA stream interfaces:
- MM2S output: 16 bits
- S2MM input: 64 bits

DRE:
- MM2S disabled
- S2MM disabled

---

## Accelerator Input Format

One input sample:

signed 16-bit Q1.15

N samples:

2 * N bytes

Source data is stored in DDR.

---

## Accelerator Output Format

One result:

64 bits

Bits:
- [15:0]  filtered FIR sample
- [52:16] unsigned 37-bit moving energy
- [53]    threshold event
- [63:54] reserved

N results:

8 * N bytes

---

## TLAST

TLAST is a transport / DMA packet boundary only.

TLAST does not reset:
- FIR history
- moving-energy history
- energy accumulator
- event history

DSP state remains continuous across SG descriptors.

---

## Accelerator Software Sequence

1. Disable accelerator.
2. Poll STATUS.IDLE until IDLE = 1.
3. Program ENERGY_THRESHOLD.
4. Issue STATE_CLEAR when a fresh DSP history is required.
5. Issue COUNTER_CLEAR when beginning a new measurement window.
6. Prepare source data in DDR.
7. Prepare MM2S and S2MM SG descriptor rings.
8. Flush CPU cache for all memory that DMA will read.
9. Arm S2MM before MM2S.
10. Enable accelerator.
11. Start DMA descriptor rings.
12. Wait for DMA completion using interrupts.
13. Invalidate CPU cache for DMA-written result buffers.
14. Validate FPGA results against the software reference.
15. Disable accelerator.
16. Poll until IDLE = 1.
17. Read accelerator telemetry counters.

---

## DMA Memory Rules

SG descriptors, source buffers and result buffers shall reside in DDR.

Do not deliberately place DMA buffers in:
- QSPI address space
- OCM address space

Because DMA DRE is disabled, buffers shall use conservative aligned
allocation.

Baseline software shall use at least 64-byte alignment for:
- MM2S source buffers
- S2MM result buffers
- SG descriptor-ring memory

Transfer sizes shall also respect the natural stream element sizes.

---

## Cache Coherency

The Cortex-A53 data cache is not assumed hardware-coherent with this DMA path.

Before DMA reads CPU-written memory:
- flush source buffers
- flush descriptor memory as required by the driver/runtime

After DMA writes result memory:
- invalidate result-buffer cache lines before CPU access

Descriptor ownership transitions shall follow the Xilinx AXI DMA SG driver
requirements.

---

## Interrupts

DMA MM2S and S2MM interrupts are connected through PL interrupt aggregation
to the Zynq UltraScale+ GIC.

Exact interrupt IDs shall be taken from the generated BSP / XSA, not guessed.

---

## Numerical Validation

The hardware result shall be compared against the same fixed-point algorithm
used by:

model/dsp_reference.py

Comparison is exact integer comparison.

Do not compare FPGA fixed-point results against an unrelated floating-point
implementation.

---

## Performance Benchmark

The benchmark compares:

1. Cortex-A53 scalar fixed-point implementation
2. FPGA streaming accelerator

Both shall process the same algorithm and same input vectors.

Measurements shall report separately:
- pure A53 computation time
- DMA setup time
- FPGA transfer + compute completion time
- sustained streaming throughput
- end-to-end acceleration

No acceleration claim is made until measured on physical ZCU104 hardware.
