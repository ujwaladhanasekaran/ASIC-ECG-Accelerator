
module act_buffer (
    input wire clk,
    input wire wr_en,
    input wire [5:0] wr_addr,
    input wire signed [7:0] wr_data,
    input wire [5:0] rd_addr,
    output wire signed [7:0] rd_data
);

    reg signed [7:0] mem [0:63];

    always @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    assign rd_data = mem[rd_addr];

endmodule
