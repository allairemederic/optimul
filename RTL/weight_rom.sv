// Read-only memory containing the prearranged weight bit planes

module weight_rom #(
    parameter int DK = 32,                         // Number of weight bits read in parallel
    parameter int DEPTH = 1024,                    // Number of words stored in the ROM
    parameter int ADDR_W = $clog2(DEPTH),          // Width required to address every ROM word
    parameter string INIT_FILE = "weights_ff1.mem" // File used to initialize the weight values
) (
    input  logic                 clk,

    // Synchronous read interface
    input  logic                 read_enable,
    input  logic [ADDR_W-1:0]    read_address,

    // DK weight bits returned by the ROM
    output logic [DK-1:0]        read_data
);

    // ROM containing DEPTH words of DK bits
    logic [DK-1:0] memory [0:DEPTH-1];

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