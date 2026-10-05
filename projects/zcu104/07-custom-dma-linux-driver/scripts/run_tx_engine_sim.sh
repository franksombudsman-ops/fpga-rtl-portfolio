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
    "$ROOT/rtl/dma_axi_read_master.sv" \
    "$ROOT/rtl/dma_tx_engine.sv" \
    "$ROOT/tb/tb_dma_tx_engine.sv"

"$VIVADO_BIN/xelab" \
    tb_dma_tx_engine \
    -s tb_dma_tx_engine_sim

"$VIVADO_BIN/xsim" \
    tb_dma_tx_engine_sim \
    -runall \
    | tee "$ROOT/reports/tx_engine_simulation.log"

grep -q "DMA TX ENGINE: PASS" \
    "$ROOT/reports/tx_engine_simulation.log"

echo
echo "TX ENGINE SIMULATION: PASS"
