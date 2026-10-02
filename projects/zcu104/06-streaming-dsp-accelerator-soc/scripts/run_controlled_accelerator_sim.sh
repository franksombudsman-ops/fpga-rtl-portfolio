#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
P06="$ROOT/projects/zcu104/06-streaming-dsp-accelerator-soc"

LOG="$P06/reports/controlled_accelerator_simulation.log"
TMP="/tmp/project06_controlled_accelerator_sim"

rm -rf "$TMP"
mkdir -p "$TMP"

cd "$TMP"

echo "============================================================"
echo "PROJECT06 CONTROLLED ACCELERATOR SIMULATION"
echo "============================================================"

xvlog --sv \
"$P06/rtl/accelerator_axil_regs.sv" \
"$P06/rtl/fir32_axis.sv" \
"$P06/rtl/moving_energy64_axis.sv" \
"$P06/rtl/dsp_accelerator_core.sv" \
"$P06/rtl/energy_event_axis_cfg.sv" \
"$P06/rtl/dsp_accelerator_controlled.sv" \
"$P06/tb/tb_dsp_accelerator_controlled.sv"

xelab \
tb_dsp_accelerator_controlled \
-s controlled_accelerator_snapshot

xsim controlled_accelerator_snapshot \
-testplusarg "VECTOR_ROOT=$P06/tb/vectors" \
-runall \
| tee "$LOG"

echo
echo "Simulation log:"
echo "$LOG"
