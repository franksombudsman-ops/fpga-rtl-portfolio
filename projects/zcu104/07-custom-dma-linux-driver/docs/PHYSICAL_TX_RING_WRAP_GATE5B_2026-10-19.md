# Project 07 — Gate 5B Physical TX Ring Wrap Validation

**Result: PASS**

Platform: ZCU104  
Toolchain: Vivado / XSDB 2023.2

## Purpose

Prove descriptor-ring wrap-around across the final physical slot of a
16-entry ring.

Initial logical state:

- HW_HEAD = 15
- SW_TAIL = 15

Three descriptors were then published:

- Logical descriptor 15 -> physical slot 15
- Logical descriptor 16 -> physical slot 0
- Logical descriptor 17 -> physical slot 1

## Physical result

All three descriptors retired successfully.

Each descriptor completed with:

- CONTROL = 0x00000006
- STATUS = 0x00000001
- ACTUAL_LENGTH = 0x00000040

Final state:

- HW_HEAD = 18
- SW_TAIL = 18
- TX completion IRQ = asserted
- ERROR_STATUS = 0
- ERROR_INFO = 0

## Conclusion

The custom DMA descriptor ring physically crossed the 15 -> 0 boundary
while preserving monotonically increasing logical HEAD/TAIL indices.

**PHYSICAL GATE 5B: PASS**
