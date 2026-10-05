#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO_BIN="/tools/Xilinx/Vivado/2023.2/bin"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$ROOT/reports"

cd "$WORK"

"$VIVADO_BIN/xvlog" --sv \
    "$ROOT/rtl/dma_irq_controller.sv" \
    "$ROOT/rtl/dma_axil_regs.sv" \
    "$ROOT/tb/tb_dma_axil_regs.sv"

"$VIVADO_BIN/xelab" \
    tb_dma_axil_regs \
    -s tb_dma_axil_regs_sim

"$VIVADO_BIN/xsim" \
    tb_dma_axil_regs_sim \
    -runall \
    | tee "$ROOT/reports/axil_regs_simulation.log"

grep -q "DMA AXI-LITE REGISTER BANK: PASS" \
    "$ROOT/reports/axil_regs_simulation.log"

echo
echo "AXI-LITE REGISTER SIMULATION: PASS"
