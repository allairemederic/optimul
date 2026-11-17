#!/usr/bin/env python3

import re
import sys
from pathlib import Path

if len(sys.argv) != 2:
    print("Usage: python3 scripts/generate_weights.py <ff1.cpp>")
    sys.exit(1)

text = Path(sys.argv[1]).read_text()
output_directory = Path("weights")
output_directory.mkdir(exist_ok=True)

# Keep only the initializer of ff1_W.
weights_text = text.split("const wi_ff1_t ff1_W[2][32][128] = {", 1)[1].split("const int ff1_M0", 1)[0]

weights = [int(value) for value in re.findall(r"-?\d+", weights_text)]

if len(weights) != 2 * 32 * 128:
    raise RuntimeError(f"Expected 8192 weights, found {len(weights)}.")


def get_weight(layer, n, k):
    # ff1_W[layer][n][k]
    index = layer * 32 * 128 + n * 128 + k
    return weights[index]

# (DN, DK)
configurations = [
    # DK = 32
    (1, 32),
    (2, 32),
    (4, 32),
    (8, 32),
    (16, 32),
    (32, 32),

    # DK = 64 with DM = 4
    (4, 64),   # 16 DPU
    (8, 64),   # 32 DPU
    (16, 64),  # 64 DPU
    (32, 64),  # 128 DPU
]

for dn, dk in configurations:

    output_path = output_directory / f"weights_ff1_DN{dn}_DK{dk}.mem"

    with output_path.open("w") as output_file:
        for layer in range(2):
            for n_tile in range(32 // dn):
                for plane in range(4):
                    for k_group in range(128 // dk):
                        word = 0

                        for dn_index in range(dn):
                            n = n_tile * dn + dn_index

                            for b in range(dk):
                                k = k_group * dk + b
                                weight = get_weight(layer, n, k)

                                # Select one bit from the signed 4-bit weight
                                bit = ((weight & 0xF) >> plane) & 1
                                position = dn_index * dk + b

                                word |= bit << position

                        hexadecimal_width = dn * dk // 4
                        output_file.write(f"{word:0{hexadecimal_width}x}\n")

    print(f"Generated {output_path}")