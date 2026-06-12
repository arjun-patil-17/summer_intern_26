#!/bin/bash
set -e

CC=riscv64-unknown-elf-gcc
OBJCOPY=riscv64-unknown-elf-objcopy
OBJDUMP=riscv64-unknown-elf-objdump

echo "============================================"
echo " Step 1: Compile main_soc.c"
echo "============================================"
$CC \
  -march=rv32i_zicsr \
  -mabi=ilp32 \
  -O2 \
  -std=c99 \
  -ffreestanding \
  -nostdlib \
  -nostartfiles \
  -fno-builtin \
  -Wall \
  -I. \
  boot.S \
  main_soc.c \
  -T link_soc.ld \
  -o output.elf
echo "[OK] Compiled."

echo ""
echo "============================================"
echo " Step 2: Disassembly"
echo "============================================"
$OBJDUMP -d output.elf > output.dis
echo "[OK] output.dis written"

echo ""
echo "============================================"
echo " Step 3+4: Extract inst.mem and data.mem"
echo "============================================"
$OBJCOPY -O verilog output.elf full.mem
python3 split_mem.py
echo "[OK] inst.mem and data.mem written"

echo ""
echo "============================================"
echo " Step 5: Size report"
echo "============================================"
riscv64-unknown-elf-size output.elf
head -3 inst.mem   # should show @00000000
head -3 data.mem   # should show @00000000 (after replacement)
tail -3 inst.mem   # verify not truncated
wc -l data.mem     # should be larger than diabetes model (weights are bigger)
echo ""
echo "============================================"
echo " Build complete!"
echo " Run: iverilog -o sim.vvp riscv_soc.v && vvp sim.vvp"
echo "============================================"
