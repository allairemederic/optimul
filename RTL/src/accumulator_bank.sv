// Bank of weighted accumulators
// One accumulator is created for each DPA row-column pair

module accumulator_bank #(
    parameter int DM = 1,
    parameter int DN = 1,
    parameter int DK = 32,
    parameter int ACT_PLANES = 3,
    parameter int WEIGHT_BITS = 4,
    parameter int ACC_W = 16,
    parameter int COUNT_W = $clog2(DK + 1),
    parameter int ACT_PLANE_W = $clog2(ACT_PLANES),
    parameter int WEIGHT_PLANE_W = $clog2(WEIGHT_BITS)
) (
    input logic clk,
    input logic reset,

    // Common control signals for all accumulators
    input logic clear,
    input logic enable,

    // One popcount value for each DPU
    input logic [DM-1:0][DN-1:0][COUNT_W-1:0] popcounts,

    // Current bit-plane indices shared by all accumulators
    input logic [ACT_PLANE_W-1:0] activation_plane,
    input logic [WEIGHT_PLANE_W-1:0] weight_plane,

    // One accumulated result for each DPU
    output logic signed [DM-1:0][DN-1:0][ACC_W-1:0] values
);

    genvar dm;
    genvar dn;

    // Create one accumulator for each DPA row-column pair
    generate
        for (dm = 0; dm < DM; dm++) begin : gen_acc_rows
            for (dn = 0; dn < DN; dn++) begin : gen_acc_columns
                weighted_accumulator #(
                    .DK(DK),
                    .ACT_PLANES(ACT_PLANES),
                    .WEIGHT_BITS(WEIGHT_BITS),
                    .ACC_W(ACC_W)
                ) accumulator (
                    .clk(clk),
                    .reset(reset),
                    .clear(clear),
                    .enable(enable),
                    .popcount(popcounts[dm][dn]),
                    .activation_plane(activation_plane),
                    .weight_plane(weight_plane),
                    .value(values[dm][dn])
                );
            end
        end
    endgenerate

endmodule