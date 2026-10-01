#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
P06="$ROOT/projects/zcu104/06-streaming-dsp-accelerator-soc"

RTL="$P06/rtl/moving_energy64_axis.sv"
TB="$P06/tb/tb_moving_energy64_axis.sv"
VECTORS="$P06/tb/vectors"

LOG="$P06/reports/energy64_simulation.log"

TMP="/tmp/project06_energy64_sim"

rm -rf "$TMP"
mkdir -p "$TMP"

echo "============================================================"
echo "PROJECT06 ENERGY64 SELF-CHECKING SIMULATION"
echo "============================================================"

echo "RTL     : $RTL"
echo "TB      : $TB"
echo "Vectors : $VECTORS"
echo

cd "$TMP"

xvlog --sv \
    "$RTL" \
    "$TB"

xelab \
    tb_moving_energy64_axis \
    -s energy64_snapshot

xsim energy64_snapshot \
    -testplusarg "VECTOR_ROOT=$VECTORS" \
    -runall \
    | tee "$LOG"

echo
echo "Simulation log:"
echo "$LOG"
