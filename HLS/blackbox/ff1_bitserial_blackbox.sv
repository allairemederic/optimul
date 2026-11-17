// Vitis HLS RTL-blackbox wrapper for the M_ff1 bit-serial core

module m_ff1_bitserial_blackbox (
    input  logic         ap_clk,
    input  logic         ap_rst,
    input  logic         ap_ce,

    // ap_ctrl_chain interface
    input  logic         ap_start,
    input  logic         ap_continue,
    output logic         ap_done,
    output logic         ap_idle,
    output logic         ap_ready,

    // Transformer layer selecting the weight set
    input  logic [31:0]  layer,

    // Input FIFO interface
    input  logic         activation_empty_n,
    output logic         activation_read,
    input  logic [31:0]  activation_dout,

    // Output FIFO interface
    input  logic         result_full_n,
    output logic         result_write,
    output logic [127:0] result_din
);

    localparam int ACT_LANES = 8;
    localparam int RESULT_LANES = 8;

    logic core_start;
    logic core_busy;
    logic core_done;

    logic core_activation_valid;
    logic core_activation_ready;
    logic [ACT_LANES-1:0][3:0] core_activation_data;

    logic core_result_valid;
    logic core_result_ready;
    logic [RESULT_LANES-1:0][15:0] core_result_data;

    logic done_latched;

    // Blackbox status signals
    assign ap_done = done_latched;
    assign ap_idle = !core_busy && !done_latched;
    assign ap_ready = ap_idle;

    // Start the core when both HLS and the core are ready
    assign core_start =  ap_ce && ap_start && ap_ready;

    // Convert the HLS input FIFO interface to ready/valid
    assign core_activation_valid = ap_ce && activation_empty_n;
    assign core_activation_data = activation_dout;
    assign activation_read = ap_ce && activation_empty_n && core_activation_ready;

    // Convert the core result interface to an HLS FIFO interface
    assign core_result_ready = ap_ce && result_full_n;
    assign result_write = ap_ce && core_result_valid && result_full_n;
    assign result_din = core_result_data;

    // Hold ap_done until the surrounding HLS block acknowledges it
    always_ff @(posedge ap_clk) begin
        if (ap_rst) begin
            done_latched <= 1'b0;
        end
        else if (ap_ce) begin
            if (core_done) begin
                done_latched <= 1'b1;
            end
            else if (done_latched && ap_continue) begin
                done_latched <= 1'b0;
            end
        end
    end

    // Bit-serial M_ff1 implementation
    bitserial_top #(
        .M(4),
        .K(128),
        .N(32),

        .ACT_W(4),
        .ACT_PLANES(3),
        .WEIGHT_BITS(4),
        .ACC_W(16),

        .ACT_LANES(ACT_LANES),
        .RESULT_LANES(RESULT_LANES),

        .DM(4),
        .DN(8),
        .DK(64),

        .NUM_LAYERS(2)
    ) core (
        .clk(ap_clk),
        .reset(ap_rst),

        .start(core_start),
        .layer_select(layer[0]),

        .activation_valid(core_activation_valid),
        .activation_data(core_activation_data),
        .activation_ready(core_activation_ready),

        .result_valid(core_result_valid),
        .result_data(core_result_data),
        .result_ready(core_result_ready),

        .busy(core_busy),
        .done(core_done)
    );

endmodule