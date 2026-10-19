# Project 07 — Gate 5A Physical Multi-Descriptor TX Ring Validation

**Result: PASS**

Platform: ZCU104  
Toolchain: Vivado / XSDB 2023.2

## Test

A 16-entry TX descriptor ring was configured with four simultaneously
published 64-byte descriptors.

Initial state:

- HW_HEAD = 0
- SW_TAIL = 4
- Four descriptors had OWN=1
- STATUS = 0
- ACTUAL_LENGTH = 0

## Physical result

All four descriptors retired successfully.

Descriptor 0:
- CONTROL = 0x00000006
- STATUS = 0x00000001
- ACTUAL_LENGTH = 0x00000040

Descriptor 1:
- CONTROL = 0x00000006
- STATUS = 0x00000001
- ACTUAL_LENGTH = 0x00000040

Descriptor 2:
- CONTROL = 0x00000006
- STATUS = 0x00000001
- ACTUAL_LENGTH = 0x00000040

Descriptor 3:
- CONTROL = 0x00000006
- STATUS = 0x00000001
- ACTUAL_LENGTH = 0x00000040

Final state:

- HW_HEAD = 4
- SW_TAIL = 4
- TX completion IRQ = asserted
- ERROR_STATUS = 0
- ERROR_INFO = 0

## Conclusion

Gate 5A physically proves that the custom DMA can consume and retire
multiple TX descriptors from one ring submission.

**PHYSICAL GATE 5A: PASS**
