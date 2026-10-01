# Project 06 — Microarchitecture

## Top-Level Functional Pipeline

AXI4-Stream input
→ input skid/register stage
→ sample unpack/sign extension
→ 32-tap FIR pipeline
→ rounding/saturation
→ moving-energy pipeline
→ programmable peak detection
→ result formatter
→ AXI4-Stream output

## Architectural Principles

1. AXI handshaking controls acceptance of new samples.
2. Backpressure shall never corrupt pipeline state.
3. Arithmetic widths shall be explicit.
4. Signedness shall be explicit.
5. No silent truncation.
6. Saturation behavior shall be deterministic.
7. Pipeline latency shall be documented and verified.
8. Initiation interval target is one sample per clock.
9. Configuration changes shall have defined application semantics.
10. Datapath telemetry shall expose enough state for performance diagnosis.

## Major Blocks

- `axis_input_stage`
- `fir32_pipeline`
- `moving_energy`
- `peak_detector`
- `axis_result_formatter`
- `accelerator_control_axi`
- `performance_counters`

## Verification Boundary

The DSP core shall first be verified independently from PS/DMA integration.

Integration shall proceed only after arithmetic and AXI4-Stream behavior are
self-checking and repeatable.
