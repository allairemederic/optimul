// Stores the completed M x N result matrix
// A DM x DN tile can be written in one clock cycle
// RESULT_LANES consecutive results can be read in parallel

module result_buffer #(
    parameter int M = 4,
    parameter int N = 32,
    parameter int DM = 1,
    parameter int DN = 1,
    parameter int DATA_W = 16,
    parameter int RESULT_LANES = 8,
    parameter int RESULT_COUNT = M * N,

    parameter int ADDR_W = ((RESULT_COUNT) > 1) ? $clog2(RESULT_COUNT) : 1,
    parameter int M_W = (M > 1) ? $clog2(M) : 1,
    parameter int N_W = (N > 1) ? $clog2(N) : 1
) (
    input logic clk,

    // Parallel tile-write interface
    input logic write_enable,
    input logic [M_W-1:0] write_row_base,
    input logic [N_W-1:0] write_column_base,

    input logic signed [DM-1:0][DN-1:0][DATA_W-1:0] write_data,

    // Parallel result-read interface
    // read_address identifies the first result of the group
    input logic [ADDR_W-1:0] read_address,
    output logic signed [RESULT_LANES-1:0][DATA_W-1:0] read_data
);

    logic signed [DATA_W-1:0] memory [0:RESULT_COUNT-1];

    integer dm;
    integer dn;
    integer write_address;
    integer read_lane;

    initial begin
        if ((RESULT_COUNT % RESULT_LANES) != 0) begin
            $fatal(1, "RESULT_LANES must divide M*N.");
        end
    end

    // Store one DM x DN tile in parallel
    always_ff @(posedge clk) begin
        if (write_enable) begin
            for (dm = 0; dm < DM; dm++) begin
                for (dn = 0; dn < DN; dn++) begin
                    write_address = (write_row_base + dm) * N + write_column_base + dn;
                    memory[write_address] <= write_data[dm][dn];
                end
            end
        end
    end

    // Read RESULT_LANES consecutive results in parallel
    always_comb begin
        read_data = '0;

        for (read_lane = 0; read_lane < RESULT_LANES; read_lane++) begin
            read_data[read_lane] = memory[read_address + read_lane];
        end
    end

endmodule