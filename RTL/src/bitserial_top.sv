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

    // DPA parallelism
    parameter int DM = 1,
    parameter int DN = 1,
    parameter int DK = 32,
    parameter int NUM_DPU = DM * DN,

    // Number of row and column tiles
    parameter int M_TILES = M / DM,
    parameter int N_TILES = N / DN,

    // Number of Transformer weight sets
    parameter int NUM_LAYERS = 2,

    // Address widths
    parameter int ACT_ADDR_W = $clog2(M * K),
    parameter int RESULT_ADDR_W = $clog2(M * N),

    // Widths of full matrix indices
    parameter int M_W = (M <= 1) ? 1 : $clog2(M),
    parameter int N_W = (N <= 1) ? 1 : $clog2(N),

    // Number of DK-wide groups in the K dimension
    parameter int K_GROUPS = K / DK,
    parameter int K_GROUP_W = (K_GROUPS <= 1) ? 1 : $clog2(K_GROUPS),

    // Widths of the bit-plane indices
    parameter int ACT_PLANE_W = (ACT_PLANES <= 1) ? 1 : $clog2(ACT_PLANES),
    parameter int WEIGHT_PLANE_W = (WEIGHT_BITS <= 1) ? 1 : $clog2(WEIGHT_BITS),

    // Each ROM word contains DN groups of DK weight bits
    parameter int WEIGHT_DEPTH = NUM_LAYERS * N_TILES * WEIGHT_BITS * K_GROUPS,
    parameter int WEIGHT_ADDR_W = (WEIGHT_DEPTH <= 1) ? 1 : $clog2(WEIGHT_DEPTH),

    // Width of one popcount result
    parameter int COUNT_W = $clog2(DK + 1),

    // File containing the packed weight bit planes
    parameter string WEIGHT_FILE = "weights_ff1.mem"
) (
    input logic clk,
    input logic reset,

    input logic start,
    input logic layer_select, // Selects the weights of the current Transformer layer

    // Activation input interface
    input  logic                 activation_valid,
    input  logic [ACT_W-1:0]     activation_data,
    output logic                 activation_ready,

    // Result output interface
    output logic                         result_valid,
    output logic [RESULT_ADDR_W-1:0]     result_index,
    output logic signed [ACC_W-1:0]      result_data,
    input  logic                         result_ready,

    // Module status
    output logic busy,
    output logic done
);

    // Check that the matrix dimensions are compatible with the selected parallelism
    initial begin
        if ((M % DM) != 0) begin
            $fatal(1, "DM must divide M.");
        end

        if ((N % DN) != 0) begin
            $fatal(1, "DN must divide N.");
        end

        if ((K % DK) != 0) begin
            $fatal(1, "DK must divide K.");
        end
    end

    // Activation-buffer write controls
    logic activation_write_enable;
    logic [ACT_ADDR_W-1:0] activation_write_address;

    // Position of the current result tile
    logic [M_W-1:0] row_base;
    logic [N_W-1:0] column_base;

    // Current K group and bit-plane indices
    logic [K_GROUP_W-1:0] k_group;
    logic [ACT_PLANE_W-1:0] activation_plane;
    logic [WEIGHT_PLANE_W-1:0] weight_plane;

    // DM activation vectors and DN weight vectors
    logic [DM-1:0][DK-1:0] activation_bits;
    logic [DN-1:0][DK-1:0] weight_bits;

    // Weight-ROM read controls
    logic weight_read_enable;
    logic [WEIGHT_ADDR_W-1:0] weight_read_address;

    // One popcount result for each DPA row-column pair
    logic [DM-1:0][DN-1:0][COUNT_W-1:0] dpa_counts;

    // Accumulator-bank controls
    logic accumulator_clear;
    logic accumulator_enable;

    // One accumulated value for each DPA row-column pair
    logic signed [DM-1:0][DN-1:0][ACC_W-1:0] accumulator_values;

    // Result-buffer controls
    logic result_write_enable;

    logic [M_W-1:0] result_row_base;
    logic [N_W-1:0] result_column_base;

    logic [RESULT_ADDR_W-1:0] result_read_address;

    // The output index is the current result-buffer read address
    assign result_index = result_read_address;

    // Stores the activation matrix and extracts DM bit-plane vectors
    activation_buffer #(
        .M(M),
        .K(K),
        .ACT_W(ACT_W),
        .DM(DM),
        .DK(DK)
    ) activation_buffer_inst (
        .clk(clk),

        .write_enable(activation_write_enable),
        .write_address(activation_write_address),
        .write_data(activation_data),

        .row_base(row_base),
        .k_group(k_group),
        .bit_plane(activation_plane),

        .plane_bits(activation_bits)
    );

    // Stores the weight bit planes for all Transformer layers
    // Each read returns DN vectors of DK bits
    weight_rom #(
        .DN(DN),
        .DK(DK),
        .DEPTH(WEIGHT_DEPTH),
        .INIT_FILE(WEIGHT_FILE)
    ) weight_rom_inst (
        .clk(clk),
        .read_enable(weight_read_enable),
        .read_address(weight_read_address),
        .read_data(weight_bits)
    );

    // Computes DM x DN parallel AND-popcount operations
    dot_product_array #(
        .DM(DM),
        .DN(DN),
        .DK(DK),
        .COUNT_W(COUNT_W)
    ) dpa_inst (
        .activation_bits(activation_bits),
        .weight_bits(weight_bits),
        .counts(dpa_counts)
    );

    // Applies the bit-plane weights and accumulates the DM x DN partial results
    accumulator_bank #(
        .DM(DM),
        .DN(DN),
        .DK(DK),
        .ACT_PLANES(ACT_PLANES),
        .WEIGHT_BITS(WEIGHT_BITS),
        .ACC_W(ACC_W)
    ) accumulator_bank_inst (
        .clk(clk),
        .reset(reset),

        .clear(accumulator_clear),
        .enable(accumulator_enable),

        .popcounts(dpa_counts),
        .activation_plane(activation_plane),
        .weight_plane(weight_plane),

        .values(accumulator_values)
    );

    // Stores one complete DM x DN result tile in parallel
    result_buffer #(
        .M(M),
        .N(N),
        .DM(DM),
        .DN(DN),
        .DATA_W(ACC_W)
    ) result_buffer_inst (
        .clk(clk),

        .write_enable(result_write_enable),
        .write_row_base(result_row_base),
        .write_column_base(result_column_base),
        .write_data(accumulator_values),

        .read_address(result_read_address),
        .read_data(result_data)
    );

    // Controls loading, tiled computation and result writing
    bismo_controller #(
        .M(M),
        .K(K),
        .N(N),

        .ACT_W(ACT_W),
        .ACT_PLANES(ACT_PLANES),
        .WEIGHT_BITS(WEIGHT_BITS),

        .DM(DM),
        .DN(DN),
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

        .row_base(row_base),
        .column_base(column_base),

        .k_group(k_group),
        .activation_plane(activation_plane),
        .weight_plane(weight_plane),

        .weight_read_enable(weight_read_enable),
        .weight_read_address(weight_read_address),

        .accumulator_clear(accumulator_clear),
        .accumulator_enable(accumulator_enable),

        .result_write_enable(result_write_enable),
        .result_row_base(result_row_base),
        .result_column_base(result_column_base),
        .result_read_address(result_read_address),

        .busy(busy),
        .done(done)
    );

endmodule