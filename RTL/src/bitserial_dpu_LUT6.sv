// Computes a binary dot product using a fused AND-popcount
// Three binary products are pre-compressed into a two-bit count
// Each group can be implemented using two 6-input LUT

module bitserial_dpu #(
    parameter int DK = 32,
    parameter int COUNT_W = $clog2(DK + 1)
) (
    input  logic [DK-1:0] a_bits,
    input  logic [DK-1:0] w_bits,
    output logic [COUNT_W-1:0] count
);

    // Number of groups containing up to three bit products
    localparam int NUM_GROUPS = (DK + 2) / 3;

    // Each group produces a value between zero and three
    logic [1:0] group_counts [0:NUM_GROUPS-1];

    genvar group;

    generate
        for (group = 0; group < NUM_GROUPS; group++) begin : gen_precompression

            localparam int BASE = 3 * group;

            logic product_0;
            logic product_1;
            logic product_2;

            // The first product always exists
            assign product_0 =  a_bits[BASE] & w_bits[BASE];

            // Missing products in the last group are replaced by zero
            if ((BASE + 1) < DK) begin : gen_product_1
                assign product_1 = a_bits[BASE + 1] & w_bits[BASE + 1];
            end
            else begin : gen_no_product_1
                assign product_1 = 1'b0;
            end

            if ((BASE + 2) < DK) begin : gen_product_2
                assign product_2 = a_bits[BASE + 2] & w_bits[BASE + 2];
            end
            else begin : gen_no_product_2
                assign product_2 = 1'b0;
            end

            // Least-significant bit of the three-product count
            assign group_counts[group][0] = product_0 ^ product_1 ^ product_2;

            // Most-significant bit of the three-product count
            assign group_counts[group][1] = (product_0 & product_1) | (product_0 & product_2) | (product_1 & product_2);

        end
    endgenerate

    integer group_index;

    // Add all pre-compressed groups to obtain the final popcount
    always_comb begin
        count = '0;

        for (group_index = 0; group_index < NUM_GROUPS; group_index++) begin
            count = count + group_counts[group_index];
        end
    end

endmodule