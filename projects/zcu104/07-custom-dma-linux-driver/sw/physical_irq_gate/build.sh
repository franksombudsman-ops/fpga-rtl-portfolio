#!/usr/bin/env bash
set -euo pipefail

AARCH64=/tools/Xilinx/Vitis/2023.2/gnu/aarch64/lin/aarch64-none/bin

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

"$AARCH64/aarch64-none-elf-gcc" \
    -mcpu=cortex-a53 \
    -ffreestanding \
    -nostdlib \
    -c irq_test.S \
    -o irq_test.o

"$AARCH64/aarch64-none-elf-gcc" \
    -mcpu=cortex-a53 \
    -nostdlib \
    -nostartfiles \
    -Wl,--build-id=none \
    -Wl,-T,linker.ld \
    -Wl,-Map,irq_test.map \
    irq_test.o \
    -o irq_test.elf

"$AARCH64/aarch64-none-elf-size" irq_test.elf
"$AARCH64/aarch64-none-elf-readelf" -h irq_test.elf \
    | grep -E 'Machine|Entry'
