#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO_BIN="/tools/Xilinx/Vivado/2023.2/bin"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$ROOT/reports"

cd "$WORK"

"$VIVADO_BIN/xvlog" --sv \
    "$ROOT/rtl/dma_burst_planner.sv" \
    "$ROOT/tb/tb_dma_burst_planner.sv"

"$VIVADO_BIN/xelab" \
    tb_dma_burst_planner \
    -s tb_dma_burst_planner_sim

"$VIVADO_BIN/xsim" \
    tb_dma_burst_planner_sim \
    -runall \
    | tee "$ROOT/reports/burst_planner_simulation.log"

grep -q "DMA BURST PLANNER: PASS" \
    "$ROOT/reports/burst_planner_simulation.log"

echo
echo "BURST PLANNER SIMULATION: PASS"
