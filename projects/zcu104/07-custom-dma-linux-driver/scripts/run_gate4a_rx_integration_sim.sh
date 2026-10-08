#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO_BIN="/tools/Xilinx/Vivado/2023.2/bin"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$ROOT/reports"

cd "$WORK"

"$VIVADO_BIN/xvlog" \
    --sv \
    -d GATE4A_RX64 \
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
    -s tb_gate4a_rx_integration_sim

"$VIVADO_BIN/xsim" \
    tb_gate4a_rx_integration_sim \
    -runall \
    | tee "$ROOT/reports/gate4a_rx_integration_simulation.log"

grep -q \
    "GATE 4A 64-BYTE RX INTEGRATION: PASS" \
    "$ROOT/reports/gate4a_rx_integration_simulation.log"

echo
echo "GATE 4A RX INTEGRATION SIMULATION: PASS"
