#!/usr/bin/env bash

# Frank Ouma
# Project 08 - Programmable Network Processor
#
# FPGA / SoC / Digital Hardware Engineering
# Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
#
# 08K - Fast-Path Performance Qualification
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

TB="$P08/tb/tb_p08_fast_path_performance.sv"
LOG="$P08/reports/08k_fast_path_performance.log"

WORK="/tmp/project08_08k_xsim"

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
    echo " PROJECT08 08K — FAST-PATH PERFORMANCE"
    echo "============================================"
    echo

    xvlog -sv \
        "$P08/rtl/p08_packet_parser.sv" \
        "$P08/rtl/p08_match_action_engine.sv" \
        "$P08/rtl/p08_packet_action_buffer.sv" \
        "$P08/rtl/p08_packet_editor.sv" \
        "$P08/rtl/p08_egress_scheduler.sv" \
        "$P08/rtl/p08_packet_processor_core.sv" \
        "$TB"

    xelab \
        tb_p08_fast_path_performance \
        -s p08_08k_sim \
        --debug typical

    xsim \
        p08_08k_sim \
        -R

} 2>&1 | tee "$LOG"

grep -q \
    "PROJECT08 08K FAST-PATH PERFORMANCE: PASS" \
    "$LOG"

echo
echo "08K_RESULT=PASS"
