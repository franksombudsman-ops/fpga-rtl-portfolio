# Project 06 — Accelerator Architecture Contract

## Functional Path

AXI4-Stream input
        |
        v
Input flow-control stage
        |
        v
32-sample history
        |
        v
32 parallel signed multipliers
        |
        v
pipelined balanced adder tree
        |
        v
37-bit FIR accumulator
        |
        v
round + saturate
        |
        +------------------------+
        |                        |
        v                        v
filtered output            square / energy
                                 |
                                 v
                         64-sample moving energy
                                 |
                                 v
                         threshold/event detector
        |                        |
        +------------+-----------+
                     |
                     v
              result formatter
                     |
                     v
             AXI4-Stream output

## FIR Datapath

The first implementation shall favor a genuinely parallel architecture.

Thirty-two coefficient/sample products shall be available concurrently.

A balanced reduction structure shall be used rather than a long serial
combinational addition chain.

This project shall demonstrate hardware parallelism rather than a
software-style sequential MAC loop.

## Flow-Control Rule

The datapath must remain correct under arbitrary legal AXI4-Stream stalls.

No sample may be:

- duplicated;
- silently discarded;
- reordered;
- recomputed against the wrong sample history.

The implementation shall explicitly track validity through the pipeline.

## Configuration

AXI4-Lite shall configure:

- accelerator enable;
- bypass;
- coefficient shadow bank;
- coefficient commit;
- energy threshold;
- event controls;
- counter clear;
- interrupt controls where used.

AXI4-Lite shall expose:

- accelerator status;
- active configuration state;
- samples accepted;
- samples produced;
- input stall cycles;
- output stall cycles;
- saturation count;
- event count;
- error/status flags.

## DMA Integration

DMA integration is deliberately outside the arithmetic core.

The standalone accelerator shall first pass self-checking simulation.

Only after the datapath contract passes verification shall it be integrated
with:

    DDR → SG DMA MM2S → accelerator → SG DMA S2MM → DDR

This keeps arithmetic bugs separate from SoC integration bugs.

## Physical Validation

Two validation sources shall eventually be supported:

1. deterministic DDR-resident vectors for exact numerical/performance tests;
2. live Pmod AD1 analog data for physical bench demonstration.

The deterministic vector path is authoritative for numerical benchmarking.

The live AD1 path demonstrates physical real-world operation.

## Design Culture

Project06 follows:

Specification
→ numerical contract
→ microarchitecture
→ reference model
→ RTL
→ self-checking verification
→ synthesis
→ implementation
→ timing/CDC/methodology
→ bitstream
→ physical hardware
→ evidence
→ documentation
→ exact Git commit/push verification.
