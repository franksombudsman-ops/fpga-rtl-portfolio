#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
P06="$ROOT/projects/zcu104/06-streaming-dsp-accelerator-soc"

RTL="$P06/rtl/accelerator_axil_regs.sv"
TB="$P06/tb/tb_accelerator_axil_regs.sv"

LOG="$P06/reports/axil_regs_simulation.log"

TMP="/tmp/project06_axil_regs_sim"

rm -rf "$TMP"
mkdir -p "$TMP"

cd "$TMP"

echo "============================================================"
echo "PROJECT06 AXI4-LITE REGISTER VERIFICATION"
echo "============================================================"

xvlog --sv \
    "$RTL" \
    "$TB"

xelab \
    tb_accelerator_axil_regs \
    -s axil_regs_snapshot

xsim axil_regs_snapshot \
    -runall \
    | tee "$LOG"

echo
echo "Simulation log:"
echo "$LOG"
