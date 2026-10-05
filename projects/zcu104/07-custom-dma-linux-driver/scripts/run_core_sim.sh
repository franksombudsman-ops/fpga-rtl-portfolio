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
    "$ROOT/rtl/dma_descriptor_parser.sv" \
    "$ROOT/rtl/dma_ring_manager.sv" \
    "$ROOT/rtl/dma_axi_read_master.sv" \
    "$ROOT/rtl/dma_axi_write_master.sv" \
    "$ROOT/rtl/dma_descriptor_engine.sv" \
    "$ROOT/rtl/dma_tx_engine.sv" \
    "$ROOT/rtl/dma_rx_engine.sv" \
    "$ROOT/rtl/dma_read_arbiter.sv" \
    "$ROOT/rtl/dma_write_arbiter.sv" \
    "$ROOT/rtl/dma_core.sv" \
    "$ROOT/tb/tb_dma_core.sv"

"$VIVADO_BIN/xelab" \
    tb_dma_core \
    -s tb_dma_core_sim

"$VIVADO_BIN/xsim" \
    tb_dma_core_sim \
    -runall \
    | tee "$ROOT/reports/core_integration_simulation.log"

grep -q "INTEGRATED BIDIRECTIONAL DMA CORE: PASS" \
    "$ROOT/reports/core_integration_simulation.log"

echo
echo "DMA CORE INTEGRATION SIMULATION: PASS"
