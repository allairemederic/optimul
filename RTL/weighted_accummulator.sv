// Applies the bit-plane weight and accumulates the partial result

module weighted_accumulator #(
    parameter int DK = 32,         // Number of bit pairs processed by the DPU
    parameter int ACT_PLANES = 3,  // Number of useful activation bit planes
    parameter int WEIGHT_BITS = 4, // Number of bits used to represent each signed weight
    parameter int ACC_W = 16,      // Width of the signed accumulator

    parameter int COUNT_W = $clog2(DK + 1),            // Width of the DPU popcount result
    parameter int ACT_PLANE_W = $clog2(ACT_PLANES),    // Width of the activation bit-plane index
    parameter int WEIGHT_PLANE_W = $clog2(WEIGHT_BITS) // Width of the weight bit-plane index
) (
    input  logic                              clk,
    input  logic                              reset,

    input  logic                              clear,    // Clears the accumulator before computing a new output
    input  logic                              enable,   // Adds the current contribution to the accumulator

    input  logic [COUNT_W-1:0]                popcount,         // Partial binary dot product produced by the DPU
    input  logic [ACT_PLANE_W-1:0]            activation_plane, // Current activation index
    input  logic [WEIGHT_PLANE_W-1:0]         weight_plane,     // Current weight index

    output logic signed [ACC_W-1:0]           value // Current signed accumulated result
);

    logic signed [ACC_W-1:0] count_extended; // Popcount extended to the accumulator width
    logic signed [ACC_W-1:0] shifted_value;  // Popcount shifted according to the bit-plane positions
    logic signed [ACC_W-1:0] contribution;   // Signed value added to the accumulator

    integer shift_amount; // Total number of positions used for the shift

    // Compute the weighted and signed contribution
    always_comb begin

        // Convert the unsigned popcount into a positive signed value
        count_extended = $signed({1'b0, popcount});
        
        // A pair of bit planes has a weight of 2^(i+j)
        shift_amount = activation_plane + weight_plane;
        shifted_value = count_extended <<< shift_amount;

        // The most significant weight plane is the sign bit
        if (weight_plane == WEIGHT_BITS - 1) begin
            contribution = -shifted_value;
        end
        else begin
            contribution = shifted_value;
        end
    end

    // Store the accumulated result
    always_ff @(posedge clk) begin
        if (reset) begin
            value <= '0;
        end
        else if (clear) begin
            value <= '0;
        end
        else if (enable) begin
            value <= value + contribution;
        end
    end

endmodule