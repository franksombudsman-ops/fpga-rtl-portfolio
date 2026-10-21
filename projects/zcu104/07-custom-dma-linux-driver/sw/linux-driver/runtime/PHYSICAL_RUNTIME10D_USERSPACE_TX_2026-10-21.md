# Project 07 — Phase 10D Physical Userspace TX Qualification

## Result

PASS

Phase 10D physically validated the real Linux character-device
interface:

    /dev/project07-dma

The temporary runtime_tx_test TX control was removed.

## Userspace ABI validated

A 64-byte userspace write successfully followed:

    userspace
      ->
    write(/dev/project07-dma)
      ->
    copy_from_user()
      ->
    driver-owned coherent TX payload
      ->
    persistent descriptor ring
      ->
    FPGA DMA
      ->
    hardware completion IRQ
      ->
    threaded IRQ
      ->
    HW_HEAD-authoritative reclaim

Userspace does not provide DMA addresses and does not directly access
DMA MMIO.

## Initial transaction

The first userspace transaction completed with:

    logical=0
    slot=0
    tx_prod=1
    tx_clean=1
    tx_head=1
    tx_bytes=64
    tx_desc=1
    irq_count=1
    error_status=0x00000000

## Persistent ring-wrap qualification

Seventeen additional userspace writes were issued successfully.

The critical logical/physical wrap was:

    logical=15 -> slot=15
    logical=16 -> slot=0
    logical=17 -> slot=1

All were reclaimed successfully by the threaded IRQ path.

## Final state

    tx_prod=18
    tx_clean=18
    tx_head=18
    tx_bytes=1152
    tx_desc=18

    rx_prod=0
    rx_clean=0
    rx_head=0

    irq_count=18
    irq_seen=0x00000001
    error_status=0x00000000

Linux IRQ 55 count:

    18

No Runtime10D FAIL messages or TX IRQ errors were observed.

## Validated properties

- real /dev/project07-dma character device
- userspace write() TX submission
- copy_from_user() path
- driver-owned coherent DMA payload memory
- persistent descriptor ring
- asynchronous TX publication
- threaded IRQ completion
- HW_HEAD-authoritative reclaim
- monotonically increasing logical producer index
- logical-to-physical ring wrap
- repeated post-probe operation
- cumulative hardware counters
- zero DMA error status
- no userspace DMA addresses
- no temporary runtime_tx_test dependency

## Conclusion

Phase 10D converts Project07 from an engineering validation interface
into a real Linux userspace-accessible DMA device while preserving the
persistent ring and asynchronous IRQ/reclaim architecture established
in Phase 10C.
