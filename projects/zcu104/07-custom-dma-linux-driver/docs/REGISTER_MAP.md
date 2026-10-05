# Project 07 — Register Map

All registers are little-endian AXI4-Lite registers.

Initial CSR aperture: 4 KiB.

## Global Registers

| Offset | Name | Access | Description |
|---|---|---|---|
| 0x000 | ID | RO | DMA identification constant |
| 0x004 | VERSION | RO | RTL interface version |
| 0x008 | GLOBAL_CONTROL | RW | Global enable/reset control |
| 0x00C | GLOBAL_STATUS | RO | Global state |
| 0x010 | IRQ_STATUS | RW1C | Latched interrupt causes |
| 0x014 | IRQ_ENABLE | RW | Interrupt mask |
| 0x018 | ERROR_STATUS | RW1C | Global/latched errors |
| 0x01C | ERROR_INFO | RO | Additional error context |
| 0x020 | ERROR_ADDR_LO | RO | Fault address [31:0] |
| 0x024 | ERROR_ADDR_HI | RO | Fault address [63:32] |

## Identification

ID:

    0x43444D41

ASCII interpretation:

    "CDMA"

meaning Custom DMA.

VERSION initial value:

    0x00010000

major = 1  
minor = 0

## GLOBAL_CONTROL

bit 0: GLOBAL_ENABLE

bit 1: SOFT_RESET, write-one pulse

bit 2: COUNTER_CLEAR, write-one pulse

bits 31:3: reserved

SOFT_RESET shall not depend on software holding the bit high.

## IRQ_STATUS / IRQ_ENABLE

bit 0: TX_COMPLETION

bit 1: RX_COMPLETION

bit 2: TX_ERROR

bit 3: RX_ERROR

bits 31:4: reserved

IRQ_STATUS is write-one-to-clear.

The external interrupt output is asserted when:

    (IRQ_STATUS & IRQ_ENABLE) != 0

## TX Registers

| Offset | Name | Access |
|---|---|---|
| 0x100 | TX_CONTROL | RW |
| 0x104 | TX_STATUS | RO |
| 0x108 | TX_RING_BASE_LO | RW |
| 0x10C | TX_RING_BASE_HI | RW |
| 0x110 | TX_RING_SIZE | RW |
| 0x114 | TX_TAIL | RW |
| 0x118 | TX_HEAD | RO |
| 0x11C | TX_BYTES_LO | RO |
| 0x120 | TX_BYTES_HI | RO |
| 0x124 | TX_DESC_COUNT | RO |
| 0x128 | TX_ACTIVE_CYCLES_LO | RO |
| 0x12C | TX_ACTIVE_CYCLES_HI | RO |
| 0x130 | TX_AXI_STALL_LO | RO |
| 0x134 | TX_AXI_STALL_HI | RO |
| 0x138 | TX_AXIS_STALL_LO | RO |
| 0x13C | TX_AXIS_STALL_HI | RO |

TX_CONTROL:

bit 0: ENABLE

bit 1: HALT

bits 31:2: reserved

## RX Registers

| Offset | Name | Access |
|---|---|---|
| 0x200 | RX_CONTROL | RW |
| 0x204 | RX_STATUS | RO |
| 0x208 | RX_RING_BASE_LO | RW |
| 0x20C | RX_RING_BASE_HI | RW |
| 0x210 | RX_RING_SIZE | RW |
| 0x214 | RX_TAIL | RW |
| 0x218 | RX_HEAD | RO |
| 0x21C | RX_BYTES_LO | RO |
| 0x220 | RX_BYTES_HI | RO |
| 0x224 | RX_DESC_COUNT | RO |
| 0x228 | RX_ACTIVE_CYCLES_LO | RO |
| 0x22C | RX_ACTIVE_CYCLES_HI | RO |
| 0x230 | RX_AXI_STALL_LO | RO |
| 0x234 | RX_AXI_STALL_HI | RO |
| 0x238 | RX_AXIS_STALL_LO | RO |
| 0x23C | RX_AXIS_STALL_HI | RO |

## Scratch Register

| Offset | Name | Access |
|---|---|---|
| 0x3FC | SCRATCH | RW |

SCRATCH has no functional effect.

It exists specifically for the first physical PS-to-PL hardware validation.

The first ZCU104 test shall:

1. read ID;
2. verify 0x43444D41;
3. write SCRATCH;
4. read SCRATCH;
5. verify exact round-trip value.

No descriptor or DMA testing is permitted until this physical gate passes.

## Configuration Rules

Ring configuration registers may be modified only while the corresponding
channel is disabled and idle.

Ring base must be 64-byte aligned.

Ring size must be a supported power of two.

Illegal configuration shall produce an explicit error rather than undefined
operation.
