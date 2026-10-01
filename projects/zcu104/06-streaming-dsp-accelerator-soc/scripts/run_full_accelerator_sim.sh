#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
P06="$ROOT/projects/zcu104/06-streaming-dsp-accelerator-soc"

LOG="$P06/reports/full_accelerator_simulation.log"
TMP="/tmp/project06_full_accelerator_sim"

rm -rf "$TMP"
mkdir -p "$TMP"

cd "$TMP"

xvlog --sv \
    "$P06/rtl/fir32_axis.sv" \
    "$P06/rtl/moving_energy64_axis.sv" \
    "$P06/rtl/dsp_accelerator_core.sv" \
    "$P06/rtl/energy_event_axis.sv" \
    "$P06/rtl/dsp_accelerator_full.sv" \
    "$P06/tb/tb_dsp_accelerator_full.sv"

xelab \
    tb_dsp_accelerator_full \
    -s full_accelerator_snapshot

xsim full_accelerator_snapshot \
    -testplusarg "VECTOR_ROOT=$P06/tb/vectors" \
    -runall \
    | tee "$LOG"

echo
echo "Simulation log:"
echo "$LOG"
