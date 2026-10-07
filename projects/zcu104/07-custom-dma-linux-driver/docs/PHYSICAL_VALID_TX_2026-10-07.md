# Project 07 — Physical Valid TX DMA Transfer

Date: 2026-10-07
Platform: AMD/Xilinx ZCU104

## Objective

Prove that the authored Project 07 DMA can execute a valid TX descriptor,
read payload data from DDR through the custom AXI4 master, retire the
descriptor correctly, and generate a real completion interrupt.

## Test Setup

Descriptor address:

    0x10000000

Payload address:

    0x10001000

Payload length:

    64 bytes

Descriptor CONTROL before execution:

    OWN = 1
    IRQ_ON_COMPLETION = 1
    EOP = 1

CONTROL word:

    0x00000007

## Physical Results

Observed:

    TX_HEAD       = 0x00000001
    TX_TAIL       = 0x00000001
    IRQ_STATUS    = 0x00000001
    IRQ_ENABLE    = 0x00000001
    ERROR_STATUS  = 0x00000000
    ERROR_INFO    = 0x00000000

Descriptor after DMA:

    LENGTH        = 0x00000040
    CONTROL       = 0x00000006
    STATUS        = 0x00000001
    ACTUAL_LENGTH = 0x00000040

Interpretation:

- OWN cleared from 1 to 0
- STATUS COMPLETE set
- ACTUAL_LENGTH = 64 bytes
- HW_HEAD advanced from 0 to 1
- no DMA error reported
- TX completion interrupt generated

ZynqMP GIC raw interrupt:

    F9010D0C = 0x02000000

This confirms PL interrupt propagation to SPI121.

## Physical Path Proven

DDR descriptor
-> custom AXI4 master
-> descriptor engine
-> TX engine
-> DDR payload read
-> AXI4-Stream TX sink
-> descriptor STATUS writeback
-> OWN clear
-> HW_HEAD advancement
-> completion IRQ
-> ZynqMP GIC SPI121

## Conclusion

Physical valid TX DMA execution: PASS.

The authored Project 07 DMA successfully executed and retired a valid
descriptor and generated a real completion interrupt.

## Not Yet Physically Proven

- visual observation of individual AXI4-Stream payload words
- RX payload write to DDR
- multi-descriptor ring operation
- ring wrap
- concurrent TX/RX operation
- Linux driver operation

## Next Gate

Expose the physical TX AXI4-Stream payload so the actual DDR payload words
can be observed directly during hardware execution.
