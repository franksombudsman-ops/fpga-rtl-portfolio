# SPI Master — Pmod AD1 (AD7476A 12-bit ADC)

**Platform:** Xilinx Kria KR260 (Zynq UltraScale+, PL fabric)  
**Interface:** Pmod 2 (J3) — SPI bus to Digilent Pmod AD1  
**ADC:** Analog Devices AD7476A — 12-bit, 1 MSPS successive-approximation  
**Toolchain:** Vivado 2022.x · SystemVerilog (IEEE 1800-2017)  
**Status:** RTL complete · simulation in progress · constraints written

---

## Overview

A parameterised SPI master that reads a 12-bit ADC result from the Digilent
Pmod AD1 module at a configurable sample rate. Demonstrates four RTL
disciplines:

1. **Parameterised clock generation** — SCLK frequency is derived from the
   system clock with an integer divider, making the core retargetable to any
   supported ADC speed without RTL changes.

2. **SPI Mode 0 protocol** — CS_N asserted one half-period before the first
   rising SCLK edge; MOSI driven on falling edge; MISO sampled on rising edge.

3. **Protocol-layer separation** — `spi_master` handles the raw bit-bang
   mechanics; `pmod_ad1_ctrl` handles the AD7476A frame format and 12-bit
   extraction. Each layer is independently testable.

4. **One-pulse handshake** — `sample_req_i` triggers exactly one conversion;
   `sample_valid_o` pulses for exactly one cycle when the result is ready,
   making integration into higher-level state machines straightforward.

---

## Architecture

```
                  ┌────────────────────────────────────────────────────┐
                  │                       top.sv                       │
                  │                                                    │
                  │  ┌──────────────┐    sample_req                   │
                  │  │ sample-rate  ├──────────────►                  │
                  │  │ timer        │                                  │
                  │  └──────────────┘   ┌──────────────────────────┐  │
                  │                     │   pmod_ad1_ctrl           │  │
                  │                     │                           │  │
                  │                     │  ┌─────────────────────┐  │  │
                  │                     │  │   spi_master        ├──┼──►  ad_cs_n
                  │                     │  │  BITS=16, Mode 0    ├──┼──►  ad_sclk
                  │                     │  │                     │  │  │
ad_sdo ──────────────────────────────────► │  clk_tick FSM       │  │  │
                  │                     │  └─────────────────────┘  │  │
                  │                     │  frame[12:1] → 12-bit out │  │
                  │                     └──────────────────────────┘  │
                  │                                   │ adc_hold       │
                  │                            ┌──────▼──────┐        │
                  │                            │ result reg  ├────────►  leds[2:0]
                  │                            └─────────────┘        │
                  └────────────────────────────────────────────────────┘
```

### Module hierarchy

| Module           | File                   | Function                                    |
|------------------|------------------------|---------------------------------------------|
| `top`            | `rtl/top.sv`           | Sample-rate timer, result register, LED out |
| `pmod_ad1_ctrl`  | `rtl/pmod_ad1_ctrl.sv` | AD7476A frame decode, SPI wiring            |
| `spi_master`     | `rtl/spi_master.sv`    | Generic 16-bit SPI Mode 0 master            |

---

## AD7476A SPI frame format

The AD7476A transfers 16 bits per conversion, CS_N low for all 16 SCLK cycles:

```
Bit:  15  14  13  12  11  10   9   8   7   6   5   4   3   2   1   0
      ─── ─── ─── ─────────────────────────────────────────────────── ───
       0   0  NUL DB11 DB10 DB9 DB8 DB7 DB6 DB5 DB4 DB3 DB2 DB1 DB0 DB0
           └──────────────────────────────────────────────────────────┘
                     12-bit result lives in frame[12:1]
```

- Bits 15–14: always 0 (ADC asserts SDO low before data)
- Bit 13: NULL bit (always 0)
- Bits 12–1: 12-bit conversion result, MSB first
- Bit 0: repeated LSB (ignored)

`pmod_ad1_ctrl` extracts `spi_rx[12:1]` after each 16-bit transfer.

---

## Key design decisions

**Why separate `spi_master` and `pmod_ad1_ctrl`?**  
`spi_master` is device-agnostic — the same core could drive an SPI flash,
DAC, or display driver just by changing BITS and the CLK_DIV parameter.
Keeping the AD7476A frame knowledge in a thin wrapper means both layers can
be tested independently and the master can be reused in project 3+.

**Why integer CLK_DIV instead of a PLL?**  
The AD7476A supports up to 20 MHz SCLK; at 100 MHz system clock,
`CLK_DIV = 5` gives exactly 10 MHz with no fractional error and zero LUT
cost compared to a DCM/MMCM. A PLL would waste a global clock resource.

**Why 16-bit SPI transfer rather than 12-bit?**  
The AD7476A always clocks out 16 bits per CS assertion — the null and leading
bits are part of the protocol, not padding. Capturing all 16 bits and slicing
`[12:1]` in logic is cleaner than trying to abort the transfer mid-frame.

**Why `done_o` is a one-cycle pulse (not a level)?**  
A pulse-based handshake is safe to use in any higher-level FSM state —
there's no risk of "double-latching" a stale result if the consumer is slow.
Compare with a `valid` level that requires an explicit `ready` acknowledgement.

---

## Simulation

The testbench exercises all four paths of `spi_master` directly:

```
sim/
└── spi_master_tb.sv
```

| Test | What it checks |
|------|----------------|
| 1 — TX fidelity | MOSI bit-stream matches `data_i` (0xABCD) |
| 2 — RX capture  | `data_o` matches MISO pattern (0x1234) |
| 3 — AD7476A frame | Frame 0x1FFE → `data_o[12:1]` = 0xFFF |
| 4 — Handshake   | `busy_o` high during transfer, low after `done_o` |

**Running in Vivado XSim:**
```bash
xvlog --sv sim/spi_master_tb.sv rtl/spi_master.sv
xelab spi_master_tb -snapshot spi_tb_snap
xsim spi_tb_snap --runall
```

---

## Pin assignments (Pmod 2 / J3, KR260)

Constraints file: `constraints/kr260_pmod2.xdc`

| Signal    | Direction | Pmod 2 pin | FPGA ball | IOSTANDARD | Notes                 |
|-----------|-----------|------------|-----------|------------|-----------------------|
| `ad_cs_n` | output    | P1         | J11       | LVCMOS33   | ADC chip-select       |
| `ad_sclk` | output    | P2         | J10       | LVCMOS33   | SPI clock ≤ 20 MHz    |
| `ad_sdo`  | input     | P3         | K13       | LVCMOS33   | ADC serial data → MISO |
| (NC)      | —         | P4         | —         | —          | SDI not used by AD7476A |
| `rst_n`   | input     | P7         | H11       | LVCMOS33   | Active-low; PULLUP    |

---

## Build

```bash
cd projects/spi-master-pmod-ad1/vivado
vivado -mode batch -source build.tcl
```

Reports written to `vivado/output/`: timing summary, utilisation, DRC, CDC.

---

## File tree

```
spi-master-pmod-ad1/
├── constraints/
│   └── kr260_pmod2.xdc       # Pmod 2 (J3) pin assignments
├── rtl/
│   ├── spi_master.sv         # Generic SPI Mode 0 master (16-bit, parameterised)
│   ├── pmod_ad1_ctrl.sv      # AD7476A frame wrapper
│   └── top.sv                # Sample-rate timer, result register, LED output
├── sim/
│   └── spi_master_tb.sv      # Directed SPI master testbench
└── vivado/
    └── build.tcl             # Non-project-mode build script
```
