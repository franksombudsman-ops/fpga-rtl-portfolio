#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO_BIN="/tools/Xilinx/Vivado/2023.2/bin"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$ROOT/reports"

cd "$WORK"

"$VIVADO_BIN/xvlog" --sv \
    "$ROOT/rtl/dma_descriptor_parser.sv" \
    "$ROOT/rtl/dma_ring_manager.sv" \
    "$ROOT/tb/tb_dma_descriptor_parser.sv" \
    "$ROOT/tb/tb_dma_ring_manager.sv"

"$VIVADO_BIN/xelab" \
    tb_dma_descriptor_parser \
    -s tb_dma_descriptor_parser_sim

"$VIVADO_BIN/xsim" \
    tb_dma_descriptor_parser_sim \
    -runall \
    | tee "$ROOT/reports/descriptor_parser_simulation.log"

grep -q "DMA DESCRIPTOR PARSER: PASS" \
    "$ROOT/reports/descriptor_parser_simulation.log"

"$VIVADO_BIN/xelab" \
    tb_dma_ring_manager \
    -s tb_dma_ring_manager_sim

"$VIVADO_BIN/xsim" \
    tb_dma_ring_manager_sim \
    -runall \
    | tee "$ROOT/reports/ring_manager_simulation.log"

grep -q "DMA RING MANAGER: PASS" \
    "$ROOT/reports/ring_manager_simulation.log"

echo
echo "DESCRIPTOR PARSER + RING MANAGER: PASS"
