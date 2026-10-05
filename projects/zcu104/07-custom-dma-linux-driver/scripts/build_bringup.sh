#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VIVADO="/tools/Xilinx/Vivado/2023.2/bin/vivado"

mkdir -p "$ROOT/reports"

echo
echo "=============================================="
echo "PACKAGING PROJECT 07 BRING-UP AXI IP"
echo "=============================================="

"$VIVADO" \
    -mode batch \
    -source "$ROOT/vivado/package_bringup_ip.tcl" \
    2>&1 | tee "$ROOT/reports/bringup_ip_package.log"

echo
echo "=============================================="
echo "BUILDING PROJECT 07 ZCU104 BRING-UP BITSTREAM"
echo "=============================================="

"$VIVADO" \
    -mode batch \
    -source "$ROOT/vivado/build_bringup.tcl" \
    2>&1 | tee "$ROOT/reports/bringup_build.log"
