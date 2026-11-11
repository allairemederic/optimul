#!/usr/bin/env bash

# Run one Transformer inference through QDMA.
#
# Assumptions:
#   - The QDMA queue is already configured in Memory-Mapped mode.
#   - The QDMA device is /dev/qdma01000-MM-0.
#   - The shared BRAM starts at AXI address 0x00000000.
#   - input.bin contains 128 signed int32 values in Q22 format.
#   - output.bin will contain 128 float32 values.
#   - The MicroBlaze and performance counter run at 100 MHz.
#
# Shared BRAM memory map:
#   0x0000 - 0x07FF : Transformer input
#   0x0800 - 0x0FFF : Transformer output
#   0x1000          : Command
#   0x1004          : Status
#   0x1008          : Cycle count, low 32 bits
#   0x100C          : Cycle count, high 32 bits
#
# Command values:
#   0 = No command
#   1 = Start inference
#
# Status values:
#   0 = Idle
#   1 = Busy
#   2 = Done
#   3 = Error
#
# Usage:
#   chmod +x run_transformer_qdma.sh
#   ./run_transformer_qdma.sh

set -e

temporary_directory="$(mktemp -d)"
trap 'rm -rf "${temporary_directory}"' EXIT

# Write the Transformer input into the shared BRAM.
echo "Sending input data..."

sudo dma-to-device -d /dev/qdma01000-MM-0 -a 0x0000 -s 512 -f input.bin

# Create a 32-bit little-endian START command.
printf '\x01\x00\x00\x00' > "${temporary_directory}/start.bin"

# Send START only after the input transfer is complete.
echo "Starting the Transformer..."

sudo dma-to-device -d /dev/qdma01000-MM-0 -a 0x1000 -s 4 -f "${temporary_directory}/start.bin"

# Poll the status register until the MicroBlaze reports DONE.
echo "Waiting for inference completion..."

while true; do
    touch "${temporary_directory}/status.bin"

    sudo dma-from-device -d /dev/qdma01000-MM-0 -a 0x1004 -s 4 -f "${temporary_directory}/status.bin" > /dev/null

    status="$(od -An -tu4 -N4 "${temporary_directory}/status.bin" | tr -d '[:space:]')"

    if [[ "${status}" == "2" ]]; then
        echo "Inference completed."
        break
    fi

    if [[ "${status}" == "3" ]]; then
        echo "The MicroBlaze reported an error."
        exit 1
    fi

    sleep 0.05
done

# Read the Transformer output from the shared BRAM.
echo "Reading output data..."

touch output.bin

sudo dma-from-device -d /dev/qdma01000-MM-0 -a 0x0200 -s 512 -f output.bin

# Read the 64-bit cycle counter.
touch "${temporary_directory}/cycles.bin"

sudo dma-from-device -d /dev/qdma01000-MM-0 -a 0x1008 -s 8 -f "${temporary_directory}/cycles.bin" > /dev/null

# The first value contains the low 32 bits.
# The second value contains the high 32 bits.
read -r cycles_low cycles_high < <(od -An -tu4 -N8 "${temporary_directory}/cycles.bin")

cycles="$(( (cycles_high << 32) | cycles_low ))"

# At 100 MHz, one millisecond corresponds to 100,000 cycles.
latency_ms="$(awk -v cycles="${cycles}" 'BEGIN { printf "%.6f", cycles / 100000.0 }')"

echo
echo "Output written to output.bin"
echo "Cycle count: ${cycles}"
echo "Latency: ${latency_ms} ms"