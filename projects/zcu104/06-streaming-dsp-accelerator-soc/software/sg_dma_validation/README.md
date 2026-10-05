# Project06 SG-DMA Physical Validation

First physical DDR -> FPGA -> DDR validation of the Project06 streaming DSP
accelerator on the ZCU104.

## Campaign

Input:
- 128 signed Q1.15 samples
- impulse_input.hex
- 256 bytes

Path:

DDR
-> AXI DMA MM2S
-> 16-bit AXI4-Stream
-> FIR32
-> moving energy64
-> programmable threshold event
-> 64-bit AXI4-Stream
-> AXI DMA S2MM
-> DDR

Output:
- 128 x 64-bit words
- 1024 bytes

Each result word:
- bits 15:0   FIR output
- bits 52:16  moving energy
- bit 53      event
- bits 63:54  reserved

Validation:
- SG DMA MM2S interrupt
- SG DMA S2MM interrupt
- actual receive length
- exact FIR value
- exact moving-energy value
- exact event bit
- reserved bits zero
- SAMPLE_COUNT
- RESULT_COUNT
- EVENT_COUNT

This is a correctness campaign, not a performance benchmark.
