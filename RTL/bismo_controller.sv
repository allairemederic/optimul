// Controls the loading, computation and result-writing phases

module bismo_controller #(
    // Matrix dimensions: (M x K) multiplied by (K x N)
    parameter int M = 4,
    parameter int K = 128,
    parameter int N = 32,

    // Operand configuration.
    parameter int ACT_W = 4,
    parameter int ACT_PLANES = 3,
    parameter int WEIGHT_BITS = 4,
    parameter int DK = 32,
    parameter int NUM_LAYERS = 2,

    // Number of input activations, results, and K groups
    parameter int ACT_COUNT = M * K,
    parameter int RESULT_COUNT = M * N,
    parameter int K_GROUPS = K / DK,

    // Counter and address widths.
    parameter int ACT_ADDR_W = $clog2(ACT_COUNT),
    parameter int RESULT_ADDR_W = $clog2(RESULT_COUNT),
    parameter int M_W = $clog2(M),
    parameter int N_W = $clog2(N),
    parameter int K_GROUP_W = $clog2(K_GROUPS),
    parameter int ACT_PLANE_W = $clog2(ACT_PLANES),
    parameter int WEIGHT_PLANE_W = $clog2(WEIGHT_BITS),

    // Total number of words stored in the weight ROM
    parameter int WEIGHT_DEPTH = NUM_LAYERS * N * WEIGHT_BITS * K_GROUPS,

    parameter int WEIGHT_ADDR_W = $clog2(WEIGHT_DEPTH)
) (
    input logic clk,
    input logic reset,

    input logic start,

    input logic layer_select, // Selects the weight set for the current Transformer layer

    // Activation input handshake
    input  logic activation_valid,
    output logic activation_ready,

    // Result output handshake
    input  logic result_ready,
    output logic result_valid,

    // Controls writes to the activation buffer
    output logic                    activation_write_enable,
    output logic [ACT_ADDR_W-1:0]   activation_write_address,

    // Selects the current activation bit plane
    output logic [M_W-1:0]              row_index,
    output logic [K_GROUP_W-1:0]        k_group,
    output logic [ACT_PLANE_W-1:0]      activation_plane,
    output logic [WEIGHT_PLANE_W-1:0]   weight_plane,

    // Controls reads from the weight ROM
    output logic                         weight_read_enable,
    output logic [WEIGHT_ADDR_W-1:0]     weight_read_address,

    // Controls the weighted accumulator
    output logic accumulator_clear,
    output logic accumulator_enable,

    // Controls the result buffer
    output logic                         result_write_enable,
    output logic [RESULT_ADDR_W-1:0]     result_write_address,
    output logic [RESULT_ADDR_W-1:0]     result_read_address,

    // Current controller status
    output logic busy,
    output logic done
);

    // Controller states
    typedef enum logic [3:0] {
        IDLE,
        LOAD_ACTIVATIONS,
        CLEAR_ACCUMULATOR,
        FETCH_OPERANDS,
        ACCUMULATE,
        STORE_RESULT,
        WRITE_RESULTS,
        DONE_STATE
    } state_t;

    state_t state;

    // Index used while loading the activation buffer
    logic [ACT_ADDR_W-1:0] load_index;

    // Current output matrix position Y[m][n]
    logic [M_W-1:0] m_index;
    logic [N_W-1:0] n_index;

    // Current K group and bit-plane indices
    logic [K_GROUP_W-1:0] k_index;
    logic [ACT_PLANE_W-1:0] i_index;
    logic [WEIGHT_PLANE_W-1:0] j_index;

    // Index used while sending the completed results
    logic [RESULT_ADDR_W-1:0] output_index;

    // Stores the layer selected when start is received
    logic layer_reg;

    // Temporary integer addresses
    integer computed_weight_address;
    integer computed_result_address;

    // Connect the internal counters to the datapath
    assign row_index = m_index;
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

        accumulator_clear = 1'b0;
        accumulator_enable = 1'b0;

        result_write_enable = 1'b0;
        result_write_address = '0;
        result_read_address = output_index;

        result_valid = 1'b0;
        done = 1'b0;

        // The module is busy during all processing states
        busy = (state != IDLE) && (state != DONE_STATE);

        // Weight ROM layout: layer -> output column -> weight plane -> K group
        computed_weight_address = (((layer_reg * N + n_index) * WEIGHT_BITS + j_index) * K_GROUPS) + k_index;

        // Flatten Y[m][n] into one result-buffer address
        computed_result_address = m_index * N + n_index;

        case (state)
            LOAD_ACTIVATIONS: begin
                // Accept one activation when valid and ready are high
                activation_ready = 1'b1;

                if (activation_valid) begin
                    activation_write_enable = 1'b1;
                end
            end

            CLEAR_ACCUMULATOR: begin
                // Clear the accumulator before computing a new result
                accumulator_clear = 1'b1;
            end

            FETCH_OPERANDS: begin
                // Request the next weight bit-plane word
                weight_read_enable = 1'b1;
                weight_read_address =
                    WEIGHT_ADDR_W'(computed_weight_address);
            end

            ACCUMULATE: begin
                // Add the current DPU contribution
                accumulator_enable = 1'b1;
            end

            STORE_RESULT: begin
                // Store the completed Y[m][n] value
                result_write_enable = 1'b1;
                result_write_address = RESULT_ADDR_W'(computed_result_address);
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
            m_index <= '0;
            n_index <= '0;
            k_index <= '0;
            i_index <= '0;
            j_index <= '0;
            output_index <= '0;
            layer_reg <= 1'b0;
        end
        else begin
            case (state)
                IDLE: begin
                    // Wait for a new operation
                    if (start) begin
                        layer_reg <= layer_select; // Save the selected Transformer layer

                        // Reset all indices
                        load_index <= '0;
                        m_index <= '0;
                        n_index <= '0;
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
                        if (load_index == ACT_COUNT - 1) begin
                            // All M x K activations have been loaded
                            load_index <= '0;
                            state <= CLEAR_ACCUMULATOR;
                        end
                        else begin
                            load_index <= load_index + 1'b1;
                        end
                    end
                end

                CLEAR_ACCUMULATOR: begin
                    // Start the computation of a new Y[m][n]
                    k_index <= '0;
                    i_index <= '0;
                    j_index <= '0;

                    state <= FETCH_OPERANDS;
                end

                FETCH_OPERANDS: begin
                    // The synchronous weight ROM returns its data after this clock edge
                    state <= ACCUMULATE;
                end

                ACCUMULATE: begin
                    // Move through the K groups first
                    if (k_index == K_GROUPS - 1) begin
                        k_index <= '0;

                        // Move to the next weight bit plane
                        if (j_index == WEIGHT_BITS - 1) begin
                            j_index <= '0;

                            // Move to the next activation bit plane
                            if (i_index == ACT_PLANES - 1) begin
                                i_index <= '0;

                                // All bit-plane pairs are complete
                                state <= STORE_RESULT;
                            end
                            else begin
                                i_index <= i_index + 1'b1;
                                state <= FETCH_OPERANDS;
                            end
                        end
                        else begin
                            j_index <= j_index + 1'b1;
                            state <= FETCH_OPERANDS;
                        end
                    end
                    else begin
                        k_index <= k_index + 1'b1;
                        state <= FETCH_OPERANDS;
                    end
                end

                STORE_RESULT: begin
                    // Move to the next output column
                    if (n_index == N - 1) begin
                        n_index <= '0;

                        // Move to the next output row
                        if (m_index == M - 1) begin
                            // The complete M x N matrix is available
                            m_index <= '0;
                            output_index <= '0;
                            state <= WRITE_RESULTS;
                        end
                        else begin
                            m_index <= m_index + 1'b1;
                            state <= CLEAR_ACCUMULATOR;
                        end
                    end
                    else begin
                        n_index <= n_index + 1'b1;
                        state <= CLEAR_ACCUMULATOR;
                    end
                end

                WRITE_RESULTS: begin
                    // Advance only when the receiver accepts the result
                    if (result_valid && result_ready) begin
                        if (output_index == RESULT_COUNT - 1) begin
                            // All M x N results have been transmitted
                            output_index <= '0;
                            state <= DONE_STATE;
                        end
                        else begin
                            output_index <= output_index + 1'b1;
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