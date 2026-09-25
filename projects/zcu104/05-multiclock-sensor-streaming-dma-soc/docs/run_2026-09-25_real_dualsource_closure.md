# Project 05 — Real Dual-Source Hardware Integration Closure

Date: 2026-09-25  
Platform: AMD/Xilinx ZCU104

## Architecture Validated

Real Pmod AD1 + Real MPU6050
→ independent AXI4-Stream packetizers
→ packet-safe 2:1 AXI4-Stream arbiter
→ asynchronous AXI4-Stream CDC FIFO
→ AXI DMA S2MM
→ DDR
→ Cortex-A53

## Implementation Closure

Internal FPGA implementation timing was closed before hardware validation.

- WNS: +5.121 ns
- TNS: 0
- WHS: +0.010 ns
- THS: 0
- WPWS: +3.500 ns
- TPWS: 0
- Unconstrained internal endpoints: 0
- CDC unsafe/unknown crossings: 0
- Bus-skew constraints: MET
- Bitstream generation: 0 errors, 0 critical warnings

Formal board-level external timing for MPU6050 I2C and AD1 CS_N is outside the current timing claim.

## Real Sensor Liveness

Hardware ILA validation confirmed:

- MPU6050 wake: PASS
- MPU6050 WHO_AM_I: PASS
- MPU6050 I2C activity: PASS
- MPU6050 transaction completion: PASS
- MPU6050 live motion frames: PASS
- Pmod AD1 sample_valid: PASS
- Pmod AD1 sample_tick: PASS

## Final A53 End-to-End Validation

Observed hardware result:

- AD1 packets verified: 341
- MPU6050 packets verified: 8
- Unknown packets: 0
- Framing errors: 0
- AD1 format errors: 0
- MPU format errors: 0
- AD1 sequence errors: 0
- MPU sequence errors: 0
- AD1 live-data variation: PASS
- MPU live-data variation: PASS
- Packet-boundary integrity: PASS
- AD1 sequence integrity: PASS
- MPU sequence integrity: PASS

Final result:

**Dual-real-source arbitration: PASS**

**AD1 + MPU6050 → Arbiter → CDC → DMA → DDR → A53: PASS**

The different packet counts reflect different source rates and the software stopping after the MPU target was achieved. Equal-bandwidth arbitration is not claimed.

## Sustained-Throughput Characterization

A separate characterization run kept the A53 Simple-DMA receiver active while source-side drop counters were sampled approximately 11 seconds apart.

MPU6050:
- Snapshot A: 0x0002EE34
- Snapshot B: 0x0002F1E2
- Increase: 942 frames

AD1:
- Snapshot A: 0x0159781F
- Snapshot B: 0x015B29ED
- Increase: 111054 samples

Both overflow-sticky indicators were asserted.

This establishes a sustained-throughput/backpressure limitation in the present Simple-DMA / CPU re-arm architecture.

It does not invalidate the accepted-packet end-to-end validation: received packets showed zero unknown headers, framing errors, format errors, or sequence discontinuities.

## Closure Statement

This Project05 run is CLOSED as a successful real dual-source hardware integration milestone.

Proven:
- two independent physical sensor sources;
- real MPU6050 replacing the synthetic second source;
- packet-safe mixed-source transport;
- asynchronous clock-domain crossing;
- AXI DMA S2MM transport;
- DDR delivery;
- Cortex-A53 source identification;
- independent packet sequence integrity;
- live physical data variation;
- zero observed corruption among accepted packets.

Not claimed:
- lossless sustained capture of every raw source event;
- equal arbitration bandwidth;
- formal external board-level timing closure for MPU6050 I2C and AD1 CS_N.

The sustained-streaming limitation is explicitly characterized and becomes an architectural improvement target for later work such as buffered/ring or scatter-gather DMA rather than a blocker to this integration milestone.
