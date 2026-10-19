# Project 07 — Gate 8E Physical Performance Counters

**Result: PASS**

Platform: AMD ZCU104  
RTL freeze:
c236100a3138dddd5bc90dcf446f16f801d6a5d9

Counter-enabled BIT SHA256:
75eeaab6538a3d511e62db7e9d4b5b033f4081876ac31e090dade46c5b0943c2

## Physical DMA completion

TX descriptor:
- CONTROL = 0x00000006
- STATUS = 0x00000001
- ACTUAL_LENGTH = 0x00000040

RX descriptor:
- CONTROL = 0x00000006
- STATUS = 0x00000001
- ACTUAL_LENGTH = 0x00000040

Completion state:
- TX_HEAD = 1
- RX_HEAD = 1
- IRQ_STATUS = 0x00000003
- ERROR_STATUS = 0
- ERROR_INFO = 0

## Physical performance counters

TX:
- bytes = 0x40 (64)
- descriptor count = 1
- active cycles = 0xDA (218)
- AXI stall cycles = 0x24 (36)
- AXIS stall cycles = 0

RX:
- bytes = 0x40 (64)
- descriptor count = 1
- active cycles = 0xF7 (247)
- AXI stall cycles = 0x05 (5)
- AXIS stall cycles = 0x55 (85)

## Counter clear

Software COUNTER_CLEAR was issued through GLOBAL_CONTROL.

After clear:
- TX bytes = 0
- TX descriptor count = 0
- TX active cycles = 0
- RX bytes = 0
- RX descriptor count = 0
- RX active cycles = 0

## Implementation signoff

- WNS = +4.761 ns
- TNS = 0
- WHS = +0.013 ns
- THS = 0
- WPWS = +3.500 ns
- TPWS = 0
- All specified timing constraints met
- Bus-skew constraints met
- DRC: 0 errors, 7 known generated-IP/debug warnings

**PHYSICAL GATE 8E: PASS**
