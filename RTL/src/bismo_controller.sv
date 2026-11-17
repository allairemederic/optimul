// Controls the loading, computation and result-writing phases

module bismo_controller #(

    // Matrix dimensions: (M x K) multiplied by (K x N)
    parameter int M = 4,
    parameter int K = 128,
    parameter int N = 32,

    // Operand configuration
    parameter int ACT_W = 4,
    parameter int ACT_PLANES = 3,
    parameter int WEIGHT_BITS = 4,

    // DPA parallelism
    parameter int DM = 1,
    parameter int DN = 1,
    parameter int DK = 32,

    parameter int ACT_LANES = 4,
    parameter int RESULT_LANES = 8,

    // Number of Transformer weight sets
    parameter int NUM_LAYERS = 2,

    // Number of input activations and output results
    parameter int ACT_COUNT = M * K,
    parameter int RESULT_COUNT = M * N,

    // Number of row, column, and K groups
    parameter int M_TILES = M / DM,
    parameter int N_TILES = N / DN,
    parameter int K_GROUPS = K / DK,

    // Address widths
    parameter int ACT_ADDR_W = $clog2(ACT_COUNT),
    parameter int RESULT_ADDR_W = $clog2(RESULT_COUNT),

    // Widths of full matrix indices
    parameter int M_W = $clog2(M),
    parameter int N_W = $clog2(N),

    // Widths of tile and group indices
    parameter int M_TILE_W = (M_TILES <= 1) ? 1 : $clog2(M_TILES),
    parameter int N_TILE_W = (N_TILES <= 1) ? 1 : $clog2(N_TILES),
    parameter int K_GROUP_W = (K_GROUPS <= 1) ? 1 : $clog2(K_GROUPS),

    // Widths of bit-plane indices
    parameter int ACT_PLANE_W = (ACT_PLANES <= 1) ? 1 : $clog2(ACT_PLANES),
    parameter int WEIGHT_PLANE_W = (WEIGHT_BITS <= 1) ? 1 : $clog2(WEIGHT_BITS),

    // Each ROM word contains DN groups of DK weight bits
    parameter int WEIGHT_DEPTH =  NUM_LAYERS * N_TILES * WEIGHT_BITS * K_GROUPS,
    parameter int WEIGHT_ADDR_W = (WEIGHT_DEPTH <= 1) ? 1 : $clog2(WEIGHT_DEPTH)
) (
    input logic clk,
    input logic reset,
    input logic start,

    // Selects the weights of the current Transformer layer
    input logic layer_select,

    // Activation input handshake
    input  logic activation_valid,
    output logic activation_ready,

    // Result output handshake
    input  logic result_ready,
    output logic result_valid,

    // Controls writes to the activation buffer
    output logic                    activation_write_enable,
    output logic [ACT_ADDR_W-1:0]   activation_write_address,

    // Position of the current result tile
    output logic [M_W-1:0] row_base,
    output logic [N_W-1:0] column_base,

    // Selects the current K group and bit planes
    output logic [K_GROUP_W-1:0]        k_group,
    output logic [ACT_PLANE_W-1:0]      activation_plane,
    output logic [WEIGHT_PLANE_W-1:0]   weight_plane,

    // Controls reads from the weight ROM
    output logic                         weight_read_enable,
    output logic [WEIGHT_ADDR_W-1:0]     weight_read_address,

    // Controls the accumulator bank
    output logic accumulator_initialize,
    output logic accumulator_enable,

    // Controls writes to the result buffer
    output logic                     result_write_enable,
    output logic [M_W-1:0]           result_row_base,
    output logic [N_W-1:0]           result_column_base,

    // Selects the result returned through the output interface
    output logic [RESULT_ADDR_W-1:0] result_read_address,

    // Current controller status
    output logic busy,
    output logic done
);

    typedef enum logic [3:0] {
        IDLE,
        LOAD_ACTIVATIONS,
        COMPUTE,
        WRITE_RESULTS,
        DONE_STATE
    } state_t;

    state_t state;

    // Index used while loading the activation buffer
    logic [ACT_ADDR_W-1:0] load_index;

    // Current row and column tiles
    logic [M_TILE_W-1:0] m_tile;
    logic [N_TILE_W-1:0] n_tile;

    // Current K group and bit-plane indices
    logic [K_GROUP_W-1:0] k_index;
    logic [ACT_PLANE_W-1:0] i_index;
    logic [WEIGHT_PLANE_W-1:0] j_index;

    // Index used while sending the completed results
    logic [RESULT_ADDR_W-1:0] output_index;

    // Stores the layer selected when start is received
    logic layer_reg;

    // Temporary weight-ROM address
    integer computed_weight_address;

    // Values for accumulator
    logic first_contribution;
    logic last_contribution;

    always_comb begin
        first_contribution = (k_index == 0) && (i_index == 0) && (j_index == 0);
        last_contribution = (k_index == K_GROUPS - 1) && (i_index == ACT_PLANES - 1) && (j_index == WEIGHT_BITS - 1);
    end

    // Convert tile indices into matrix row and column indices
    assign row_base = m_tile * DM;
    assign column_base = n_tile * DN;

    // Connect the internal counters to the datapath
    assign k_group = k_index;
    assign activation_plane = i_index;
    assign weight_plane = j_index;

    // Generate control signals from the current state
    always_comb begin

        // Default values prevent unintended latches
        activation_ready = 1'b0;
        activation_write_enable = 1'b0;
        activation_write_address = load_index;

        weight_read_enable = 1'b0;
        weight_read_address = '0;

        accumulator_initialize = 1'b0;
        accumulator_enable = 1'b0;
        result_write_enable = 1'b0;

        result_write_enable = 1'b0;
        result_row_base = row_base;
        result_column_base = column_base;
        result_read_address = output_index;

        result_valid = 1'b0;
        done = 1'b0;

        // The module is busy during all processing states
        busy = (state != IDLE) && (state != DONE_STATE);

        // Weight ROM layout = layer -> column tile -> weight plane -> K group
        computed_weight_address = (((layer_reg * N_TILES + n_tile) * WEIGHT_BITS + j_index) * K_GROUPS) + k_index;

        case (state)
            LOAD_ACTIVATIONS: begin
                // Accept one activation when valid and ready are high
                activation_ready = 1'b1;

                if (activation_valid) begin
                    activation_write_enable = 1'b1;
                end
            end

            COMPUTE: begin
                weight_read_enable = 1'b1;
                weight_read_address = WEIGHT_ADDR_W'(computed_weight_address);

                accumulator_enable = 1'b1;
                accumulator_initialize = first_contribution;

                // Store the completed tile during its final computation
                if (last_contribution) begin
                    result_write_enable = 1'b1;
                    result_row_base = row_base;
                    result_column_base = column_base;
                end
            end

            WRITE_RESULTS: begin
                // Indicate that the current result is available
                result_valid = 1'b1;
            end

            DONE_STATE: begin
                // Produce a one-cycle completion pulse
                done = 1'b1;
            end

            default: begin
                // Outputs keep their default values
            end
        endcase
    end

    // Update the state and counters on each clock cycle
    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;

            load_index <= '0;

            m_tile <= '0;
            n_tile <= '0;

            k_index <= '0;
            i_index <= '0;
            j_index <= '0;

            output_index <= '0;
            layer_reg <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        // Save the selected Transformer layer
                        layer_reg <= layer_select;

                        // Reset all indices
                        load_index <= '0;

                        m_tile <= '0;
                        n_tile <= '0;

                        k_index <= '0;
                        i_index <= '0;
                        j_index <= '0;

                        output_index <= '0;

                        state <= LOAD_ACTIVATIONS;
                    end
                end

                LOAD_ACTIVATIONS: begin
                    // Advance only when one activation is transferred
                    if (activation_valid && activation_ready) begin
                        if (load_index == ACT_COUNT - ACT_LANES) begin
                            // All M x K activations have been loaded
                            load_index <= '0;

                            k_index <= '0;
                            i_index <= '0;
                            j_index <= '0;

                            state <= COMPUTE;
                        end
                        else begin
                            load_index <= load_index + ACT_LANES;
                        end
                    end
                end

                COMPUTE: begin
                    if (k_index == K_GROUPS - 1) begin
                        k_index <= '0;

                        if (j_index == WEIGHT_BITS - 1) begin
                            j_index <= '0;

                            if (i_index == ACT_PLANES - 1) begin
                                i_index <= '0;

                                // The current tile is complete and is being written to the result buffer on this edge
                                if (n_tile == N_TILES - 1) begin
                                    n_tile <= '0;

                                    if (m_tile == M_TILES - 1) begin
                                        m_tile <= '0;
                                        output_index <= '0;
                                        state <= WRITE_RESULTS;
                                    end
                                    else begin
                                        m_tile <= m_tile + 1'b1;
                                        state <= COMPUTE;
                                    end
                                end
                                else begin
                                    n_tile <= n_tile + 1'b1;
                                    state <= COMPUTE;
                                end
                            end
                            else begin
                                i_index <= i_index + 1'b1;
                                state <= COMPUTE;
                            end
                        end
                        else begin
                            j_index <= j_index + 1'b1;
                            state <= COMPUTE;
                        end
                    end
                    else begin
                        k_index <= k_index + 1'b1;
                        state <= COMPUTE;
                    end
                end

                WRITE_RESULTS: begin
                    // Advance only when the receiver accepts a result
                    if (result_valid && result_ready) begin
                        if (output_index >= RESULT_COUNT - RESULT_LANES) begin
                            // All M x N results have been transmitted
                            output_index <= '0;
                            state <= DONE_STATE;
                        end
                        else begin
                            output_index <= output_index + RESULT_LANES;
                        end
                    end
                end

                DONE_STATE: begin
                    // Return to IDLE after the one-cycle done pulse
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
