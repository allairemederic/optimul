// Stores the activation matrix and extracts one bit plane at a time

module activation_buffer #(
    parameter int M = 4,     // Number of rows in the activation matrix
    parameter int K = 128,   // Number of elements in each row
    parameter int ACT_W = 4, // Number of elements in each row.
    parameter int DK = 32,   // Number of activation bits sent to the DPU in parallel

    parameter int ADDR_W = $clog2(M * K),       // Width of the address used to load the activation buffer
    parameter int M_W = $clog2(M),              // Width of the row index
    parameter int K_GROUPS = K / DK,            // Number of DK-wide groups in each row
    parameter int K_GROUP_W = $clog2(K_GROUPS), // Width of the group index
    parameter int PLANE_W = $clog2(ACT_W)       // Width of the bit-plane index
) (
    input  logic                    clk,

    // Interface used to load activations into the buffer   
    input  logic                    write_enable,
    input  logic [ADDR_W-1:0]       write_address,
    input  logic [ACT_W-1:0]        write_data,

    // Indices selecting the requested activation bits
    input  logic [M_W-1:0]          row_index,
    input  logic [K_GROUP_W-1:0]    k_group,
    input  logic [PLANE_W-1:0]      bit_plane,

    // Selected bit plane for DK consecutive activations
    output logic [DK-1:0]           plane_bits
);

    logic [ACT_W-1:0] memory [0:M*K-1]; // Activation memory containing M rows of K values

    integer b;
    integer element_index;

    // Store one activation on each valid write
    always_ff @(posedge clk) begin
        if (write_enable) begin
            memory[write_address] <= write_data;
        end
    end

    // Extract one bit from each of DK consecutive activations
    always_comb begin
        plane_bits = '0;

        for (b = 0; b < DK; b++) begin
            element_index = row_index * K + k_group * DK + b; // Convert the row, group and position into a flat address
            plane_bits[b] = memory[element_index][bit_plane]; // Select the requested bit plane
        end
    end

endmodule