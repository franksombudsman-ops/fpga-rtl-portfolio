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
    "$ROOT/tb/tb_dma_irq_controller.sv"

"$VIVADO_BIN/xelab" \
    tb_dma_irq_controller \
    -s tb_dma_irq_controller_sim

"$VIVADO_BIN/xsim" \
    tb_dma_irq_controller_sim \
    -runall \
    | tee "$ROOT/reports/irq_controller_simulation.log"

grep -q "DMA IRQ CONTROLLER: PASS" \
    "$ROOT/reports/irq_controller_simulation.log"

echo
echo "IRQ CONTROLLER SIMULATION: PASS"
