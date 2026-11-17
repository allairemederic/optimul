// Stores the activation matrix and extracts one bit plane at a time

module activation_buffer #(
    parameter int M = 4, 
    parameter int K = 128,
    parameter int ACT_W = 4,
    parameter int ACT_LANES = 4, // Number of activations loaded per cycle
    parameter int DM = 1,
    parameter int DK = 32,

    parameter int ADDR_W = $clog2(M * K), 
    parameter int M_W = $clog2(M),
    parameter int K_GROUPS = K / DK,
    parameter int K_GROUP_W = $clog2(K_GROUPS),
    parameter int PLANE_W = $clog2(ACT_W)
) (
    input  logic clk,

    // Interface used to load activations into the buffer   
    input  logic                    write_enable,
    input  logic [ADDR_W-1:0]       write_address,
    input  logic [ACT_LANES-1:0][ACT_W-1:0] write_data,

    // Indices selecting the requested activation bits
    input  logic [M_W-1:0]          row_base,
    input  logic [K_GROUP_W-1:0]    k_group,
    input  logic [PLANE_W-1:0]      bit_plane,

    // Selected bit plane for DM rows of DK consecutive activations
    output logic [DM-1:0][DK-1:0] plane_bits
);

    localparam int ACT_COUNT = M * K;

    // Activation memory containing M rows of K values
    logic [ACT_W-1:0] memory [0:ACT_COUNT-1];

    integer lane;
    integer dm;
    integer b;
    integer row;
    integer element_index;

    initial begin
        if ((ACT_COUNT % ACT_LANES) != 0) begin
            $fatal(1, "ACT_LANES must divide M*K.");
        end
    end

    // // Store ACT_LANES consecutive activations on each valid write
    always_ff @(posedge clk) begin
        if (write_enable) begin
            for (lane = 0; lane < ACT_LANES; lane++) begin
                memory[write_address + lane] <= write_data[lane];
            end
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
                
                // Convert the row, K group, and bit position into a flat memory address
                element_index = row * K + k_group * DK + b;

                // Select the requested bit from the activation
                plane_bits[dm][b] = memory[element_index][bit_plane];
            end
        end
    end

endmodule