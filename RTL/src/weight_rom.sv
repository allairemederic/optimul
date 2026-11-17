// Stores the packed weight bit planes in block RAM
// Each memory word contains DN vectors of DK bits
// Vivado splits wide words across multiple physical BRAMs when needed

module weight_rom #(
    parameter int DN = 1,
    parameter int DK = 32,                         
    parameter int DEPTH = 1024,
    parameter int WORD_W = DN * DK,
    parameter int ADDR_W = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    parameter string INIT_FILE = ""
) (
    input  logic                  read_enable,
    input  logic [ADDR_W-1:0]     read_address,
    output logic [DN-1:0][DK-1:0] read_data
);

    logic [WORD_W-1:0] memory [0:DEPTH-1];

    // Load the weight values when the simulation or FPGA starts
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, memory);
        end
    end

    // Combinational weight read
    // The selected weight plane is available in the same cycle
    always_comb begin
        if (read_enable) begin
            read_data = memory[read_address];
        end
        else begin
            read_data = '0;
        end
    end

endmodule