# Project 07 — Physical Custom DMA DDR Descriptor Fetch

Date: 2026-10-07  
Platform: AMD/Xilinx ZCU104

## Objective

Prove that the authored Project 07 AXI4 memory master can physically access
ZCU104 DDR through PS S_AXI_HP0_FPD and deliver descriptor data into the
authored descriptor engine/parser.

This gate does not claim TX payload movement, RX payload movement, successful
descriptor retirement, ring wrap, or Linux-driver operation.

## Hardware Path

Cortex-A53 / debugger
-> DDR
-> Zynq UltraScale+ HP0
-> AXI SmartConnect
-> Project 07 authored AXI4 memory master
-> descriptor engine
-> descriptor parser

## Test Method

A single 64-byte descriptor was placed in DDR at:

    0x10000000

The descriptor was deliberately initialized with CONTROL.OWN = 0.

TX ring configuration:

    TX_RING_BASE = 0x0000000010000000
    TX_RING_SIZE = 16
    TX_TAIL      = 1

The DMA was then enabled.

Expected behavior:

- descriptor is physically fetched from DDR;
- parser detects OWN=0;
- descriptor engine enters ownership fault;
- HW_HEAD does not advance;
- descriptor is not modified;
- TX error interrupt is raised.

## Physical Results

Observed:

    TX_STATUS      = 0x00000029
    TX_HEAD        = 0x00000000
    TX_TAIL        = 0x00000001
    IRQ_STATUS     = 0x00000004
    IRQ_ENABLE     = 0x00000004
    ERROR_STATUS   = 0x00000001
    ERROR_INFO     = 0x00000002

TX_STATUS decoding:

- bit 0 = config_valid = 1
- bit 3 = fault_valid = 1
- bits 7:4 = fault_code = 2

Fault code 2 is FAULT_OWNERSHIP.

The 64-byte DDR descriptor remained unchanged after the test.

HW_HEAD remained zero, confirming that the invalid/unowned descriptor was not
retired.

## Conclusion

Physical custom DMA descriptor fetch from ZCU104 DDR: PASS.

This proves the authored Project 07 AXI4 memory master physically reached DDR,
returned descriptor data to the descriptor engine, and produced the expected
ownership-fault behavior.

## Not Yet Physically Proven

- valid descriptor execution
- TX payload read from DDR
- AXI4-Stream TX output
- RX payload write to DDR
- STATUS / ACTUAL_LENGTH writeback
- OWN clear
- successful HW_HEAD advancement
- real DMA completion interrupt
- ring wrap
- sustained bidirectional DMA
- Linux platform driver

## Next Physical Gate

Valid TX descriptor execution and payload movement:

DDR payload
-> custom DMA AXI4 read
-> TX AXI4-Stream
-> descriptor STATUS writeback
-> OWN clear
-> HW_HEAD advancement
-> completion interrupt
