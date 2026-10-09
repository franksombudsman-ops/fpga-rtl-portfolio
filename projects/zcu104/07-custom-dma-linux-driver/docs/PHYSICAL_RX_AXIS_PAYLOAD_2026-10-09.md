# Project 07 — Physical Gate 4B RX AXI4-Stream Validation

**Result: PASS**

Platform: ZCU104
Toolchain: Vivado / XSDB 2023.2
PL clock: 100 MHz

## Physical result

Gate 4B directly observed the AXI4-Stream packet presented to dma_rx_engine using Vivado ILA.

```text
Beat 0: 2222222211111111  KEEP=FF  VALID=1 READY=1 LAST=0
Beat 1: 4444444433333333  KEEP=FF  VALID=1 READY=1 LAST=0
Beat 2: 6666666655555555  KEEP=FF  VALID=1 READY=1 LAST=0
Beat 3: 8888888877777777  KEEP=FF  VALID=1 READY=1 LAST=0
Beat 4: AAAAAAAA99999999  KEEP=FF  VALID=1 READY=1 LAST=0
Beat 5: CCCCCCCCBBBBBBBB  KEEP=FF  VALID=1 READY=1 LAST=0
Beat 6: EEEEEEEEDDDDDDDD  KEEP=FF  VALID=1 READY=1 LAST=0
Beat 7: 12345678FFFFFFFF  KEEP=FF  VALID=1 READY=1 LAST=1

TRANSFER_BEATS = 8
GATE4B_STREAM_CHECK = PASS
```

The capture also showed TVALID asserted while TREADY was initially low, with the first payload word held stable until acceptance.

The same transaction physically produced the expected 64-byte DDR payload, descriptor STATUS=1, ACTUAL_LENGTH=0x40, OWN clear, RX_HEAD=1, RX completion IRQ, and ERROR_STATUS=0.

## Offline signoff

- WNS: +4.168 ns
- TNS: 0
- WHS: +0.001 ns
- THS: 0
- WPWS: +3.500 ns
- TPWS: 0
- Final failed nets: 0
- Final unrouted nets: 0
- Final node overlaps: 0

DRC contained six PDCN-1569 warnings and one RTSTAT-10 warning in generated Xilinx AXI/debug-hub infrastructure; no custom-DMA DRC error was identified.

## Evidence

- ILA: evidence/ila/gate4b_rx_payload_capture.ila
- CSV: evidence/ila/gate4b_rx_payload_capture.csv
- Screenshot: evidence/screenshots/06_gate4b_physical_rx_axis_payload.png
- Video: evidence/videos/gate4b_physical_rx_axis_payload.mp4

- ILA SHA256: 5d97f5ac0b39b27778fb7a4a40962f7c789ee721b2a8f95587a81ca1b5924ff1
- CSV SHA256: 8fef73e427923d40b0b463b7c94c1f151107168b8a9d5c970738875c42970108
- Screenshot SHA256: b792f01893a7bf8e5dd5117539cf16fcfc591ed5d3b77e661fa7f3967280974a
- Gate 4B bitstream SHA256: a5eca4e1dca5c3c9ab455d70a0a0488fca5c39e721e7af556017502d32d8a591

## Conclusion

**PHYSICAL GATE 4B: PASS**

Direct ILA hardware evidence proves the deterministic RX AXI4-Stream packet entered the custom DMA receive engine with correct payload, TKEEP, TVALID/TREADY handshakes, and TLAST framing.
