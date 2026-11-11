module fc2_accelerator_synth (
    input  wire clk,
    input  wire reset,
    input  wire start,

    input  wire signed [7:0]  input_data,
    input  wire signed [7:0]  weight_data,
    input  wire signed [31:0] bias_data,

    output reg  [5:0] input_addr,
    output reg  [8:0] weight_addr,
    output reg  [2:0] bias_addr,

    output reg signed [31:0] fc2_output,
    output reg [2:0] predicted_class,

    output reg busy,
    output reg done
);

    localparam IDLE    = 2'd0;
    localparam COMPUTE = 2'd1;
    localparam FINISH  = 2'd2;

    reg [1:0] state;

    reg [5:0] input_count;
    reg [2:0] class_count;

    reg signed [15:0] product;
    reg signed [31:0] accumulator;
    reg signed [31:0] sum_value;
    reg signed [31:0] current_score;

    reg signed [31:0] score0;
    reg signed [31:0] score1;
    reg signed [31:0] score2;
    reg signed [31:0] score3;
    reg signed [31:0] score4;

    always @* begin
        product = $signed(input_data) * $signed(weight_data);
        sum_value = accumulator + product;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state          <= IDLE;
            input_count    <= 6'd0;
            class_count    <= 3'd0;
            input_addr     <= 6'd0;
            weight_addr    <= 9'd0;
            bias_addr      <= 3'd0;
            accumulator    <= 32'sd0;
            current_score  <= 32'sd0;
            score0         <= 32'sd0;
            score1         <= 32'sd0;
            score2         <= 32'sd0;
            score3         <= 32'sd0;
            score4         <= 32'sd0;
            fc2_output     <= 32'sd0;
            predicted_class <= 3'd0;
            busy           <= 1'b0;
            done           <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        input_count <= 6'd0;
                        class_count <= 3'd0;
                        input_addr  <= 6'd0;
                        weight_addr <= 9'd0;
                        bias_addr   <= 3'd0;
                        accumulator <= 32'sd0;
                        busy        <= 1'b1;
                        state       <= COMPUTE;
                    end
                end

                COMPUTE: begin
                    if (input_count == 6'd0)
                        accumulator <= bias_data + product;
                    else
                        accumulator <= sum_value;

                    if (input_count == 6'd63) begin
                        current_score <= sum_value;

                        case (class_count)
                            3'd0: score0 <= sum_value;
                            3'd1: score1 <= sum_value;
                            3'd2: score2 <= sum_value;
                            3'd3: score3 <= sum_value;
                            3'd4: score4 <= sum_value;
                            default: begin end
                        endcase

                        if (class_count == 3'd4) begin
                            if ((score0 >= score1) &&
                                (score0 >= score2) &&
                                (score0 >= score3) &&
                                (score0 >= sum_value)) begin
                                fc2_output <= score0;
                                predicted_class <= 3'd0;
                            end else if ((score1 > score0) &&
                                         (score1 >= score2) &&
                                         (score1 >= score3) &&
                                         (score1 >= sum_value)) begin
                                fc2_output <= score1;
                                predicted_class <= 3'd1;
                            end else if ((score2 > score0) &&
                                         (score2 > score1) &&
                                         (score2 >= score3) &&
                                         (score2 >= sum_value)) begin
                                fc2_output <= score2;
                                predicted_class <= 3'd2;
                            end else if ((score3 > score0) &&
                                         (score3 > score1) &&
                                         (score3 > score2) &&
                                         (score3 >= sum_value)) begin
                                fc2_output <= score3;
                                predicted_class <= 3'd3;
                            end else begin
                                fc2_output <= sum_value;
                                predicted_class <= 3'd4;
                            end

                            state <= FINISH;
                        end else begin
                            class_count <= class_count + 3'd1;
                            weight_addr <=
                                (class_count + 3'd1) * 9'd64;
                            bias_addr <= class_count + 3'd1;
                            input_count <= 6'd0;
                            input_addr <= 6'd0;
                            accumulator <= 32'sd0;
                        end
                    end else begin
                        input_count <= input_count + 6'd1;
                        input_addr <= input_count + 6'd1;
                        weight_addr <= weight_addr + 9'd1;
                    end
                end

                FINISH: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
