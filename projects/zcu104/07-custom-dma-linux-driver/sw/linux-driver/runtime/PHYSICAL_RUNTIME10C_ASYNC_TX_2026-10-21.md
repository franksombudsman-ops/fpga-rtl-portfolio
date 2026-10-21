# Project 07 — Phase 10C Physical Asynchronous TX Validation

## Result

PASS

Phase 10C physically validated asynchronous runtime TX submission
with threaded IRQ-driven, HW_HEAD-authoritative descriptor reclaim.

## Idle boot

Before runtime DMA activity the driver initialized with:

    tx_prod=0
    tx_clean=0
    tx_head=0
    tx_bytes=0
    tx_desc=0

    rx_prod=0
    rx_clean=0
    rx_head=0

    irq_count=0
    irq_seen=0x00000000
    error_status=0x00000000

No DMA transaction occurred during probe.

## Runtime architecture

TX submission:

    descriptor prepared
        ->
    OWN published
        ->
    dma_wmb()
        ->
    logical TX_TAIL advanced
        ->
    submission returns without synchronous completion wait

Completion:

    hardware raises TX completion IRQ
        ->
    hard IRQ acknowledges RW1C cause
        ->
    threaded IRQ executes
        ->
    HW_HEAD read
        ->
    dma_rmb()
        ->
    descriptor writeback validated
        ->
    tx_clean advanced

## Physical runtime transaction 1

Submission:

    logical=0
    slot=0
    tx_prod=1
    tx_clean=0
    tail=1

Threaded completion:

    causes=0x00000001
    reclaimed=1
    tx_clean=1
    tx_head=1

## Physical runtime transaction 2

Submission:

    logical=1
    slot=1
    tx_prod=2
    tx_clean=1
    tail=2

Descriptor writeback:

    control=0x00000006
    status=0x00000001
    actual=64
    cookie=0x3130430000000001

Threaded completion:

    causes=0x00000001
    reclaimed=1
    tx_clean=2
    tx_head=2

Final state:

    tx_prod=2
    tx_clean=2
    tx_head=2
    tx_bytes=128
    tx_desc=2

    irq_count=2
    irq_seen=0x00000001
    error_status=0x00000000

Direct sysfs submission returned:

    WRITE_RC=0

## Validated properties

- persistent TX descriptor ring
- persistent TX payload pool
- no DMA submission during probe
- asynchronous descriptor publication
- monotonically increasing logical producer index
- ring slot selection using logical index mask
- hard-IRQ RW1C acknowledgement
- threaded IRQ completion processing
- HW_HEAD-authoritative reclaim
- descriptor OWN clear and successful writeback
- repeated post-probe runtime operation
- cumulative hardware counters
- zero DMA error status
- no synchronous TX completion wait in submission path

## Conclusion

Phase 10C physically demonstrates separation between descriptor
submission and completion processing. Runtime TX work is published
through the persistent ring while completion and reclaim are performed
independently by the threaded IRQ path using hardware HEAD as the
authoritative retirement point.
