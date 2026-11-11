`timescale 1ns/1ps
// Self-checking testbench for ecg_accelerator_top_synth.
// Run gen_vectors.py first; it writes the .hex files read below.
module tb_ecg_accelerator;
    parameter N = 20;

    reg clk = 0, reset = 1, start = 0;
    always #5 clk = ~clk;

    reg signed [7:0]  w1 [0:64*128-1];
    reg signed [31:0] b1 [0:63];
    reg signed [7:0]  w2 [0:5*64-1];
    reg signed [31:0] b2 [0:4];
    reg signed [7:0]  x  [0:N*128-1];
    reg [7:0]  exp_act   [0:N*64-1];
    reg [3:0]  exp_class [0:N-1];
    reg signed [31:0] exp_score [0:N-1];

    integer vec = 0;

    wire [6:0]  fc1_input_addr;  wire [12:0] fc1_weight_addr; wire [5:0] fc1_bias_addr;
    wire [5:0]  fc2_input_addr;  wire [8:0]  fc2_weight_addr; wire [2:0] fc2_bias_addr;
    wire signed [31:0] fc1_output, fc2_output;
    wire signed [7:0]  fc1_int8_output;
    wire [2:0] predicted_class;
    wire busy, done;

    // Asynchronous-read memory models
    wire signed [7:0]  ecg_input       = x[vec*128 + fc1_input_addr];
    wire signed [7:0]  fc1_weight_data = w1[fc1_weight_addr];
    wire signed [31:0] fc1_bias_data   = b1[fc1_bias_addr];
    wire signed [7:0]  fc2_weight_data = w2[fc2_weight_addr];
    wire signed [31:0] fc2_bias_data   = b2[fc2_bias_addr];

    ecg_accelerator_top_synth dut (
        .clk(clk), .reset(reset), .start(start),
        .ecg_input(ecg_input),
        .fc1_weight_data(fc1_weight_data), .fc1_bias_data(fc1_bias_data),
        .fc2_weight_data(fc2_weight_data), .fc2_bias_data(fc2_bias_data),
        .fc1_input_addr(fc1_input_addr), .fc1_weight_addr(fc1_weight_addr),
        .fc1_bias_addr(fc1_bias_addr),
        .fc2_input_addr(fc2_input_addr), .fc2_weight_addr(fc2_weight_addr),
        .fc2_bias_addr(fc2_bias_addr),
        .fc1_output(fc1_output), .fc1_int8_output(fc1_int8_output),
        .fc2_output(fc2_output), .predicted_class(predicted_class),
        .busy(busy), .done(done)
    );

    integer i, errors = 0, cycles, t0;

    initial begin
        $readmemh("w1.hex", w1); $readmemh("b1.hex", b1);
        $readmemh("w2.hex", w2); $readmemh("b2.hex", b2);
        $readmemh("x.hex",  x);
        $readmemh("exp_act.hex", exp_act);
        $readmemh("exp_class.hex", exp_class);
        $readmemh("exp_score.hex", exp_score);

        repeat (3) @(posedge clk);
        reset = 0;

        for (vec = 0; vec < N; vec = vec + 1) begin
            @(negedge clk) start = 1;
            @(negedge clk) start = 0;
            t0 = $time;
            @(posedge done); #1;
            cycles = ($time - t0) / 10;

            for (i = 0; i < 64; i = i + 1)
                if (dut.act_buf.mem[i] !== exp_act[vec*64 + i]) begin
                    errors = errors + 1;
                    $display("vec %0d act[%0d]: got %0d exp %0d",
                             vec, i, dut.act_buf.mem[i], exp_act[vec*64 + i]);
                end

            if (predicted_class !== exp_class[vec][2:0] ||
                fc2_output      !== exp_score[vec]) begin
                errors = errors + 1;
                $display("vec %0d FAIL: class %0d score %0d (exp %0d / %0d)",
                         vec, predicted_class, fc2_output,
                         exp_class[vec], exp_score[vec]);
            end else
                $display("vec %0d ok: class %0d score %0d  (%0d cycles)",
                         vec, predicted_class, fc2_output, cycles);

            @(posedge clk); #1;   // state leaves FC2 one clock after done
            if (busy) begin errors = errors + 1; $display("busy stuck high"); end
            repeat (2) @(posedge clk);
        end

        if (errors == 0) $display("PASS: all %0d vectors match the golden model", N);
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end
endmodule
