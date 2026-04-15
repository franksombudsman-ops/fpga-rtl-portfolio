# FPGA RTL Portfolio

Synthesizable SystemVerilog designs targeting the **Xilinx Kria KR260** (Zynq UltraScale+ MPSoC).  
Each project lives in `projects/` with its own README, constraints, and simulation.

## Projects

| Project | Status | Key Techniques |
|---|---|---|
| [debounced-led-controller](projects/debounced-led-controller/) | In progress — constraints & implementation | CDC synchronizer, FSM-less debounce, Johnson counter, edge detect |

## Toolchain

- **Synthesis & Implementation:** Vivado 2022.x (non-project mode scripts planned)
- **Simulation:** Vivado XSim / ModelSim
- **Target board:** Xilinx Kria KR260 Robotics Starter Kit
- **Language:** SystemVerilog (IEEE 1800-2017)

## Repo conventions

- RTL lives in `rtl/` — one module per file, filename matches module name
- Testbenches in `sim/` — parameterized for fast simulation (reduced stable counts, etc.)
- Constraints in `constraints/` — board-specific XDC
- `vivado/` holds Tcl scripts to recreate the project non-interactively (no `.xpr` committed)
