#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
P06="$ROOT/projects/zcu104/06-streaming-dsp-accelerator-soc"

RTL="$P06/rtl/fir32_axis.sv"
TB="$P06/tb/tb_fir32_axis.sv"
VECTORS="$P06/tb/vectors"
LOG="$P06/reports/fir32_simulation.log"

TMP="/tmp/project06_fir32_sim"
rm -rf "$TMP"
mkdir -p "$TMP"

echo "============================================================"
echo "PROJECT06 FIR32 SELF-CHECKING SIMULATION"
echo "============================================================"
echo "RTL     : $RTL"
echo "TB      : $TB"
echo "Vectors : $VECTORS"
echo

if command -v iverilog >/dev/null 2>&1 &&
   command -v vvp >/dev/null 2>&1; then

    echo "Simulator: Icarus Verilog"
    echo

    iverilog \
        -g2012 \
        -Wall \
        -s tb_fir32_axis \
        -o "$TMP/fir32_sim" \
        "$RTL" \
        "$TB"

    vvp "$TMP/fir32_sim" \
        "+VECTOR_ROOT=$VECTORS" \
        | tee "$LOG"

elif command -v xvlog >/dev/null 2>&1 &&
     command -v xelab >/dev/null 2>&1 &&
     command -v xsim >/dev/null 2>&1; then

    echo "Simulator: AMD Vivado XSIM"
    echo

    cd "$TMP"

    xvlog --sv "$RTL" "$TB"

    xelab \
        tb_fir32_axis \
        -s fir32_snapshot

    xsim fir32_snapshot \
        -testplusarg "VECTOR_ROOT=$VECTORS" \
        -runall \
        | tee "$LOG"

else
    echo "ERROR: No supported simulator found."
    echo
    echo "Expected either:"
    echo "  iverilog + vvp"
    echo "or:"
    echo "  xvlog + xelab + xsim"
    echo
    echo "If Vivado 2023.2 is installed but not in PATH,"
    echo "source its settings64.sh and rerun this script."
    exit 1
fi

echo
echo "Simulation log:"
echo "$LOG"
