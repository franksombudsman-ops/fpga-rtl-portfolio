# Project 07 — Final Qualification and Release

**Project:** Custom Descriptor-Ring DMA Engine + Linux Driver
**Platform:** AMD ZCU104
**Final qualification date:** 2026-10-21
**Release:** Project07 v1.0
**Result:** PASS / COMPLETE

---

## 1. Final architecture

Project07 implements an authored FPGA DMA subsystem rather than using
AMD AXI DMA as the data-movement engine.

Final system path:

    Linux userspace
          |
          v
    /dev/project07-dma
          |
          v
    custom Linux platform driver
          |
          +-------------------------------+
          |                               |
          v                               v
    persistent TX ring              persistent RX ring
          |                               |
          v                               v
    authored TX DMA                  authored RX DMA
          |                               |
          v                               v
    AXI4-MM <-> DDR                AXI4-MM <-> DDR
          |                               |
          v                               v
    AXI4-Stream TX                 AXI4-Stream RX

Completion path:

    FPGA
      -> IRQ
      -> GIC
      -> Linux hard IRQ
      -> threaded IRQ
      -> HW_HEAD reclaim

Recovery path:

    hardware fault
      -> FPGA error IRQ
      -> Linux threaded IRQ
      -> diagnostic snapshot
      -> quiesce/reset
      -> ring restore
      -> new DMA epoch
      -> normal operation resumes

---

## 2. Final userspace ABI

Runtime device:

    /dev/project07-dma

Supported v1 operations:

- write exactly 64 bytes for TX
- read exactly 64 bytes for RX
- GET_INFO ioctl
- GET_STATS ioctl
- RESET ioctl

Userspace does not supply DMA addresses.

Descriptor and payload storage is owned by the kernel driver through
the Linux DMA API.

Direct /dev/mem access is not part of the runtime architecture.

---

## 3. Persistent-ring model

TX and RX each use:

    16 descriptors
    64 bytes per descriptor

Logical indices are monotonically increasing.

Physical slot:

    logical_index & 15

TX software state:

    tx_prod
    tx_clean

RX software state:

    rx_prod
    rx_clean

Hardware HEAD is authoritative for descriptor retirement.

A descriptor is reclaimed only after hardware publishes completion
through HW_HEAD.

---

## 4. Physical runtime qualification

### TX

Userspace TX through write() was physically proven through:

    copy_from_user
      -> driver coherent payload
      -> descriptor publication
      -> FPGA DDR read
      -> AXI4-Stream
      -> completion IRQ
      -> threaded HW_HEAD reclaim

Persistent-ring operation and physical wrap were demonstrated.

### RX

Userspace RX through read() was physically proven through:

    RX descriptor publication
      -> FPGA AXI4-Stream source
      -> DDR DMA write
      -> completion IRQ
      -> threaded HW_HEAD reclaim
      -> copy_to_user

Exact physical RX payload:

    11111111 22222222 33333333 44444444
    55555555 66666666 77777777 88888888
    99999999 aaaaaaaa bbbbbbbb cccccccc
    dddddddd eeeeeeee ffffffff 12345678

TX and RX both completed with zero DMA error status.

---

## 5. Error and recovery qualification

A genuine hardware ownership fault was physically induced.

Captured hardware diagnostics:

    ERROR_STATUS = 0x00000001
    ERROR_INFO   = 0x00000002
    ERROR_ADDR   = 0x0000000000000000

The real FPGA error propagated through:

    FPGA
      -> GIC
      -> Linux IRQ
      -> threaded recovery

Automatic recovery:

- captured pre-reset diagnostics
- quiesced DMA
- reset the custom core
- cleared stale status
- restored persistent ring configuration
- reset software logical indices
- restored interrupts
- established a clean new DMA epoch

A valid userspace TX then succeeded after the real hardware fault.

Recovery failures:

    0

---

## 6. Final ABI qualification

GET_INFO physically returned:

    ABI version       0x00010000
    hardware ID       0x43444d41
    hardware version  0x00010000
    ring entries      16
    descriptor bytes  64
    payload bytes     64
    DMA address bits  40
    capabilities      0x0000003f

GET_STATS physically reported the qualified TX/RX runtime state.

RESET ioctl physically:

- returned success
- reset TX indices to zero
- reset RX indices to zero
- cleared hardware performance counters
- retained Linux lifetime IRQ history
- left ERROR_STATUS zero
- left runtime fault state clear

Final ABI ioctl qualification:

    PASS

---

## 7. Measured RX performance

Physical one-packet RX measurement:

    payload bytes               64
    userspace end-to-end        107.020 us

Hardware:

    active cycles               146
    AXI stall cycles            5
    AXIS stall cycles           65

    AXI stall                   3.425 %
    AXIS stall                  44.521 %

The current physical FPGA validation wrapper emits one deterministic
64-byte packet per custom-core reset.

Therefore the RX measurement is reported as physical single-packet
latency and correctness, not sustained RX throughput.

The short CPU utilization sample is not treated as a long-duration CPU
benchmark.

---

## 8. Measured sustained TX performance

Workload:

    descriptors                 2048
    payload per descriptor      64 bytes
    total payload               131072 bytes

Measured wall time:

    0.073498020 s

Measured userspace end-to-end throughput:

    1.700726 MiB/s
    14.266724 Mbit/s

Descriptor processing rate:

    27864.696 descriptors/s

Average userspace descriptor time:

    35.888 us

Ring-full retries:

    0

Measured CPU busy percentage during run:

    58.621 %

This is the measured end-to-end qualification-build result. It is not
represented as theoretical FPGA bandwidth.

---

## 9. Hardware performance measurement

Measured TX hardware counters:

    active cycles               290461
    AXI stall cycles            2048
    AXIS stall cycles           0

    AXI stall                   0.705 %
    AXIS stall                  0.000 %

At the physical 100 MHz PL clock:

    hardware-active time        2.904610 ms

Derived from the measured hardware-active interval:

    approximately 43.035 MiB/s
    approximately 361.004 Mbit/s

This active-window rate is intentionally distinguished from the
1.700726 MiB/s measured userspace end-to-end result.

The difference includes software submission, syscall, interrupt,
scheduler and idle/runtime overhead. It is not represented as a pure
driver-only latency measurement.

---

## 10. Final sustained-run accounting

After 2048 TX requests:

    tx_bytes        = 131072
    tx_desc         = 2048

    tx_prod         = 2048
    tx_clean        = 2048
    tx_head         = 2048

    error_status    = 0x00000000
    faulted         = 0

    recovery_failures = 0

Linux IRQ handler count increased by 2047 during the 2048-descriptor
TX workload.

This is valid because IRQ_STATUS uses latched cause bits and completion
interrupts may coalesce.

IRQ count is not used as descriptor completion authority.

The completion authorities were:

    TX_DESC_COUNT = 2048
    TX_HEAD       = 2048
    tx_clean      = 2048
    tx_prod       = 2048

All agreed exactly.

---

## 11. Project completion criteria

### 1. Authored DMA RTL verified

PASS

Custom descriptor handling, TX/RX engines, AXI read/write masters,
arbitration, interrupt controller and control registers were verified.

### 2. AXI protocol behavior verified

PASS

Burst behavior, backpressure, 4-KiB splitting, response handling and
request stability were covered by self-checking verification and
physical integration.

### 3. Implementation timing closed

PASS

Implemented physical builds completed with positive setup/hold margins
and no custom-DMA timing failure.

### 4. Physical AXI-Lite access proven

PASS

Hardware identity and control/status registers were physically accessed
from the A53/Linux system.

### 5. Descriptor fetch proven in hardware

PASS

DDR-resident descriptors were physically fetched and processed by the
custom engine.

### 6. TX and RX DDR transfers proven

PASS

Both directions were physically demonstrated, including exact RX
payload verification.

### 7. Linux driver operates using DMA API

PASS

Persistent coherent descriptor and payload memory uses Linux DMA APIs.

### 8. Interrupts physically demonstrated

PASS

Completion and error interrupts were demonstrated through the physical
FPGA -> GIC -> Linux path.

### 9. Descriptor-ring wraparound demonstrated

PASS

Monotonic logical indices and physical slot wrap were demonstrated in
hardware.

### 10. Measured performance reported

PASS

Userspace end-to-end TX throughput, RX latency, descriptor rate, IRQ
rate, CPU utilization and hardware stall/active counters were measured.

### 11. Failure/error behavior demonstrated

PASS

A real FPGA hardware fault produced a Linux error IRQ, was captured,
automatically recovered, and normal DMA operation resumed.

### 12. Evidence and reconstruction material committed

PASS

Verification scripts, physical reports, checkpoints and evidence are
stored with the Project07 repository.

---

## 12. Final qualification state

Project07 v1.0 has physically demonstrated:

- authored custom descriptor-ring DMA RTL
- AXI4-MM DDR access
- AXI4-Stream TX and RX
- persistent TX/RX descriptor rings
- monotonic logical indices
- physical ring wrap
- Linux DMA API integration
- controlled character-device userspace ABI
- asynchronous IRQ completion
- HW_HEAD-authoritative reclaim
- real userspace TX
- real userspace RX
- exact physical RX payload
- performance counters
- measured end-to-end performance
- real hardware-error IRQ
- automatic reset/recovery
- successful operation after recovery

## Final verdict

**PROJECT 07 — COMPLETE**

The project achieved its original objective: ownership of the complete
hardware/software boundary of a custom Linux-controlled SoC DMA
subsystem on physical ZCU104 hardware.
