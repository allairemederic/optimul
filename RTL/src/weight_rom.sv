// Read-only memory containing the prearranged weight bit planes

module weight_rom #(
    parameter int DN = 1,
    parameter int DK = 32,                         
    parameter int DEPTH = 1024,
    parameter int ADDR_W = $clog2(DEPTH),
    parameter string INIT_FILE = "weights_ff1.mem"
) (
    input  logic                  clk,
    input  logic                  read_enable,
    input  logic [ADDR_W-1:0]     read_address,
    output logic [DN-1:0][DK-1:0] read_data
);

    // ROM containing DEPTH words of DN x DK bits
    logic [DN*DK-1:0] memory [0:DEPTH-1];

    // Load the weight values when the simulation or FPGA starts
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, memory);
        end
    end

    // Synchronous ROM read
    // The requested word becomes available after the rising clock edge
    always_ff @(posedge clk) begin
        if (read_enable) begin
            read_data <= memory[read_address];
        end
    end

endmodule