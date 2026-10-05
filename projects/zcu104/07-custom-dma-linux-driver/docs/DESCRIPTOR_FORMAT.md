# Project 07 — Descriptor Format

## Descriptor Size

Each descriptor is exactly 64 bytes and must begin on a 64-byte boundary.

Descriptors are stored in DDR.

TX and RX rings use the same base descriptor layout.

## Ownership

Software producer / hardware consumer.

Software may modify a descriptor only while OWN = 0.

Software shall:

1. construct the descriptor;
2. perform required DMA memory synchronization/barriers;
3. set OWN = 1;
4. advance the producer/tail index.

Hardware may consume only descriptors with OWN = 1.

On completion, hardware:

1. writes completion/result fields;
2. clears OWN;
3. advances the hardware head;
4. optionally raises an interrupt.

Completion data must become visible before ownership is returned to software.

## 64-Byte Layout

| Offset | Width | Field |
|---|---:|---|
| 0x00 | 64 | BUFFER_ADDR |
| 0x08 | 32 | LENGTH |
| 0x0C | 32 | CONTROL |
| 0x10 | 64 | COOKIE |
| 0x18 | 32 | STATUS |
| 0x1C | 32 | ACTUAL_LENGTH |
| 0x20 | 64 | TIMESTAMP / RESERVED |
| 0x28 | 64 | RESERVED |
| 0x30 | 64 | RESERVED |
| 0x38 | 64 | RESERVED |

## BUFFER_ADDR

64-bit DMA address of the payload buffer.

V1 requirements:

- address must be 8-byte aligned;
- implementation shall support the physical address width required by ZCU104;
- unsupported upper address bits shall generate an explicit descriptor error.

## LENGTH

Requested payload length in bytes.

V1:

- LENGTH must be non-zero;
- LENGTH must be a multiple of 8 bytes;
- the DMA may split one descriptor into multiple AXI bursts;
- no individual AXI burst may cross a 4-KiB boundary.

## CONTROL

Bit definitions:

- bit 0: OWN
- bit 1: IRQ_ON_COMPLETION
- bit 2: END_OF_PACKET / TX packet completion policy
- bit 3: reserved
- bits 31:4: reserved, write zero

Unknown/reserved control bits shall not silently change hardware behavior.

## COOKIE

Opaque 64-bit software value.

Hardware shall preserve the value.

The cookie may be used by the Linux driver to associate a completion with a
software request.

## STATUS

Written by hardware.

Bit definitions:

- bit 0: COMPLETE
- bit 1: ERROR
- bit 2: AXI_READ_ERROR
- bit 3: AXI_WRITE_ERROR
- bit 4: ALIGNMENT_ERROR
- bit 5: LENGTH_ERROR
- bit 6: ADDRESS_ERROR
- bit 7: RX_OVERFLOW
- bit 8: RX_LENGTH_MISMATCH
- bit 9: INTERNAL_ERROR
- bits 31:10: reserved

## ACTUAL_LENGTH

Number of payload bytes successfully transferred.

For a successful TX descriptor:

ACTUAL_LENGTH == LENGTH.

For RX:

ACTUAL_LENGTH records the number of bytes actually accepted and committed to
DDR according to the RX termination contract.

## Ring Rules

Ring size shall be a power of two.

Hardware and software track monotonically advancing logical indices.

Physical descriptor index:

    logical_index & (ring_size - 1)

This allows wraparound without ambiguous special-case pointer arithmetic.

The initial implementation shall support a configurable ring size of at least
16 descriptors and target support for up to 1024 descriptors.

## Invalid Descriptor Behavior

Hardware shall reject rather than partially execute descriptors containing:

- zero length;
- unsupported alignment;
- unsupported address;
- invalid reserved/control fields where defined;
- ownership inconsistency.

An invalid descriptor must generate a software-visible error and must not
silently corrupt subsequent descriptors.

## Authoritative Completion Publication

The descriptor OWN field alone is not sufficient evidence that software may
reclaim a descriptor.

The authoritative hardware completion boundary is HW_HEAD.

For logical descriptor N, software may reclaim the descriptor only after
HW_HEAD has advanced beyond N.

Normal successful retirement is:

1. hardware completes payload processing;
2. hardware writes STATUS and ACTUAL_LENGTH;
3. that write receives a successful AXI write response;
4. hardware writes CONTROL with OWN cleared;
5. that write receives a successful AXI write response;
6. hardware advances HW_HEAD.

HW_HEAD therefore publishes successful descriptor retirement.

### AXI Write-Error Case

A non-OKAY AXI BRESP does not provide a transactional guarantee that the
corresponding memory write had no side effect.

For example, the CONTROL word containing OWN=0 may have reached the memory
system before an error response is returned.

Therefore, after a failed descriptor writeback:

- the channel enters a faulted state;
- HW_HEAD does not advance;
- no successful completion is published;
- software must not reclaim the descriptor based only on its memory OWN bit;
- descriptor memory affected by the failed transaction is considered
  untrusted until explicit software recovery/reinitialization.

This rule prevents a write-response failure from causing premature descriptor
reuse.
