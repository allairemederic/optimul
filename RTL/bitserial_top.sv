// Top-level module for the bit-serial matrix multiplication

module bitserial_top #(

    // Matrix dimensions: (M x K) multiplied by (K x N)
    parameter int M = 4,
    parameter int K = 128,
    parameter int N = 32,

    // Operand and result widths
    parameter int ACT_W = 4,
    parameter int ACT_PLANES = 3,
    parameter int WEIGHT_BITS = 4,
    parameter int ACC_W = 16,

    // Number of bit pairs processed by one DPU
    parameter int DK = 32,

    // Number of Transformer weight sets
    parameter int NUM_LAYERS = 2,

    // Derived address and counter widths
    parameter int ACT_ADDR_W = $clog2(M * K),
    parameter int RESULT_ADDR_W = $clog2(M * N),
    parameter int M_W = $clog2(M),

    // Number of DK-wide groups in the K dimension
    parameter int K_GROUPS = K / DK,
    parameter int K_GROUP_W = $clog2(K_GROUPS),

    // Widths of the bit-plane indices
    parameter int ACT_PLANE_W = $clog2(ACT_PLANES),
    parameter int WEIGHT_PLANE_W = $clog2(WEIGHT_BITS),

    // Weight ROM dimensions
    parameter int WEIGHT_DEPTH =
        NUM_LAYERS * N * WEIGHT_BITS * K_GROUPS,

    parameter int WEIGHT_ADDR_W = $clog2(WEIGHT_DEPTH),

    // Width of one popcount result
    parameter int COUNT_W = $clog2(DK + 1),

    // File containing the packed weight bit planes
    parameter string WEIGHT_FILE = "weights_ff1.mem"
) (
    input logic clk,
    input logic reset,

    // Starts a new matrix multiplication
    input logic start,

    // Selects the weight set for the current Transformer layer
    input logic layer_select,

    // Activation input interface
    input  logic                     activation_valid,
    input  logic [ACT_W-1:0]         activation_data,
    output logic                     activation_ready,

    // Result output interface
    output logic                         result_valid,
    output logic [RESULT_ADDR_W-1:0]     result_index,
    output logic signed [ACC_W-1:0]      result_data,
    input  logic                         result_ready,

    // Module status
    output logic busy,
    output logic done
);

    // Activation-buffer write controls
    logic activation_write_enable;
    logic [ACT_ADDR_W-1:0] activation_write_address;

    // Indices used to select the current activation bit plane
    logic [M_W-1:0] row_index;
    logic [K_GROUP_W-1:0] k_group;
    logic [ACT_PLANE_W-1:0] activation_plane;
    logic [WEIGHT_PLANE_W-1:0] weight_plane;

    // Binary activation and weight vectors sent to the DPA
    logic [DK-1:0] activation_bits;
    logic [DK-1:0] weight_bits;

    // Weight-ROM read controls
    logic weight_read_enable;
    logic [WEIGHT_ADDR_W-1:0] weight_read_address;

    // DPA interfaces
    // The first version contains only one DPU
    logic [0:0][DK-1:0] dpa_activation_bits;
    logic [0:0][DK-1:0] dpa_weight_bits;
    logic [0:0][COUNT_W-1:0] dpa_counts;

    // Accumulator controls and current value
    logic accumulator_clear;
    logic accumulator_enable;
    logic signed [ACC_W-1:0] accumulator_value;

    // Result-buffer controls
    logic result_write_enable;
    logic [RESULT_ADDR_W-1:0] result_write_address;
    logic [RESULT_ADDR_W-1:0] result_read_address;

    // Connect the activation and weight vectors to DPU 0
    assign dpa_activation_bits[0] = activation_bits;
    assign dpa_weight_bits[0] = weight_bits;

    // The output index is the current result-buffer read address
    assign result_index = result_read_address;

    // Stores the activation matrix and extracts activation bit planes
    activation_buffer #(
        .M(M),
        .K(K),
        .ACT_W(ACT_W),
        .DK(DK)
    ) activation_buffer_inst (
        .clk(clk),

        .write_enable(activation_write_enable),
        .write_address(activation_write_address),
        .write_data(activation_data),

        .row_index(row_index),
        .k_group(k_group),
        .bit_plane(activation_plane),

        .plane_bits(activation_bits)
    );

    // Stores the weight bit planes for both Transformer layers
    weight_rom #(
        .DK(DK),
        .DEPTH(WEIGHT_DEPTH),
        .INIT_FILE(WEIGHT_FILE)
    ) weight_rom_inst (
        .clk(clk),

        .read_enable(weight_read_enable),
        .read_address(weight_read_address),
        .read_data(weight_bits)
    );

    // Computes the AND-popcount operation
    // This first version uses one DPU
    dot_product_array #(
        .DK(DK),
        .NUM_DPU(1)
    ) dpa_inst (
        .a_bits(dpa_activation_bits),
        .w_bits(dpa_weight_bits),
        .counts(dpa_counts)
    );

    // Applies the bit-plane weight, corrects the sign and accumulates the partial results.
    weighted_accumulator #(
        .DK(DK),
        .ACT_PLANES(ACT_PLANES),
        .WEIGHT_BITS(WEIGHT_BITS),
        .ACC_W(ACC_W)
    ) accumulator_inst (
        .clk(clk),
        .reset(reset),

        .clear(accumulator_clear),
        .enable(accumulator_enable),

        .popcount(dpa_counts[0]),
        .activation_plane(activation_plane),
        .weight_plane(weight_plane),

        .value(accumulator_value)
    );

    // Stores the completed M x N output matrix
    result_buffer #(
        .M(M),
        .N(N),
        .DATA_W(ACC_W)
    ) result_buffer_inst (
        .clk(clk),

        .write_enable(result_write_enable),
        .write_address(result_write_address),
        .write_data(accumulator_value),

        .read_address(result_read_address),
        .read_data(result_data)
    );

    // Controls all loading, computation and writing operations
    bismo_controller #(
        .M(M),
        .K(K),
        .N(N),
        .ACT_W(ACT_W),
        .ACT_PLANES(ACT_PLANES),
        .WEIGHT_BITS(WEIGHT_BITS),
        .DK(DK),
        .NUM_LAYERS(NUM_LAYERS)
    ) controller_inst (
        .clk(clk),
        .reset(reset),

        .start(start),
        .layer_select(layer_select),

        .activation_valid(activation_valid),
        .activation_ready(activation_ready),

        .result_ready(result_ready),
        .result_valid(result_valid),

        .activation_write_enable(activation_write_enable),
        .activation_write_address(activation_write_address),

        .row_index(row_index),
        .k_group(k_group),
        .activation_plane(activation_plane),
        .weight_plane(weight_plane),

        .weight_read_enable(weight_read_enable),
        .weight_read_address(weight_read_address),

        .accumulator_clear(accumulator_clear),
        .accumulator_enable(accumulator_enable),

        .result_write_enable(result_write_enable),
        .result_write_address(result_write_address),
        .result_read_address(result_read_address),

        .busy(busy),
        .done(done)
    );

endmodule