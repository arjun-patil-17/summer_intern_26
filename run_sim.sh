#!/bin/bash

# Exit immediately if any command fails (returns a non-zero exit code)
set -e

# Clear the terminal screen for clean logging visibility

echo "===================================================="
echo " STEP 1: Running CIFAR-10 Image Processor Data Extraction"
echo "===================================================="
python3 image_processor.py
echo "✓ Image asset matrices generated successfully."
echo ""

echo "===================================================="
echo " STEP 2: Compiling RTL & C Source via Verilator toolchain"
echo "===================================================="
./build_soc.sh
echo "✓ SoC Hardware/Software compilation complete."
echo ""

echo "===================================================="
echo " STEP 3: Executing Hardware Simulation Engine"
echo "===================================================="
./obj_dir/Vriscv_soc

echo ""
echo "===================================================="
echo " Processing Pipeline Completed Successfully! "
echo "===================================================="
