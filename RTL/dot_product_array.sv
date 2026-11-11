// Array of parallel bit-serial dot product units

module dot_product_array #(
    parameter int DK = 32,                 // Number of bit pairs processed by each DPU
    parameter int NUM_DPU = 1,             // Number of DPUs operating in parallel
    parameter int COUNT_W = $clog2(DK + 1) // Width of each popcount result
) (
    input  logic [NUM_DPU-1:0][DK-1:0] a_bits,     // Activation vector provided to each DPU
    input  logic [NUM_DPU-1:0][DK-1:0] w_bits,     // Weight vector provided to each DPU
    output logic [NUM_DPU-1:0][COUNT_W-1:0] counts // Popcount result produced by each DPU
);

    genvar d;

    // Create NUM_DPU independent DPUs
    generate
        for (d = 0; d < NUM_DPU; d++) begin : gen_dpu
            bitserial_dpu #(
                .DK(DK),
                .COUNT_W(COUNT_W)
            ) dpu (
                .a_bits(a_bits[d]),
                .w_bits(w_bits[d]),
                .count(counts[d])
            );
        end
    endgenerate

endmodule