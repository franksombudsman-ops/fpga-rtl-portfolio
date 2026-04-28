# SPI Master Controller with Pmod AD1 Reader

Parameterized SPI Mode 0 master in SystemVerilog, verified in simulation against a behavioral AD7476A (12-bit SAR ADC) model.

---

## Architecture

```
top
└── pmod_ad1_reader          # AD7476A-specific wrapper + sample timer
    └── spi_master           # Generic SPI Mode 0 master (reusable)
```

`spi_master` is fully generic — it works with any SPI Mode 0 slave by setting
`CLK_FREQ`, `SPI_FREQ`, and `DATA_WIDTH`.  `pmod_ad1_reader` adds the
autonomous sample timer and 12-bit frame extraction specific to the AD7476A.

---

## SPI Mode 0 Protocol

| Signal | Idle state | Active behavior |
|--------|-----------|-----------------|
| CS_N   | High       | Low for full transfer |
| SCLK   | Low (CPOL=0) | Toggles during transfer |
| MOSI   | —          | Data changes on **falling** SCLK edge |
| MISO   | —          | Data sampled on **rising** SCLK edge (CPHA=0) |

```
CS_N  ‾‾\_______________________________________/‾‾
SCLK  ____/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\______
MOSI  ────< D7>< D6>< D5>< D4>< D3>< D2>< D1>< D0>
MISO  ────< Q7>< Q6>< Q5>< Q4>< Q3>< Q2>< Q1>< Q0>
            ↑   ↑   ↑   ↑   ↑   ↑   ↑   ↑
            sample points (rising SCLK)
```

Full timing detail: [`docs/spi_timing_diagram.md`](docs/spi_timing_diagram.md)

---

## Module Reference

### `spi_master`

| Parameter   | Default     | Description |
|-------------|-------------|-------------|
| `CLK_FREQ`  | 100_000_000 | System clock frequency (Hz) |
| `SPI_FREQ`  | 1_000_000   | Target SCLK frequency (Hz) |
| `DATA_WIDTH`| 16          | Bits per transaction |

`HALF_PERIOD = CLK_FREQ / (2 × SPI_FREQ)`.  A clock-divider counter toggles
SCLK every `HALF_PERIOD` system clocks.

| Port        | Dir | Description |
|-------------|-----|-------------|
| `start`     | in  | One-cycle pulse — begin transaction |
| `data_in`   | in  | Data to shift out on MOSI (latched on `start`) |
| `miso`      | in  | Serial input from slave |
| `sclk`      | out | SPI clock |
| `mosi`      | out | Serial output to slave |
| `cs_n`      | out | Chip select (active-low) |
| `data_out`  | out | Received data (valid on `done` pulse) |
| `done`      | out | One-cycle pulse — transaction complete |
| `busy`      | out | High for full duration of transaction |

FSM:

```
        start
IDLE ─────────► TRANSFER ──(DATA_WIDTH edges)──► DONE ──► IDLE
  ▲               │cs_n=0                          │cs_n=1
  └───────────────┘                                │done=1
```

### `pmod_ad1_reader`

| Parameter     | Default     | Description |
|---------------|-------------|-------------|
| `CLK_FREQ`    | 100_000_000 | System clock frequency (Hz) |
| `SPI_FREQ`    | 1_000_000   | SPI clock frequency (Hz) |
| `SAMPLE_RATE` | 1000        | ADC conversions per second |

Fires a `start` pulse to `spi_master` every `CLK_FREQ / SAMPLE_RATE` clocks.
If the previous transaction is still in progress the sample is skipped.
Extracts `adc_data = data_out[11:0]` from the 16-bit AD7476A frame.

### `top`

Thin wrapper instantiating `pmod_ad1_reader`.  Connects SPI bus signals and
ADC result directly to top-level ports for synthesis or simulation.

---

## Design Decisions

**Parameterized clock divider, not a fixed divider**  
`HALF_PERIOD` is derived from `CLK_FREQ` and `SPI_FREQ` as a `localparam`.
Retargeting to a different clock or a slower slave requires no RTL changes —
only parameter overrides at instantiation.

**FSM-based control path**  
A three-state FSM (`IDLE → TRANSFER → DONE`) makes transfer sequencing
explicit and safe.  Each state has a single, well-defined purpose; illegal
state recovery (`default: state <= IDLE`) prevents hang after a glitch.

**Generic master, AD1-specific wrapper**  
`spi_master` has no knowledge of the AD7476A protocol.  The same core can
drive an SPI flash, DAC, or temperature sensor by changing `DATA_WIDTH` and
the wrapper.  `pmod_ad1_reader` encapsulates the sample timer and frame
extraction so the reusable core stays clean.

**Registered SCLK output**  
`sclk_r` is a flip-flop driven inside `always_ff`.  This eliminates
combinational glitches on the SPI clock line, which could cause spurious
edges on the slave.

---

## Verification

### `spi_master_tb.sv`

| Test | Description | Expected |
|------|-------------|----------|
| Transaction 1 RX | Slave preloaded with `0xA5`; check `data_out` | `data_out == 8'hA5` |
| Transaction 1 TX | Master sends `0x3C`; check slave captured value | `slave_rx == 8'h3C` |
| Transaction 2 RX | Slave preloaded with `0x69`; check `data_out` | `data_out == 8'h69` |
| Transaction 2 TX | Master sends `0xF0`; check slave captured value | `slave_rx == 8'hF0` |
| busy/done timing | `busy` high immediately after `start`, low after `done` | PASS |

The testbench's behavioral slave model pre-drives MISO on CS_N assertion and
updates it on each falling SCLK edge, matching SPI Mode 0 slave behavior.
SCLK edges, MOSI, and MISO values are logged with `$display` at each edge.

### `pmod_ad1_tb.sv`

| Test | ADC frame | Expected |
|------|-----------|----------|
| Sample 1 | `{4'b0000, 12'hABC}` | `adc_data == 12'hABC` |
| Sample 2 | `{4'b0000, 12'h321}` | `adc_data == 12'h321` |

The AD7476A behavioral model shifts out 16-bit frames on the SPI bus; the
testbench waits for autonomous `data_valid` pulses from `pmod_ad1_reader`.

---

## Pmod AD1 Hardware Interface

The [Digilent Pmod AD1](https://digilent.com/reference/pmod/pmodad1/start)
carries two AD7476A ADCs.  This design reads channel A (J1 connector).

| Pmod Pin | Signal  | Direction | Description |
|----------|---------|-----------|-------------|
| J1 pin 1 | CS_N_A  | FPGA → ADC | Chip select, channel A |
| J1 pin 2 | SDO_A   | ADC → FPGA | Serial data out (MISO) |
| J1 pin 3 | NC      | —          | Not connected |
| J1 pin 4 | SCLK    | FPGA → ADC | SPI clock (≤ 20 MHz) |
| J1 pin 5 | GND     | —          | Ground |
| J1 pin 6 | VCC     | —          | 3.3 V supply |

**Voltage levels:** 3.3 V logic.  The KR260 Pmod headers are 3.3 V; no
level-shifting is required.

**Data format:** Each 16-bit SPI frame contains four leading zeros followed by
the 12-bit conversion result MSB-first.  `adc_data = data_out[11:0]`.

**Maximum SCLK:** 20 MHz (AD7476A datasheet).  Default `SPI_FREQ = 1 MHz`
provides comfortable margin; increase to up to `10 MHz` for faster sampling.

---

## Hardware Deployment

Design is **simulation-verified**.  It is ready for deployment on:

- **Arty A7** — 100 MHz oscillator available directly; synthesize with Vivado,
  map `sclk/mosi/miso/cs_n` to the JA Pmod header.
- **Xilinx Kria KR260** — 100 MHz PL clock sourced from Zynq PS (`pl_clk0`);
  requires a Zynq PS block-design wrapper to bring `pl_clk0` into the PL
  fabric before synthesis.

XDC constraints and a Vivado non-project-mode `build.tcl` will be added upon
hardware bring-up.

---

## Key SystemVerilog Features

| Feature | Where used |
|---------|-----------|
| `always_ff` with `<=` | All sequential logic in `spi_master`, `pmod_ad1_reader`, `top` |
| `always_comb` / `assign` | SCLK output (`assign sclk = sclk_r`) |
| `typedef enum` | FSM state encoding in `spi_master` |
| `parameter` / `localparam` | Clock divider, timer period, bit-count widths |
| Named port connections | All module instantiations |
| `logic` throughout | No `wire` or `reg` keywords used |
| Shift registers | TX (`tx_reg`) and RX (`rx_reg`) in `spi_master` |
| Parameterized width | `[DATA_WIDTH-1:0]` buses, `$clog2`-derived counter widths |
