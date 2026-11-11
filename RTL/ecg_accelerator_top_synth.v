module ecg_accelerator_top_synth (
    input  wire clk,
    input  wire reset,
    input  wire start,

    input  wire signed [7:0]  ecg_input,
    input  wire signed [7:0]  fc1_weight_data,
    input  wire signed [31:0] fc1_bias_data,
    input  wire signed [7:0]  fc2_weight_data,
    input  wire signed [31:0] fc2_bias_data,

    output wire [6:0]  fc1_input_addr,
    output wire [12:0] fc1_weight_addr,
    output wire [5:0]  fc1_bias_addr,

    output wire [5:0]  fc2_input_addr,
    output wire [8:0]  fc2_weight_addr,
    output wire [2:0]  fc2_bias_addr,

    output wire signed [31:0] fc1_output,
    output wire signed [7:0]  fc1_int8_output,
    output wire signed [31:0] fc2_output,
    output wire [2:0] predicted_class,

    output wire busy,
    output wire done
);

    localparam STATE_IDLE = 2'd0;
    localparam STATE_FC1  = 2'd1;
    localparam STATE_FC2  = 2'd2;
    localparam STATE_DONE = 2'd3;

    reg [1:0] state;

    reg fc1_start;
    reg fc2_start;

    wire fc1_busy;
    wire fc1_done;
    wire fc2_busy;
    wire fc2_done;

    // FC1 -> activation buffer
    wire [5:0]        fc1_output_addr;
    wire signed [7:0] fc1_output_data;
    wire              fc1_output_valid;

    // activation buffer -> FC2
    wire signed [7:0] fc2_input_data;

    fc1_accelerator_synth fc1_unit (
        .clk(clk),
        .reset(reset),
        .start(fc1_start),
        .ecg_input(ecg_input),
        .weight_data(fc1_weight_data),
        .bias_data(fc1_bias_data),
        .input_addr(fc1_input_addr),
        .weight_addr(fc1_weight_addr),
        .bias_addr(fc1_bias_addr),
        .output_addr(fc1_output_addr),
        .output_data(fc1_output_data),
        .output_valid(fc1_output_valid),
        .fc1_output(fc1_output),
        .fc1_int8_output(fc1_int8_output),
        .busy(fc1_busy),
        .done(fc1_done)
    );

    act_buffer act_buf (
        .clk(clk),
        .wr_en(fc1_output_valid),
        .wr_addr(fc1_output_addr),
        .wr_data(fc1_output_data),
        .rd_addr(fc2_input_addr),
        .rd_data(fc2_input_data)
    );

    fc2_accelerator_synth fc2_unit (
        .clk(clk),
        .reset(reset),
        .start(fc2_start),
        .input_data(fc2_input_data),
        .weight_data(fc2_weight_data),
        .bias_data(fc2_bias_data),
        .input_addr(fc2_input_addr),
        .weight_addr(fc2_weight_addr),
        .bias_addr(fc2_bias_addr),
        .fc2_output(fc2_output),
        .predicted_class(predicted_class),
        .busy(fc2_busy),
        .done(fc2_done)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state     <= STATE_IDLE;
            fc1_start <= 1'b0;
            fc2_start <= 1'b0;
        end else begin
            fc1_start <= 1'b0;
            fc2_start <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    if (start) begin
                        fc1_start <= 1'b1;
                        state     <= STATE_FC1;
                    end
                end

                STATE_FC1: begin
                    if (fc1_done) begin
                        fc2_start <= 1'b1;
                        state     <= STATE_FC2;
                    end
                end

                STATE_FC2: begin
                    if (fc2_done)
                        state <= STATE_DONE;
                end

                STATE_DONE: begin
                    state <= STATE_IDLE;
                end

                default: begin
                    state <= STATE_IDLE;
                end
            endcase
        end
    end

    assign busy = (state == STATE_FC1) || (state == STATE_FC2);
    assign done = fc2_done;

endmodule
