# Project 07 — AXI Contract

## Interfaces

The custom DMA exposes:

- AXI4-Lite slave control interface;
- AXI4 memory-mapped master interface;
- AXI4-Stream TX master;
- AXI4-Stream RX slave;
- interrupt output.

## AXI4 Memory-Mapped Master

Data width: 64 bits.

Beat size: 8 bytes.

Supported burst type:

INCR.

The DMA shall generate legal AXI4 AR/AW transactions and shall never cross a
4-KiB boundary within one burst.

## Fundamental VALID Rule

For every AXI channel:

Once VALID is asserted, the corresponding payload/control signals shall remain
stable until VALID && READY occurs.

A transaction advances only on a completed handshake.

## Read Channel

The DMA shall generate:

- ARADDR;
- ARLEN;
- ARSIZE;
- ARBURST;
- ARVALID.

ARLEN encodes beats minus one.

The DMA shall consume:

- RDATA;
- RRESP;
- RLAST;
- RVALID.

Every accepted read beat shall be counted exactly once.

RRESP values other than OKAY shall terminate the affected DMA operation with a
software-visible error.

RLAST shall be checked against the expected final beat.

Early or missing RLAST is an error.

## Write Channel

The DMA shall generate:

- AWADDR;
- AWLEN;
- AWSIZE;
- AWBURST;
- AWVALID;
- WDATA;
- WSTRB;
- WLAST;
- WVALID.

For V1 aligned transfers:

WSTRB = 8'hFF for every payload beat.

WLAST shall be asserted only on the final beat of the corresponding AXI burst.

B responses shall be checked.

BRESP values other than OKAY shall terminate the affected operation with a
software-visible error.

## Burst Planning

For each operation:

    beats_remaining = bytes_remaining / 8

The next burst length is limited by:

1. remaining transfer beats;
2. configured maximum burst length;
3. number of beats remaining before the next 4-KiB boundary.

The burst planner shall never generate a zero-beat burst.

## Outstanding Transactions

Initial RTL may begin with one outstanding read burst and one outstanding write
burst.

The architecture shall not prevent a later milestone from supporting multiple
outstanding transactions.

Outstanding counts shall be explicit state, not inferred indirectly.

## Descriptor vs Payload Traffic

Descriptor and payload accesses share the external AXI master.

Internal requesters shall be identifiable.

Initial requester classes:

- TX descriptor fetch;
- RX descriptor fetch;
- TX payload read;
- RX payload write;
- TX completion writeback;
- RX completion writeback.

Arbitration shall be deterministic and starvation-free.

## AXI4-Stream TX

Width: 64 bits.

Signals:

- TDATA[63:0]
- TKEEP[7:0]
- TVALID
- TREADY
- TLAST

For V1 aligned/multiple-of-eight transfers:

TKEEP = 8'hFF.

TLAST marks the last beat belonging to the descriptor packet.

While TVALID && !TREADY:

- TDATA stable;
- TKEEP stable;
- TLAST stable.

## AXI4-Stream RX

Width: 64 bits.

The DMA controls TREADY.

Once an RX beat is accepted:

    TVALID && TREADY

that beat becomes hardware-owned and may not be silently discarded.

Internal buffering shall absorb the timing difference between AXIS arrival and
DDR writes.

If no RX descriptor/buffer space exists, TREADY shall be deasserted.

## Reset Contract

During reset:

- all master VALID outputs low;
- TX TVALID low;
- RX TREADY low;
- no outstanding AXI transactions;
- channels disabled.

After reset release, software must configure the DMA before data movement can
begin.

## Error Contract

Protocol/data movement errors shall be:

- latched;
- visible through registers;
- attributable to TX or RX;
- capable of producing an interrupt.

No AXI error may be silently converted into successful descriptor completion.
