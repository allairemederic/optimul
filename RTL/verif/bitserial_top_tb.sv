`timescale 1ns/1ps

module tb_bitserial_top #(
    parameter int DM = 1,
    parameter int DN = 1,
    parameter int DK = 32
);

    // Parameters for parallelization
    localparam int M = 4;
    localparam int K = 128;
    localparam int N = 32;
    localparam int ACT_W = 4;
    localparam int ACT_PLANES = 3;
    localparam int WEIGHT_BITS = 4;
    localparam int ACC_W = 16;
    localparam int NUM_LAYERS = 2;
    localparam int RESULT_COUNT = M * N;
    localparam int RESULT_ADDR_W = $clog2(RESULT_COUNT);
    localparam int M_TILES = M / DM;
    localparam int N_TILES = N / DN;
    localparam int K_GROUPS = K / DK;
    localparam int WEIGHT_WORD_W = DN * DK;

    // Expected cycle count for the current controller.
    localparam int EXPECTED_CYCLES =
        2
        + M * K
        + M * N
        + M_TILES * N_TILES * ( 2 + 2 * ACT_PLANES * WEIGHT_BITS * K_GROUPS);

    localparam time CLOCK_PERIOD = 10ns; // 100 MHZ

    logic clk;
    logic reset;

    // Control interface
    logic start;
    logic layer_select;
    logic busy;
    logic done;

    // Activation input interface
    logic                 activation_valid;
    logic [ACT_W-1:0]     activation_data;
    logic                 activation_ready;

    // Result output interface
    logic                             result_valid;
    logic [RESULT_ADDR_W-1:0]         result_index;
    logic signed [ACC_W-1:0]          result_data;
    logic                             result_ready;

    // Reference matrices used by the testbench
    integer activations [0:M-1][0:K-1];
    integer weights [0:NUM_LAYERS-1][0:K-1][0:N-1];
    integer expected_results [0:M-1][0:N-1];

    // Test statistics
    integer global_cycle;
    integer received_count;
    integer run_errors;
    integer total_errors;
    integer current_layer;

    // Variables used by the result monitor
    integer received_row;
    integer received_column;
    integer received_value;

    // Instantiate the complete bit-serial module
    bitserial_top #(
        .M(M),
        .K(K),
        .N(N),
        .ACT_W(ACT_W),
        .ACT_PLANES(ACT_PLANES),
        .WEIGHT_BITS(WEIGHT_BITS),
        .ACC_W(ACC_W),
        .DM(DM),
        .DN(DN),
        .DK(DK),
        .NUM_LAYERS(NUM_LAYERS),
        .WEIGHT_FILE("") // The testbench initializes the ROM directly
    ) dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .layer_select(layer_select),
        .activation_valid(activation_valid),
        .activation_data(activation_data),
        .activation_ready(activation_ready),
        .result_valid(result_valid),
        .result_index(result_index),
        .result_data(result_data),
        .result_ready(result_ready),
        .busy(busy),
        .done(done)
    );

    // Generate the 100 MHz clock
    initial begin
        clk = 1'b0;

        forever begin
            #(CLOCK_PERIOD / 2);
            clk = ~clk;
        end
    end

    // Count every simulated clock cycle
    always @(posedge clk) begin
        global_cycle = global_cycle + 1;
    end

    // Create deterministic activation and weight matrices
    task automatic initialize_matrices;
        integer layer;
        integer m;
        integer k;
        integer n;

        begin
            // Activations are always between 0 and 7
            for (m = 0; m < M; m++) begin
                for (k = 0; k < K; k++) begin
                    activations[m][k] = (3 * m + k) % 8;
                end
            end

            // Weights are signed values between -8 and 7
            for (layer = 0; layer < NUM_LAYERS; layer++) begin
                for (k = 0; k < K; k++) begin
                    for (n = 0; n < N; n++) begin
                        weights[layer][k][n] = ((5 * layer + 3 * k + n) % 16) - 8;
                    end
                end
            end
        end
    endtask

    // Pack the weight matrices into the format used by weight_rom
    // One ROM word contains DN output columns with DK weight bits for each column
    task automatic initialize_weight_rom;
        integer layer;
        integer n_tile;
        integer dn;
        integer n;
        integer plane;
        integer group;
        integer b;
        integer k;
        integer address;

        logic [WEIGHT_WORD_W-1:0] packed_word;

        begin
            for (layer = 0; layer < NUM_LAYERS; layer++) begin

                for (n_tile = 0; n_tile < N_TILES; n_tile++) begin

                    for (plane = 0; plane < WEIGHT_BITS; plane++) begin

                        for (group = 0; group < K_GROUPS; group++) begin

                            packed_word = '0;

                            // Pack DN columns of DK bits
                            for (dn = 0; dn < DN; dn++) begin
                                n = n_tile * DN + dn;

                                for (b = 0; b < DK; b++) begin
                                    k = group * DK + b;

                                    packed_word[dn * DK + b] = (weights[layer][k][n] >>> plane) & 1;
                                end
                            end

                            address = (((layer * N_TILES + n_tile) * WEIGHT_BITS + plane) * K_GROUPS) + group;

                            // Direct ROM initialization for simulation
                            dut.weight_rom_inst.memory[address] = packed_word;
                        end
                    end
                end
            end
        end
    endtask

    // Compute the expected matrix multiplication for one layer
    task automatic compute_expected_results( input integer selected_layer);
        integer m;
        integer n;
        integer k;
        integer sum;

        begin
            for (m = 0; m < M; m++) begin
                for (n = 0; n < N; n++) begin
                    sum = 0;

                    for (k = 0; k < K; k++) begin
                        sum = sum + activations[m][k] * weights[selected_layer][k][n];
                    end

                    expected_results[m][n] = sum;
                end
            end
        end
    endtask

    // Send all M x K activations to the DUT.
    task automatic send_activations;
        integer m;
        integer k;

        begin
            activation_valid = 1'b0;
            activation_data = '0;

            // Wait until the controller enters LOAD_ACTIVATIONS
            wait (activation_ready == 1'b1);

            for (m = 0; m < M; m++) begin
                for (k = 0; k < K; k++) begin
                    // Drive the next value before the rising edge
                    @(negedge clk);

                    activation_valid = 1'b1;
                    activation_data = activations[m][k];

                    // The activation is accepted on the next edge
                    @(posedge clk);

                    if (!activation_ready) begin
                        $fatal(1, "Activation interface stopped unexpectedly.");
                    end
                end
            end

            // Stop sending data after the last activation
            @(negedge clk);

            activation_valid = 1'b0;
            activation_data = '0;
        end
    endtask

    // Execute one complete matrix multiplication
    task automatic run_layer(
        input integer selected_layer
    );
        integer start_cycle;
        integer end_cycle;
        integer measured_cycles;

        begin
            $display("Test for Transformer layer %0d", selected_layer);
            $display("Configuration: DM=%0d DN=%0d DK=%0d", DM, DN, DK);

            current_layer = selected_layer;
            received_count = 0;
            run_errors = 0;

            compute_expected_results(selected_layer);

            // Start the DUT
            @(negedge clk);

            layer_select = selected_layer;
            start = 1'b1;
            start_cycle = global_cycle;

            @(negedge clk);
            start = 1'b0;

            // Load all activations
            send_activations();

            // Wait until all results have been transmitted.
            wait (done == 1'b1);

            end_cycle = global_cycle;
            measured_cycles = end_cycle - start_cycle;

            // Check that every expected result was received
            if (received_count != RESULT_COUNT) begin
                $display("[FAIL] Expected %0d results but received %0d.", RESULT_COUNT, received_count);

                run_errors = run_errors + 1;
                total_errors = total_errors + 1;
            end

            // Check the controller cycle count
            if (measured_cycles != EXPECTED_CYCLES) begin
                $display("[FAIL] Expected %0d cycles but measured %0d.", EXPECTED_CYCLES, measured_cycles);

                run_errors = run_errors + 1;
                total_errors = total_errors + 1;
            end
            else begin
                $display(
                    "[PASS] Cycle count = %0d",
                    measured_cycles
                );
            end

            $display("Layer:           %0d", selected_layer);
            $display("DM:              %0d", DM);
            $display("DN:              %0d", DN);
            $display("DK:              %0d", DK);
            $display("DPUs:            %0d", DM * DN);
            $display("Cycles:          %0d", measured_cycles);
            $display("Latency at 100 MHz: %0.2f us", measured_cycles / 100.0);
            $display("Results:         %0d", received_count);
            $display("Errors:          %0d", run_errors);

            if (run_errors == 0) begin
                $display("LAYER TEST: PASS");
            end
            else begin
                $display("LAYER TEST: FAIL");
            end

            // Wait until the controller returns to IDLE
            @(posedge clk);
            wait (busy == 1'b0 && done == 1'b0);
        end
    endtask

    // Monitor and verify every output result
    always @(posedge clk) begin
        if (result_valid && result_ready) begin
            received_row = result_index / N;
            received_column = result_index % N;
            received_value = $signed(result_data);

            received_count = received_count + 1;

            if (received_value !== expected_results[received_row][received_column]) begin
                run_errors = run_errors + 1;
                total_errors = total_errors + 1;

                $display(
                    "[FAIL] Layer=%0d Y[%0d][%0d]: expected=%0d received=%0d",
                    current_layer,
                    received_row,
                    received_column,
                    expected_results[received_row] [received_column],
                    received_value
                );
            end
            else begin
                $display(
                    "[PASS] Layer=%0d Y[%0d][%0d] = %0d",
                    current_layer,
                    received_row,
                    received_column,
                    received_value
                );
            end
        end
    end

    initial begin
        global_cycle = 0;
        received_count = 0;
        run_errors = 0;
        total_errors = 0;
        current_layer = 0;

        reset = 1'b1;
        start = 1'b0;
        layer_select = 1'b0;

        activation_valid = 1'b0;
        activation_data = '0;

        // Always accept output results
        result_ready = 1'b1;

        // Generate a VCD waveform file
        $dumpfile("tb_bitserial_top.vcd");
        $dumpvars(0, tb_bitserial_top);

        initialize_matrices();
        initialize_weight_rom();

        // Apply reset for several clock cycles
        repeat (4) @(posedge clk);

        @(negedge clk);
        reset = 1'b0;

        // Test both Transformer layers
        run_layer(0);
        run_layer(1);

        $display("TEST SUMMARY");
        $display("Configuration: DM=%0d DN=%0d DK=%0d", DM, DN, DK);
        $display("Total errors: %0d", total_errors);

        if (total_errors == 0) begin
            $display("BIT-SERIAL TEST: PASS");
        end
        else begin
            $display("BIT-SERIAL TEST: FAIL");
            $fatal(1,"One or more results were incorrect.");
        end

        $finish;
    end

    // Stop the simulation if the DUT becomes blocked
    initial begin
        repeat (40000) @(posedge clk);
        $fatal(1, "Simulation timeout after 40000 clock cycles.");
    end

endmodule