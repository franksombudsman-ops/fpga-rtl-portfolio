# Project 07 — Minimal Physical Bring-Up

Date: 2026-10-07
Platform: AMD/Xilinx ZCU104

## Scope

This milestone validates the Project 07 control-plane and interrupt substrate only.

It does not yet claim physical DMA descriptor fetch, payload movement, descriptor retirement, ring operation, or Linux-driver operation.

## Physical AXI-Lite Control Validation

PS/A53 access through M_AXI_HPM0_FPD to the Project 07 AXI-Lite register bank passed.

Observed:

- ID @ 0xA0000000 = 0x43444D41
- VERSION @ 0xA0000004 = 0x00010000
- SCRATCH initial = 0x00000000
- SCRATCH write/readback = 0xA5A55A5A

Result:

PS -> PL AXI-Lite control path: PASS

## Interrupt Register Validation

The temporary bring-up shell converts a SCRATCH write into a synthetic TX-completion event.

Observed:

- IRQ_STATUS[0] asserted after synthetic event
- IRQ_STATUS[0] cleared through W1C
- IRQ_ENABLE[0] accepted
- second synthetic event reasserted IRQ_STATUS[0]

Result:

Project 07 interrupt register logic: PASS

## Physical PL -> PS Interrupt Validation

The authored Project 07 irq output is connected to:

dma_bringup_shell irq
-> ZynqMP pl_ps_irq0[0]
-> GIC SPI 121

Observed:

- GIC raw SPI status bit for IRQ121 = 0x02000000
- GIC pending bit for IRQ121 = 0x02000000 after enabling distributor and IRQ121

Result:

Physical PL -> PS interrupt routing: PASS

## Cortex-A53 Interrupt Service Validation

A minimal AArch64 bare-metal test was downloaded to Cortex-A53 #0.

Observed ISR evidence:

- ISR signature = 0x49535231 ("ISR1")
- raw GICC_IAR = 0x00000079
- decoded interrupt ID = 0x00000079 (121)
- CurrentEL = 0x0000000C (EL3)

After servicing:

- P07 IRQ_STATUS = 0x00000000
- raw PL IRQ input = 0x00000000
- GIC IRQ121 pending = 0x00000000

The ISR performed:

1. interrupt acknowledge
2. IRQ121 verification
3. Project 07 W1C source clear
4. GIC EOI
5. PASS-signature write

Result:

Cortex-A53 physical service of Project 07 PL interrupt: PASS

## Physically Proven

- PS -> PL AXI-Lite access
- ID register
- VERSION register
- SCRATCH R/W
- IRQ event latch
- IRQ W1C clear
- IRQ masking
- PL -> PS interrupt routing
- GIC SPI 121 raw input
- GIC pending state
- Cortex-A53 interrupt servicing
- ISR source clear and EOI

## Not Yet Physically Proven

- descriptor fetch from DDR
- custom DMA AXI4-MM DDR access
- TX DDR -> AXI4-Stream
- RX AXI4-Stream -> DDR
- descriptor completion/writeback
- HW_HEAD advancement
- ring wrap
- sustained bidirectional DMA
- Linux platform driver

## Next Physical Gate

Project 07 Physical Gate 2:

Custom DMA descriptor fetch from DDR.

## Implementation Closure

The minimal physical bring-up implementation closed timing before hardware validation.

Observed post-route timing:

- WNS: +2.937 ns
- TNS: 0
- WHS: +0.017 ns
- THS: 0
- WPWS: +3.500 ns
- TPWS: 0
- no_clock checks: 0
- unconstrained internal endpoints: 0
- multiple-clock issues: 0
- combinational loops: 0

All user-specified timing constraints were met.

The associated DRC and utilization reports are preserved with this milestone.
