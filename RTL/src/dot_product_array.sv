// Array of bit-serial dot product units
// The array processes DM activation rows and DN output columns in parallel

module dot_product_array #(
    parameter int DM = 1,   // Number of activation rows processed in parallel.
    parameter int DN = 1,   // Number of output columns processed in parallel.
    parameter int DK = 32,  // Number of bit pairs processed by each DPU
    
    parameter int COUNT_W = $clog2(DK + 1) // Width required to represent a popcount from 0 to DK
) (
    input logic [DM-1:0][DK-1:0] activation_bits, // One DK-bit activation vector for each parallel row
    input logic [DN-1:0][DK-1:0] weight_bits,     // One DK-bit weight vector for each parallel output column

    output logic [DM-1:0][DN-1:0][COUNT_W-1:0] counts // Popcount result produced for each row-column pair
);

    genvar dm;
    genvar dn;

    // Create a DM-by-DN array of independent DPUs
    generate
        for (dm = 0; dm < DM; dm++) begin : gen_rows
            for (dn = 0; dn < DN; dn++) begin : gen_columns
                bitserial_dpu #(
                    .DK(DK),
                    .COUNT_W(COUNT_W)
                ) dpu (
                    .a_bits(activation_bits[dm]), // Broadcast one activation vector across the row
                    .w_bits(weight_bits[dn]),     // Broadcast one weight vector across the column
                    .count(counts[dm][dn])        // Store the partial result for this row-column pair
                );
            end
        end
    endgenerate

endmodule