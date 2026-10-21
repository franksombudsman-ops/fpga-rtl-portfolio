# Project 07 — Phase 10E Physical Recovery Qualification

## Result

PASS

Phase 10E physically validated both:

1. controlled runtime recovery
2. real hardware-error IRQ automatic recovery

The real Linux userspace DMA interface remained:

    /dev/project07-dma

## Controlled recovery

A valid userspace TX completed before recovery.

Controlled recovery was triggered through the temporary validation
runtime_recover interface.

Recovery captured the pre-reset state and re-established:

    tx_prod=0
    tx_clean=0
    tx_head=0

    rx_prod=0
    rx_clean=0
    rx_head=0

    error_status=0x00000000
    faulted=0
    recovery_count=1
    recovery_failures=0

Hardware performance counters were cleared as defined by the canonical
hardware initialization sequence.

A new /dev/project07-dma TX then completed successfully after recovery.

## Real hardware-error IRQ qualification

A deliberate laboratory fault was injected through the Project07 TX_TAIL
CSR by publishing logical tail 2 while the corresponding descriptor slot
was no longer hardware-owned.

The hardware produced an error interrupt.

Captured error state:

    error_status=0x00000001
    error_info=0x00000002
    error_addr=0x0000000000000000

The Linux threaded IRQ entered:

    reason=hardware-error-irq

Automatic recovery completed successfully:

    tx_prod=0
    tx_clean=0
    tx_head=0
    error_status=0x00000000

Persistent recovery state after the fault:

    irq_seen=0x00000005
    recovery_count=2
    recovery_failures=0
    faulted=0

    last_error_status=0x00000001
    last_error_info=0x00000002
    last_error_addr=0x0000000000000000

No in-flight TX descriptors were lost:

    recovery_dropped_tx=0
    last_recovery_dropped_tx=0

## Post-fault runtime proof

After automatic recovery, another userspace write through:

    /dev/project07-dma

completed successfully.

The new DMA epoch began at:

    logical=0
    slot=0
    tx_prod=1

Completion was reclaimed through the normal threaded IRQ / HW_HEAD path:

    tx_clean=1
    tx_head=1

Final runtime state:

    tx_prod=1
    tx_clean=1
    tx_head=1
    tx_bytes=64
    tx_desc=1

    irq_count=5
    irq_seen=0x00000005

    error_status=0x00000000
    faulted=0

    recovery_count=2
    recovery_failures=0

## Validated properties

- controlled runtime reset/recovery
- pre-reset diagnostic capture
- DMA channel quiesce
- custom core soft reset
- stale interrupt/error clearing
- persistent ring base restoration
- software logical-index reinitialization
- hardware counter reset
- real FPGA hardware-error interrupt
- threaded Linux error handling
- automatic recovery from hardware fault
- preserved error diagnostics across reset
- clean post-recovery DMA epoch
- successful userspace TX after real hardware fault
- successful IRQ/HW_HEAD reclaim after recovery
- zero recovery failures

## Qualification note

The direct CSR write used to create the hardware fault was a laboratory
fault-injection mechanism only.

Direct /dev/mem register access is not part of the final Project07
userspace architecture.

## Conclusion

Phase 10E demonstrates that Project07 can detect a real hardware fault,
deliver the error through the FPGA-to-GIC-to-Linux interrupt path,
capture diagnostics, automatically restore the DMA runtime, and resume
normal userspace DMA operation without rebooting or reprogramming the FPGA.
