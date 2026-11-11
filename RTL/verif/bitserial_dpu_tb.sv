`timescale 1ns/1ps

module tb_bitserial_dpu;


    parameter int DK = 32;
    parameter int COUNT_W = $clog2(DK + 1);


    logic [DK-1:0] a_bits;
    logic [DK-1:0] w_bits;
    logic [COUNT_W-1:0] count;

    // For statistics
    integer test_count;
    integer error_count;

    bitserial_dpu #(
        .DK(DK),
        .COUNT_W(COUNT_W)
    ) dut (
        .a_bits(a_bits),
        .w_bits(w_bits),
        .count(count)
    );

    // Apply two vectors and compare the DPU result with a reference popcount computed by the testbench
    task automatic check_vectors(
        input logic [DK-1:0] a_vector,
        input logic [DK-1:0] w_vector,
        input string test_name
    );
        integer k;
        integer expected_count;

        begin
            a_bits = a_vector;
            w_bits = w_vector;

            #1; // Wait for the combinational logic to settle

            expected_count = 0;

            for (k = 0; k < DK; k++) begin
                expected_count = expected_count + (a_vector[k] & w_vector[k]);
            end

            test_count = test_count + 1;

            // Compare the DUT output with the reference result
            if (count !== expected_count[COUNT_W-1:0]) begin
                error_count = error_count + 1;

                $display(
                    "[FAIL] %s: a=%h w=%h expected=%0d received=%0d",
                    test_name,
                    a_vector,
                    w_vector,
                    expected_count,
                    count
                );
            end
            else begin
                $display("[PASS] %s: count=%0d", test_name,count);
            end
        end
    endtask

    initial begin

        test_count = 0;
        error_count = 0;

        a_bits = '0;
        w_bits = '0;

        $display("Verification for bitserial_dpu");
        $display("DK = %0d", DK);

        // Both vectors contain only zeros
        check_vectors(32'h00000000, 32'h00000000, "All zeros");

        // Both vectors contain only ones
        check_vectors(32'hFFFFFFFF, 32'hFFFFFFFF, "All ones");

        // Half of the activation bits are equal to one
        check_vectors(32'hAAAAAAAA, 32'hFFFFFFFF, "Alternating activations");

        // The active bits never appear at the same positions
        check_vectors(32'hAAAAAAAA, 32'h55555555, "Opposite patterns");

        // The same alternating pattern is used for both vectors
        check_vectors(32'h55555555, 32'h55555555, "Matching alternating patterns");

        // Run additional random tests
        repeat (100) begin
            check_vectors($urandom, $urandom, "Random vectors");
        end

        $display("Tests completed: %0d", test_count);
        $display("Errors:          %0d", error_count);

        if (error_count == 0) begin
            $display("BIT-SERIAL DPU TEST: PASS");
        end
        else begin
            $display("BIT-SERIAL DPU TEST: FAIL");
            $fatal(1, "The DPU produced incorrect results.");
        end

        $finish;
    end

endmodule