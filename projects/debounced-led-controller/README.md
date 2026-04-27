# Debounced LED Controller

**Platform:** Xilinx Kria KR260 (Zynq UltraScale+, PL fabric)  
**Interface:** Pmod 1 (J2) — 2 buttons in, 3 LEDs out  
**Toolchain:** Vivado 2022.x · SystemVerilog (IEEE 1800-2017)  
**Status:** RTL complete · simulation verified · constraints complete · implementation in progress

---

## Overview

A button-driven 3-bit Johnson counter that demonstrates three fundamental RTL
disciplines in a single, self-contained design:

1. **Clock-domain crossing hygiene** — the raw button signal is synchronised into
   the PL clock domain via a two-flop synchroniser before any combinational
   logic touches it.

2. **Glitch-free input conditioning** — a parameterised stability counter enforces
   10 ms of electrical quiet before accepting a level change, eliminating
   mechanical switch bounce entirely in hardware.

3. **Structured sequential logic** — a 3-bit Johnson counter advances on each
   clean button press, producing the walking-ones / walking-zeros LED pattern:

   ```
   000 → 100 → 110 → 111 → 011 → 001 → 000 → ...
   ```

   Adjacent states always differ by exactly **one bit**, so the display is
   glitch-free regardless of routing skew.

---

## Architecture

```
                  ┌──────────────────────────────────────────────────────┐
                  │                      top.sv                          │
                  │                                                      │
btn_raw ──────────►  ┌─────────────┐   btn_clean  ┌──────────────────┐  │
                  │  │  debouncer  ├──────────────►│  edge detector   │  │
                  │  │             │               │  (FF + AND)      │  │
                  │  │  2FF sync   │               └────────┬─────────┘  │
                  │  │  + stability│                        │ btn_pulse  │
                  │  │  counter    │               ┌────────▼─────────┐  │
                  │  └─────────────┘               │ johnson_counter  ├──►  leds[2:0]
                  │                                │  WIDTH=3         │  │
                  │                                └──────────────────┘  │
                  └──────────────────────────────────────────────────────┘
```

### Module hierarchy

| Module            | File                    | Function                               |
|-------------------|-------------------------|----------------------------------------|
| `top`             | `rtl/top.sv`            | Top-level integration; inline edge detect |
| `debouncer`       | `rtl/debouncer.sv`      | 2FF CDC sync + 10 ms stability counter |
| `johnson_counter` | `rtl/johnson_counter.sv`| 3-bit right-shift Johnson counter      |

---

## Key design decisions

**Why a Johnson counter instead of a binary counter?**  
Adjacent Johnson states differ by exactly one bit — `110 → 111` flips one LED,
`0111 → 1000` (binary) flips four simultaneously. Any routing skew on a binary
counter produces visible multi-LED glitches. The Johnson sequence is inherently
glitch-free.

**Why 10 ms stability window?**  
Cherry MX-style and most TACT switches bounce for under 5 ms worst case.
10 ms gives a comfortable 2× margin and is imperceptible as input latency.

**Why active-low reset?**  
KR260 Pmod I/O with a pull-up naturally produces active-low: the button
connects the pin to GND when pressed. Matching reset polarity throughout the
hierarchy avoids inversion bugs at module boundaries.

**Why parameterised `COUNTER_WIDTH` and `STABLE_COUNT`?**  
The testbench overrides `STABLE_COUNT` to 100 cycles so simulations complete in
microseconds without touching RTL. Hardware gets `STABLE_COUNT = 1_000_000`
(10 ms at 100 MHz).

**Why is `clk` routed through Zynq PS?**  
The KR260 PL fabric has no standalone oscillator — all PL clocks come from
the Zynq PS `pl_clkN` outputs. A Block Design wrapping the Zynq MPSoC IP
provides `pl_clk0` at 100 MHz to the top-level.

---

## Simulation

The debouncer is verified with a directed testbench that injects 20 cycles of
synthetic bounce (alternating 17 ns / 23 ns glitches) before holding the signal
stable for 5 µs — well past the 1 µs threshold used in simulation.

```
sim/
└── debouncer_tb.sv    # COUNTER_WIDTH=8, STABLE_COUNT=100 (100-cycle window)
```

**Running in Vivado XSim:**
```tcl
xvlog --sv sim/debouncer_tb.sv rtl/debouncer.sv
xelab debouncer_tb -snapshot debouncer_tb_snap
xsim debouncer_tb_snap --runall
```

**Expected output:**
```
Time(ns)   button_in  button_out
--- Pressing button (with bounce) ---
    1950      1          1       ← stable after bounce + 100-cycle window
--- Releasing button (with bounce) ---
    8910      0          0
--- Test complete ---
```

---

## Pin assignments (Pmod 1 / J2, KR260)

Constraints file: `constraints/kr260_pmod1.xdc`

| Signal        | Direction | Pmod 1 pin | FPGA ball | IOSTANDARD | Notes                          |
|---------------|-----------|------------|-----------|------------|--------------------------------|
| `leds[0]`     | output    | P1         | H12       | LVCMOS33   |                                |
| `leds[1]`     | output    | P2         | E10       | LVCMOS33   |                                |
| `leds[2]`     | output    | P3         | D10       | LVCMOS33   |                                |
| `btn_raw`     | input     | P4         | C11       | LVCMOS33   | Active-high; PULLDOWN on board |
| `rst_n`       | input     | P7         | B10       | LVCMOS33   | Active-low; PULLUP on board    |

---

## Build

Tcl script: `vivado/build.tcl`

The script runs synthesis and implementation in non-project (batch) mode and
writes timing, utilisation, and DRC reports to `vivado/output/`.

```bash
cd projects/debounced-led-controller/vivado
vivado -mode batch -source build.tcl
```

> **Note:** Full bitstream generation requires wrapping `top` in a Block Design
> that instantiates the Zynq MPSoC IP to supply `pl_clk0`. The script performs
> out-of-context synthesis for RTL verification until the BD wrapper is added.

---

## File tree

```
debounced-led-controller/
├── constraints/
│   └── kr260_pmod1.xdc      # Pmod 1 (J2) pin assignments
├── rtl/
│   ├── debouncer.sv         # 2FF sync + stability counter
│   ├── johnson_counter.sv   # 3-bit Johnson shift register
│   └── top.sv               # Integration + edge detect
├── sim/
│   └── debouncer_tb.sv      # Directed bounce testbench
└── vivado/
    └── build.tcl            # Non-project-mode build script
```
