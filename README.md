# Optimul

BISMO-inspired bit-serial matrix multiplication for
mixed-precision neural network inference on FPGA.

The project compares C++/Vitis HLS and SystemVerilog
implementations on an Alveo U280, evaluating numerical
correctness, latency, and resource usage.

## Structure

- `RTL/` — SystemVerilog modules, testbenches, and build scripts
- `DMA/` — PCIe/QDMA integration, MicroBlaze firmware, and transfers
- `HLS/` — Reference and bit-serial C++ implementations
