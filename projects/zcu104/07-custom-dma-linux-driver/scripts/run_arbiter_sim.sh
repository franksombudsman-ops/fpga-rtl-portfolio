#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO_BIN="/tools/Xilinx/Vivado/2023.2/bin"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$ROOT/reports"

cd "$WORK"

"$VIVADO_BIN/xvlog" --sv \
    "$ROOT/rtl/dma_read_arbiter.sv" \
    "$ROOT/rtl/dma_write_arbiter.sv" \
    "$ROOT/tb/tb_dma_arbiters.sv"

"$VIVADO_BIN/xelab" \
    tb_dma_arbiters \
    -s tb_dma_arbiters_sim

"$VIVADO_BIN/xsim" \
    tb_dma_arbiters_sim \
    -runall \
    | tee "$ROOT/reports/arbiter_simulation.log"

grep -q "DMA MEMORY ARBITERS: PASS" \
    "$ROOT/reports/arbiter_simulation.log"

echo
echo "MEMORY ARBITER SIMULATION: PASS"
