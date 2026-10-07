# Project 07 — Physical TX AXI4-Stream Payload Validation

Date: 2026-10-07
Platform: AMD/Xilinx ZCU104
Clock: 100 MHz PL clock

## Objective

Physically prove that payload data read from DDR by the authored Project 07
DMA appears correctly on the authored TX AXI4-Stream interface.

## Payload

DDR payload address:

    0x10001000

Length:

    64 bytes

Expected 64-bit TX beats:

    Beat 0: 0x2222222211111111
    Beat 1: 0x4444444433333333
    Beat 2: 0x6666666655555555
    Beat 3: 0x8888888877777777
    Beat 4: 0xAAAAAAAA99999999
    Beat 5: 0xCCCCCCCCBBBBBBBB
    Beat 6: 0xEEEEEEEEDDDDDDDD
    Beat 7: 0x12345678FFFFFFFF

## Physical ILA Result

The ZCU104 ILA captured exactly eight accepted TX AXI4-Stream beats.

Observed:

    Beat 0: DATA=2222222211111111 KEEP=FF VALID=1 READY=1 LAST=0
    Beat 1: DATA=4444444433333333 KEEP=FF VALID=1 READY=1 LAST=0
    Beat 2: DATA=6666666655555555 KEEP=FF VALID=1 READY=1 LAST=0
    Beat 3: DATA=8888888877777777 KEEP=FF VALID=1 READY=1 LAST=0
    Beat 4: DATA=AAAAAAAA99999999 KEEP=FF VALID=1 READY=1 LAST=0
    Beat 5: DATA=CCCCCCCCBBBBBBBB KEEP=FF VALID=1 READY=1 LAST=0
    Beat 6: DATA=EEEEEEEEDDDDDDDD KEEP=FF VALID=1 READY=1 LAST=0
    Beat 7: DATA=12345678FFFFFFFF KEEP=FF VALID=1 READY=1 LAST=1

Transfer beats:

    8

## Descriptor Retirement

The same physical transaction also produced:

    TX_HEAD       = 0x00000001
    TX_TAIL       = 0x00000001
    IRQ_STATUS    = 0x00000001
    ERROR_STATUS  = 0x00000000

Descriptor after DMA:

    CONTROL       = 0x00000006
    STATUS        = 0x00000001
    ACTUAL_LENGTH = 0x00000040

Therefore:

- OWN cleared successfully
- COMPLETE asserted
- ACTUAL_LENGTH = 64 bytes
- HW_HEAD advanced
- TX completion interrupt generated

- no DMA error occurred

## Physical Path Proven

DDR payload
-> authored AXI4-MM read master
-> authored TX DMA engine
-> AXI4-Stream interface
-> eight physical accepted transfers
-> TLAST on final transfer
-> descriptor completion
-> OWN clear
-> HW_HEAD advancement
-> completion IRQ

## Evidence

Machine-readable Vivado ILA capture:

    evidence/ila/gate3b_tx_payload_capture.ila

CSV export:

    evidence/ila/gate3b_tx_payload_capture.csv

Waveform screenshot:

    evidence/screenshots/03_gate3b_physical_tx_axis_payload.png

## Conclusion

Physical TX payload movement: PASS.

The authored Project 07 DMA physically read the expected 64-byte payload from
ZCU104 DDR and presented all eight expected 64-bit words on its TX
AXI4-Stream interface with correct TKEEP, TVALID/TREADY handshake behavior
and TLAST packet termination.
