#!/usr/bin/env bash

# Frank Ouma
# Project 08 - Programmable Network Processor
#
# FPGA / SoC / Digital Hardware Engineering
# Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
#
# Author: Frank Ouma
# Email: frankotieno254@gmail.com
# Contact: +254725582132
#
# Copyright (c) 2026 Frank Ouma.
# All rights reserved.

set -euo pipefail

REPO="$HOME/fpga-rtl-portfolio"
P08="$REPO/projects/zcu104/08-programmable-network-processor"
TB="$P08/tb/tb_axis_stream_infrastructure.sv"
LOG="$P08/reports/08b_axis_stream_infrastructure.log"
WORK="/tmp/project08_08b_xsim"

if ! command -v xvlog >/dev/null 2>&1; then
    echo "ERROR: Vivado 2023.2 environment is not sourced."
    echo "Open the established Vivado shell/environment and rerun."
    exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"
mkdir -p "$(dirname "$LOG")"

cd "$WORK"

{
    echo "============================================"
    echo " PROJECT08 08B — AXI-STREAM VERIFICATION"
    echo "============================================"
    echo

    xvlog -sv "$TB"

    xelab \
        tb_axis_stream_infrastructure \
        -s p08_08b_sim \
        --debug typical

    xsim \
        p08_08b_sim \
        -R

} 2>&1 | tee "$LOG"

grep -q \
    "PROJECT08 08B AXI-STREAM INFRASTRUCTURE: PASS" \
    "$LOG"

echo
echo "08B_RESULT=PASS" | tee -a "$LOG"
