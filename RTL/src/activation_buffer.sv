// Stores the activation matrix and extracts one bit plane at a time

module activation_buffer #(
    parameter int M = 4,     // Number of rows in the activation matrix
    parameter int K = 128,   // Number of elements in each row
    parameter int ACT_W = 4, // Number of elements in each row
    parameter int DM = 1,    // Number of activation rows processed in parallel
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
    input  logic [M_W-1:0]          row_base,
    input  logic [K_GROUP_W-1:0]    k_group,
    input  logic [PLANE_W-1:0]      bit_plane,

    // Selected bit plane for DM rows of DK consecutive activations
    output logic [DM-1:0][DK-1:0] plane_bits
);

    // Activation memory containing M rows of K values
    logic [ACT_W-1:0] memory [0:M*K-1];

    integer dm;
    integer b;
    integer row;
    integer element_index;

    // Store one activation on each valid write
    always_ff @(posedge clk) begin
        if (write_enable) begin
            memory[write_address] <= write_data;
        end
    end

    // Extract DK bits from each of DM activation rows
    always_comb begin
        plane_bits = '0;

        // Select each parallel activation row
        for (dm = 0; dm < DM; dm++) begin
            row = row_base + dm;

            // Extract DK bits from the selected row and bit plane
            for (b = 0; b < DK; b++) begin
                
                // Convert the row, K group, and bit positio into a flat memory address
                element_index = row * K + k_group * DK + b;

                // Select the requested bit from the activation
                plane_bits[dm][b] = memory[element_index][bit_plane];
            end
        end
    end

endmodule