# Project 07 — Phase 10F Physical Runtime Qualification

## Result

PASS

Phase 10F physically validated the final runtime TX/RX character-device
datapath on ZCU104.

Runtime device:

    /dev/project07-dma

## Runtime10F interface

The driver exposes:

- 64-byte TX through write()
- 64-byte RX through read()
- persistent coherent TX and RX descriptor rings
- driver-owned coherent TX/RX payload buffers
- threaded interrupt completion/reclaim
- HW_HEAD-authoritative descriptor retirement
- GET_INFO ioctl
- GET_STATS ioctl
- RESET ioctl
- automatic hardware-error recovery

The temporary Runtime10E runtime_recover sysfs trigger was removed.

Physical validation confirmed:

    runtime_recover absent

## Initial state

The runtime booted with:

    tx_prod=0
    tx_clean=0
    tx_head=0
    tx_bytes=0
    tx_desc=0

    rx_prod=0
    rx_clean=0
    rx_head=0
    rx_bytes=0
    rx_desc=0
    rx_pending=0

    irq_count=0
    irq_seen=0x00000000

    error_status=0x00000000
    faulted=0

## Physical userspace RX

Userspace issued one read from:

    /dev/project07-dma

The driver posted:

    logical=0
    slot=0
    rx_prod=1
    rx_clean=0
    tail=1
    bytes=64

Hardware completed the descriptor with:

    control=0x00000006
    status=0x00000001
    actual=64
    cookie=0x3130460000000000

The FPGA generated RX completion IRQ cause:

    0x00000002

Threaded IRQ reclaim advanced:

    rx_clean=1
    rx_head=1

The driver then delivered exactly 64 bytes to userspace.

RX read return:

    RX_RC=0

Output file size:

    64 bytes

## Physical RX payload

The exact userspace-visible 32-bit words were:

    11111111 22222222 33333333 44444444
    55555555 66666666 77777777 88888888
    99999999 aaaaaaaa bbbbbbbb cccccccc
    dddddddd eeeeeeee ffffffff 12345678

Raw byte representation:

    11 11 11 11 22 22 22 22
    33 33 33 33 44 44 44 44
    55 55 55 55 66 66 66 66
    77 77 77 77 88 88 88 88
    99 99 99 99 aa aa aa aa
    bb bb bb bb cc cc cc cc
    dd dd dd dd ee ee ee ee
    ff ff ff ff 78 56 34 12

This exactly matches the deterministic physical AXI4-Stream RX source
implemented in the current Project07 validation FPGA wrapper.

## RX state after userspace delivery

    rx_prod=1
    rx_clean=1
    rx_head=1
    rx_bytes=64
    rx_desc=1
    rx_pending=0

    irq_count=1
    irq_seen=0x00000002

    error_status=0x00000000
    faulted=0

## TX after RX

A 64-byte userspace TX was then issued through the same character device.

TX return:

    TX_RC=0

Hardware completed and IRQ/HW_HEAD reclaim produced:

    tx_prod=1
    tx_clean=1
    tx_head=1
    tx_bytes=64
    tx_desc=1

## Final combined runtime state

    tx_prod=1
    tx_clean=1
    tx_head=1
    tx_bytes=64
    tx_desc=1

    rx_prod=1
    rx_clean=1
    rx_head=1
    rx_bytes=64
    rx_desc=1
    rx_pending=0

    irq_count=2
    irq_seen=0x00000003

    error_status=0x00000000
    faulted=0

    recovery_count=0
    recovery_failures=0
    recovery_dropped_tx=0
    recovery_dropped_rx=0

IRQ history:

    bit 0 = TX completion
    bit 1 = RX completion

    irq_seen = 0x00000003

## Validated properties

- real Linux userspace RX read()
- driver-owned coherent RX payload buffer
- RX descriptor publication
- FPGA AXI4-Stream to DDR DMA
- exact payload correctness
- RX completion interrupt
- threaded RX IRQ handling
- HW_HEAD-authoritative RX reclaim
- copy_to_user userspace delivery
- RX byte and descriptor counters
- TX operation after completed RX
- TX completion interrupt
- TX HW_HEAD reclaim
- simultaneous lifetime TX/RX IRQ history
- zero hardware error status
- zero runtime fault state
- zero recovery failures
- temporary Runtime10E recovery sysfs interface removed

## Current FPGA validation-source limitation

The current physical FPGA wrapper contains a deterministic one-packet
AXI4-Stream RX source used for Project07 physical qualification.

It emits one 64-byte packet per custom-core reset.

Therefore this Phase 10F qualification proves the Linux RX runtime,
descriptor handling, DMA write path, IRQ handling, HW_HEAD reclaim, and
userspace delivery.

It does not claim that the validation wrapper is a continuous production
AXI4-Stream source.

## Conclusion

Phase 10F physically demonstrates a bidirectional Linux runtime interface:

    userspace write()
        -> TX descriptor
        -> DDR-to-AXI-Stream DMA
        -> TX IRQ
        -> HW_HEAD reclaim

and:

    userspace read()
        -> RX descriptor
        -> AXI-Stream-to-DDR DMA
        -> RX IRQ
        -> HW_HEAD reclaim
        -> copy_to_user()

Both directions completed successfully on the physical ZCU104 with exact
RX payload correctness and zero reported DMA errors.
