// Stores the completed matrix multiplication results

module result_buffer #(
    parameter int M = 4,                 // Number of rows in the result matrix
    parameter int N = 32,                // Number of columns in the result matrix
    parameter int DATA_W = 16,           // Width of each signed result
    parameter int ADDR_W = $clog2(M * N) // Width required to address all M x N results
) (
    input  logic                         clk,

    // Interface used to store a completed result
    input  logic                         write_enable,
    input  logic [ADDR_W-1:0]            write_address,
    input  logic signed [DATA_W-1:0]     write_data,

    // Interface used to read a stored result
    input  logic [ADDR_W-1:0]            read_address,
    output logic signed [DATA_W-1:0]     read_data
);

    // Memory containing the M x N signed results
    logic signed [DATA_W-1:0] memory [0:M*N-1];

    // Store one result on the rising clock edge
    always_ff @(posedge clk) begin
        if (write_enable) begin
            memory[write_address] <= write_data;
        end
    end

    // Asynchronous read used to simplify the output interface
    assign read_data = memory[read_address];

endmodule