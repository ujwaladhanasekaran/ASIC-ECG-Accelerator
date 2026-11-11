
module fc1_accelerator_synth #(
    parameter signed [31:0] FC1_ACTIVATION_MAX = 32'sd99580
) (
    input wire clk,
    input wire reset,
    input wire start,

    input wire signed [7:0] ecg_input,
    input wire signed [7:0] weight_data,
    input wire signed [31:0] bias_data,

    output reg [6:0] input_addr,
    output reg [12:0] weight_addr,
    output reg [5:0] bias_addr,

    output reg [5:0] output_addr,
    output reg signed [7:0] output_data,
    output reg output_valid,

    output reg signed [31:0] fc1_output,
    output reg signed [7:0] fc1_int8_output,

    output reg busy,
    output reg done
);

    localparam IDLE    = 2'd0;
    localparam COMPUTE = 2'd1;
    localparam FINISH  = 2'd2;

    localparam integer REQ_S = 41;
    localparam [63:0] REQ_M =
        ((64'd1 << REQ_S) + FC1_ACTIVATION_MAX - 1)
        / FC1_ACTIVATION_MAX;
    localparam [23:0] REQ_HALF = FC1_ACTIVATION_MAX / 2;

    reg [1:0] state;
    reg [6:0] sample_count;
    reg [5:0] neuron_count;

    reg signed [31:0] accumulator;
    reg signed [15:0] product;
    reg signed [31:0] sum_value;

    reg [16:0] sum_clamped;
    reg [23:0] req_num;
    reg [63:0] req_prod;
    reg [7:0] requant_int8;

    always @* begin
        product = $signed(ecg_input) * $signed(weight_data);
        sum_value = accumulator + product;

        sum_clamped = 17'd0;
        req_num = 24'd0;
        req_prod = 64'd0;
        requant_int8 = 8'd0;

        if (sum_value <= 0) begin
            requant_int8 = 8'd0;
        end else if (sum_value >= FC1_ACTIVATION_MAX) begin
            requant_int8 = 8'd127;
        end else begin
            sum_clamped = sum_value[16:0];
            req_num = (sum_clamped * 24'd127) + REQ_HALF;
            req_prod = req_num * REQ_M;

            requant_int8 =
                (req_prod >> REQ_S) > 64'd127
                ? 8'd127
                : req_prod[REQ_S +: 8];
        end
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state <= IDLE;
            sample_count <= 0;
            neuron_count <= 0;
            accumulator <= 0;

            input_addr <= 0;
            weight_addr <= 0;
            bias_addr <= 0;
            output_addr <= 0;
            output_data <= 0;
            output_valid <= 0;

            fc1_output <= 0;
            fc1_int8_output <= 0;
            busy <= 0;
            done <= 0;
        end else begin
            done <= 0;
            output_valid <= 0;

            case (state)
                IDLE: begin
                    busy <= 0;

                    if (start) begin
                        sample_count <= 0;
                        neuron_count <= 0;
                        input_addr <= 0;
                        weight_addr <= 0;
                        bias_addr <= 0;
                        output_addr <= 0;
                        accumulator <= 0;
                        busy <= 1;
                        state <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    if (sample_count == 0)
                        accumulator <= bias_data + product;
                    else
                        accumulator <= sum_value;

                    if (sample_count == 127) begin
                        fc1_output <= sum_value;
                        output_data <= requant_int8;
                        fc1_int8_output <= requant_int8;
                        output_addr <= neuron_count;
                        output_valid <= 1;

                        if (neuron_count == 63) begin
                            state <= FINISH;
                        end else begin
                            neuron_count <= neuron_count + 1'b1;
                            sample_count <= 0;
                            input_addr <= 0;
                            weight_addr <=
                                (neuron_count + 6'd1) * 13'd128;
                            bias_addr <= neuron_count + 6'd1;
                            accumulator <= 0;
                        end
                    end else begin
                        sample_count <= sample_count + 1'b1;
                        input_addr <= sample_count + 1'b1;
                        weight_addr <= weight_addr + 1'b1;
                    end
                end

                FINISH: begin
                    busy <= 0;
                    done <= 1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy <= 0;
                end
            endcase
        end
    end

endmodule
