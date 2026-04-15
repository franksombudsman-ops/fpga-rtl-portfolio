# Debounced LED Controller

**Platform:** Xilinx Kria KR260 (Zynq UltraScale+ MPSoC, PL fabric)  
**Interface:** Pmod JA — 2 buttons in, 4 LEDs out  
**Toolchain:** Vivado 2022.x · SystemVerilog (IEEE 1800-2017)  
**Status:** RTL complete · simulation verified · constraints & implementation in progress

---

## Overview

A button-driven Johnson counter that demonstrates three fundamental RTL
disciplines in a single, self-contained design:

1. **Clock-domain crossing hygiene** — raw button signal synchronised into the
   PL clock domain via a two-flop synchroniser before any combinational logic
   touches it.

2. **Glitch-free input conditioning** — a parameterised stability counter
   enforces 10 ms of quiet before accepting a level change, eliminating
   mechanical switch bounce entirely in hardware.

3. **Structured sequential logic** — a 4-bit Johnson counter advances on each
   clean button press, producing the walking-ones/walking-zeros LED pattern
   `0000 → 1000 → 1100 → 1110 → 1111 → 0111 → 0011 → 0001 → 0000`.

---

## Architecture

```
btn_raw ──► [ 2FF sync ] ──► [ stability counter ] ──► btn_clean
                                                           │
                                                    [ edge detect ]
                                                           │ btn_pulse
                                                    [ johnson counter ] ──► leds[3:0]
```

`top.sv` wires the three stages together. The inline rising-edge detector
(one FF + combinational AND) keeps the advance pulse exactly one cycle wide
regardless of how long the button stays pressed.

### Module hierarchy

| Module | File | Function |
|---|---|---|
| `top` | `rtl/top.sv` | Top-level integration, edge detect |
| `debouncer` | `rtl/debouncer.sv` | 2FF sync + 10 ms stability counter |
| `johnson_counter` | `rtl/johnson_counter.sv` | 4-bit shift-register counter |

---

## Key design decisions

**Why a Johnson counter?**  
Adjacent states differ by exactly one bit, so the LED pattern is glitch-free:
no intermediate states where multiple outputs change simultaneously.  
Contrast with a binary counter where e.g. `0111 → 1000` flips four bits at
once — any routing skew produces visible LED glitches.

**Why 10 ms stability window?**  
Cherry MX-style switches and most TACT switches bounce for < 5 ms worst case.
10 ms gives 2× margin and is imperceptible to a human finger press.

**Why active-low reset?**  
The KR260 pushbuttons and most Xilinx primitives default to active-low.
Keeping `rst_n` consistent throughout avoids polarity inversions at module
boundaries that are a common source of reset-domain bugs.

**Why parameterised `COUNTER_WIDTH` and `STABLE_COUNT`?**  
The testbench overrides `STABLE_COUNT` to 100 cycles so the simulation runs
in microseconds rather than milliseconds, without touching the RTL.

---

## Simulation

The debouncer is verified with a directed testbench that injects 20 cycles of
synthetic bounce (alternating 17 ns / 23 ns glitches) before holding the
signal stable.

```
sim/
└── debouncer_tb.sv    # parameterised: COUNTER_WIDTH=8, STABLE_COUNT=100
```

Expected output:
```
Time(ns)   button_in  button_out
--- Pressing button (with bounce) ---
    1950      1          1       ← stable after bounce settles + 100 cycles
--- Releasing button (with bounce) ---
    ...       0          0
--- Test complete ---
```

---

## Pin assignments (Pmod JA, KR260)

> XDC constraints file: `constraints/kr260_pmod_ja.xdc` *(in progress)*

| Signal | Pmod JA pin | KR260 net |
|---|---|---|
| `btn_raw` (advance) | JA1 | — |
| `rst_n` (reset) | JA2 | — |
| `leds[0]` | JA7 | — |
| `leds[1]` | JA8 | — |
| `leds[2]` | JA9 | — |
| `leds[3]` | JA10 | — |

*KR260 net names to be populated from the KR260 Schematic (PG373) during constraints phase.*

---

## Build

> Tcl build script: `vivado/build.tcl` *(in progress)*

The KR260's PL clock is sourced from the Zynq PS block (the fabric has no
standalone oscillator), so a Block Design with a Zynq MPSoC IP instance is
required to provide `pl_clk0`. This is documented in the Vivado project
creation script.
