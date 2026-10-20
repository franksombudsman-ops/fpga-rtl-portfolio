# Project 07 Runtime Linux DMA Driver

## Validation Baseline

Physical Linux validation completed through Gate 9N.

Validated capabilities:

- platform-driver probe and MMIO mapping
- generated Device Tree binding
- Linux DMA API with 40-bit coherent DMA mask
- PL -> GIC -> Linux interrupts
- interrupt RW1C acknowledgement
- valid TX DMA
- valid RX DMA
- simultaneous TX/RX
- multi-descriptor TX operation
- descriptor retirement
- performance counters
- logical ring progression across physical wrap

The Gate 9 checkpoint sources are immutable validation references.

## Runtime Driver Rules

### Ring organization

TX and RX each use a persistent coherent descriptor ring.

Ring size:

    16 descriptors

Descriptor size:

    64 bytes

Physical descriptor slot:

    slot = logical_index & (ring_size - 1)

Logical producer and reclaim counters remain monotonically increasing.

They MUST NOT be reduced modulo ring_size when written as logical
HEAD/TAIL values.

### TX software state

    tx_prod
        next logical descriptor index to publish

    tx_clean
        oldest logical descriptor not yet reclaimed

Hardware TX_HEAD is authoritative for completed descriptors.

Reclaim range:

    while tx_clean != HW_HEAD:
        slot = tx_clean & (ring_size - 1)
        validate descriptor writeback
        reclaim slot
        tx_clean++

### RX software state

    rx_prod
        next logical RX descriptor advertised to hardware

    rx_clean
        next completed RX descriptor for software consumption

Hardware RX_HEAD is authoritative for completion.

### Descriptor publication

Software shall:

1. prepare payload/buffer
2. prepare descriptor
3. set OWN
4. dma_wmb()
5. advance software producer
6. write logical TAIL

### Descriptor reclaim

Software shall:

1. read HW_HEAD
2. dma_rmb()
3. inspect writeback
4. verify OWN cleared
5. verify STATUS / ACTUAL_LENGTH
6. reclaim descriptor
7. advance software clean index

### Interrupts

ISR shall:

1. read IRQ_STATUS
2. mask supported causes
3. record completion/error state
4. RW1C acknowledged causes
5. wake waiting runtime paths

Interrupt count is not the authoritative completion count.

HW_HEAD is authoritative.

### Recovery

Recovery shall:

1. disable channel interrupts
2. halt/disable channels
3. capture ERROR_STATUS / ERROR_INFO / ERROR_ADDR
4. reset DMA core when required
5. restore ring configuration
6. restore software producer/reclaim state safely
7. re-enable operation

### Userspace

Expose a controlled character-device interface.

Planned device:

    /dev/project07-dma

Initial operations:

- query hardware/driver information
- query runtime statistics
- submit controlled TX request
- receive/reclaim RX completion
- request controlled reset/recovery

Userspace must never receive arbitrary MMIO access.

No /dev/mem dependency is permitted.
