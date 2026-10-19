# Project 07 — Gate 7B Corrected Physical TX/RX Concurrency

**Result: PASS**

Platform: ZCU104  
Toolchain: Vivado / XSDB 2023.2  
RTL freeze: 4f5a314d93e851102f551600de476f1cf9cb372a  
Corrected BIT SHA256:
2f46cd683775a50f5d019ae1d67eab2c4cd6f23e0b26faa76483824b1c07a31d

## Purpose

Validate the corrected read/write arbiters in the physical FPGA image
under simultaneous pending TX and RX DMA work.

Both TX and RX channels were enabled before one common global-enable
write.

## Physical result

TX descriptor:
- CONTROL = 0x00000006
- STATUS = 0x00000001
- ACTUAL_LENGTH = 0x00000040

RX descriptor:
- CONTROL = 0x00000006
- STATUS = 0x00000001
- ACTUAL_LENGTH = 0x00000040

Final state:
- TX_HEAD = 1
- RX_HEAD = 1
- IRQ_STATUS = 0x00000003
- ERROR_STATUS = 0
- ERROR_INFO = 0

RX DDR payload matched the deterministic 64-byte source exactly:
11111111 through 12345678.

## Validation boundary

This physically validates simultaneous bidirectional DMA operation
using the corrected arbiter RTL.

The adversarial request-stability condition in which a higher-priority
request arrives while shared VALID is stalled by READY=0 was validated
separately in XSIM.

**PHYSICAL GATE 7B: PASS**
