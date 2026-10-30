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

RTL="$P08/rtl/p08_control_telemetry_cdc.sv"
TB="$P08/tb/tb_p08_control_telemetry_cdc.sv"
LOG="$P08/reports/08i_control_telemetry_cdc.log"

WORK="/tmp/project08_08i_xsim"

if ! command -v xvlog >/dev/null 2>&1; then
    echo "ERROR: Vivado 2023.2 environment is not sourced."
    exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK"
mkdir -p "$(dirname "$LOG")"

cd "$WORK"

{
    echo "============================================"
    echo " PROJECT08 08I — CONTROL / TELEMETRY CDC"
    echo "============================================"
    echo

    xvlog -sv \
        "$RTL" \
        "$TB"

    xelab \
        tb_p08_control_telemetry_cdc \
        -s p08_08i_sim \
        --debug typical

    xsim \
        p08_08i_sim \
        -R

} 2>&1 | tee "$LOG"

grep -q \
    "PROJECT08 08I CONTROL/TELEMETRY CDC: PASS" \
    "$LOG"

echo
echo "08I_RESULT=PASS"
