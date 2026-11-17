// Applies the bit-plane weight and accumulates the partial result

module weighted_accumulator #(
    parameter int DK = 32,
    parameter int ACT_PLANES = 3,
    parameter int WEIGHT_BITS = 4,
    parameter int ACC_W = 16,

    parameter int COUNT_W = $clog2(DK + 1),
    parameter int ACT_PLANE_W = (ACT_PLANES > 1) ? $clog2(ACT_PLANES) : 1,
    parameter int WEIGHT_PLANE_W = (WEIGHT_BITS > 1) ? $clog2(WEIGHT_BITS) : 1
) (
    input  logic                              clk,
    input  logic                              reset,

    input  logic                              initialize,
    input  logic                              enable,

    input  logic [COUNT_W-1:0]                popcount,
    input  logic [ACT_PLANE_W-1:0]            activation_plane, 
    input  logic [WEIGHT_PLANE_W-1:0]         weight_plane,

    output logic signed [ACC_W-1:0] value,
    output logic signed [ACC_W-1:0] next_value
);

    logic signed [ACC_W-1:0] count_extended; // Popcount extended to the accumulator width
    logic signed [ACC_W-1:0] shifted_value;  // Popcount shifted according to the bit-plane positions
    logic signed [ACC_W-1:0] contribution;   // Signed value added to the accumulator

    integer shift_amount;

    always_comb begin

        count_extended = $signed({1'b0, popcount}); // Convert into a positive signed value
        
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

        // The first contribution replaces the previous tile value
        if (initialize) begin
            next_value = contribution;
        end
        else begin
            next_value = value + contribution;
        end
    end

    // Store the accumulated result
    always_ff @(posedge clk) begin
        if (reset) begin
            value <= '0;
        end
        else if (enable) begin
            value <= next_value;
        end
    end

endmodule