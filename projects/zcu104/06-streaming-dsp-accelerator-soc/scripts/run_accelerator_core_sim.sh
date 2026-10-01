#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
P06="$ROOT/projects/zcu104/06-streaming-dsp-accelerator-soc"

FIR="$P06/rtl/fir32_axis.sv"
ENERGY="$P06/rtl/moving_energy64_axis.sv"
CORE="$P06/rtl/dsp_accelerator_core.sv"
TB="$P06/tb/tb_dsp_accelerator_core.sv"

VECTORS="$P06/tb/vectors"
LOG="$P06/reports/accelerator_core_simulation.log"

TMP="/tmp/project06_accelerator_core_sim"

rm -rf "$TMP"
mkdir -p "$TMP"

echo "============================================================"
echo "PROJECT06 COMBINED ACCELERATOR SIMULATION"
echo "============================================================"
echo "FIR     : $FIR"
echo "ENERGY  : $ENERGY"
echo "CORE    : $CORE"
echo "TB      : $TB"
echo "Vectors : $VECTORS"
echo

cd "$TMP"

xvlog --sv \
    "$FIR" \
    "$ENERGY" \
    "$CORE" \
    "$TB"

xelab \
    tb_dsp_accelerator_core \
    -s accelerator_core_snapshot

xsim accelerator_core_snapshot \
    -testplusarg "VECTOR_ROOT=$VECTORS" \
    -runall \
    | tee "$LOG"

echo
echo "Simulation log:"
echo "$LOG"
