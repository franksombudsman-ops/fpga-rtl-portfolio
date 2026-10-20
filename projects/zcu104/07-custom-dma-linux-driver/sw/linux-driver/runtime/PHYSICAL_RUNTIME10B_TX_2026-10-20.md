# Project 07 — Phase 10B Physical Runtime TX Validation

## Result

PASS

Phase 10B physically validated post-probe TX submission and
HW_HEAD-authoritative reclaim using the persistent runtime ring.

## Boot / idle state

Before any runtime transaction:

    tx_prod=0
    tx_clean=0
    tx_head=0
    tx_bytes=0
    tx_desc=0
    irq_count=0
    irq_seen=0x00000000
    error_status=0x00000000

No DMA transaction occurred during probe.

## First runtime TX

Submission:

    logical=0
    slot=0
    tx_prod=1
    tx_clean=0
    tail=1

Hardware retirement / software reclaim:

    logical=0
    slot=0
    control=0x00000006
    status=0x00000001
    actual=64
    cookie=0x3130420000000000

Final state:

    tx_prod=1
    tx_clean=1
    tx_head=1
    tx_bytes=64
    tx_desc=1
    irq_count=1
    error_status=0x00000000

## Second runtime TX

A second independent post-probe runtime transaction was executed
without reboot, FPGA reprogramming, driver reload, or ring
reallocation.

Submission:

    logical=1
    slot=1
    tx_prod=2
    tx_clean=1
    tail=2

Hardware retirement / software reclaim:

    logical=1
    slot=1
    control=0x00000006
    status=0x00000001
    actual=64
    cookie=0x3130420000000001

Final state:

    tx_prod=2
    tx_clean=2
    tx_head=2
    tx_bytes=128
    tx_desc=2
    irq_count=2
    irq_seen=0x00000001
    error_status=0x00000000

Direct sysfs write returned:

    WRITE_RC=0

## Validated runtime properties

- persistent coherent TX descriptor ring
- persistent coherent TX payload pool
- no DMA submission during probe
- monotonically increasing logical producer index
- physical slot selection by ring mask
- descriptor publication after dma_wmb()
- interrupt-driven completion notification
- HW_HEAD-authoritative descriptor reclaim
- descriptor OWN clear and successful writeback
- persistent ring reuse across multiple runtime submissions
- cumulative hardware byte and descriptor counters
- zero DMA error status

## Conclusion

Phase 10B physically demonstrates that the Project 07 Linux runtime
driver can submit and reclaim TX descriptors after probe using a
persistent descriptor ring rather than a temporary boot-time
validation ring.
