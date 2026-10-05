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
    "$ROOT/rtl/dma_axi_write_master.sv" \
    "$ROOT/rtl/dma_descriptor_parser.sv" \
    "$ROOT/rtl/dma_ring_manager.sv" \
    "$ROOT/rtl/dma_descriptor_engine.sv" \
    "$ROOT/tb/tb_dma_descriptor_engine.sv"

"$VIVADO_BIN/xelab" \
    tb_dma_descriptor_engine \
    -s tb_dma_descriptor_engine_sim

"$VIVADO_BIN/xsim" \
    tb_dma_descriptor_engine_sim \
    -runall \
    | tee "$ROOT/reports/descriptor_engine_simulation.log"

grep -q "DMA DESCRIPTOR ENGINE: PASS" \
    "$ROOT/reports/descriptor_engine_simulation.log"

echo
echo "DESCRIPTOR ENGINE SIMULATION: PASS"
