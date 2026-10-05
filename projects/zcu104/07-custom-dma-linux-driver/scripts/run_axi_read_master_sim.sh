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
    "$ROOT/tb/tb_dma_axi_read_master.sv"

"$VIVADO_BIN/xelab" \
    tb_dma_axi_read_master \
    -s tb_dma_axi_read_master_sim

"$VIVADO_BIN/xsim" \
    tb_dma_axi_read_master_sim \
    -runall \
    | tee "$ROOT/reports/axi_read_master_simulation.log"

grep -q "DMA AXI READ MASTER: PASS" \
    "$ROOT/reports/axi_read_master_simulation.log"

echo
echo "AXI READ MASTER SIMULATION: PASS"
