`timescale 1ns / 10ps
/* verilator coverage_off */

module tb_mac_pe ();
    localparam CLK_PERIOD = 10;

    logic clk, n_rst;
    logic load_weights, run_array;
    logic [15:0] x_in, weight_in;
    logic [31:0] psum_in;
    logic [15:0] x_out;
    logic [15:0] weight_out;
    logic [31:0] sum_out;

    localparam BF16_0_0 = 16'h0000;
    localparam BF16_2_0 = 16'h4000;
    localparam BF16_3_0 = 16'h4040;
    localparam BF16_5_0 = 16'h40A0;
    localparam BF16_NEG_2_0 = 16'hC000;
    localparam FP32_0_0 = 32'h0000_0000;
    localparam FP32_1_0 = 32'h3F80_0000;
    localparam FP32_7_0 = 32'h40E0_0000;
    localparam FP32_10_0 = 32'h4120_0000;
    localparam FP32_4_0 = 32'h4080_0000;
    localparam FP32_NEG_5_0 = 32'hC0A0_0000;

    string test_name;

    mac_pe DUT (.*);

    always begin
        clk = 0;
        #(CLK_PERIOD / 2.0);
        clk = 1;
        #(CLK_PERIOD / 2.0);
    end

    task reset_dut;
    begin
        n_rst = 0;
        load_weights = 0;
        run_array = 0;
        x_in = BF16_0_0;
        weight_in = BF16_0_0;
        psum_in = FP32_0_0;
        @(negedge clk);
        @(negedge clk);
        n_rst = 1;
        @(negedge clk);
    end
    endtask

    initial begin
        $dumpfile("waveform_mac_pe.vcd");
        $dumpvars(0, tb_mac_pe); 

        //test 1: reset dut
        test_name = "reset test";
        reset_dut();
        repeat(3) @(negedge clk);

        //test 2: weight loading
        test_name = "weight loading test";
        load_weights = 1'b1;
        weight_in = BF16_2_0;
        @(negedge clk);
        load_weights = 1'b0;
        weight_in = BF16_0_0;
        repeat(2) @(negedge clk);

        //test 3: pipeline firing
        //(weight * x_in) + psum_in -> (2.0 * 3.0) + 1.0 = 7.0
        test_name = "pipeline firing test";
        run_array = 1'b1;
        x_in = BF16_3_0;
        psum_in = FP32_1_0;
        @(negedge clk);
        //return inputs to 0
        x_in = BF16_0_0;
        psum_in = FP32_0_0;
        //wait for pipeline delay
        repeat(5) @(negedge clk); // Already waited 1 cycle above
        //check math
        if (sum_out == FP32_7_0) begin
            $display("Pass, output is 7.0 (0x%h)", sum_out);
        end else begin
            $display("Fail, expected 7.0 (0x%h), but got (0x%h)", FP32_7_0, sum_out);
        end
        //check pass-through
        if (x_out == BF16_0_0) begin
            $display("Pass, horizontal pipeline clear.");
        end else begin
            $display("Fail, horizontal pipeline not clear.");
        end
        repeat(5) @(negedge clk);

        //test 4: zero weight check -> (0.0 * 5.0) + 1.0 = 1.0
        test_name = "zero weight check test";
        load_weights = 1'b1;
        weight_in = BF16_0_0;
        @(negedge clk);
        load_weights = 1'b0;
        repeat(2) @(negedge clk);
        run_array = 1'b1;
        x_in = BF16_5_0;
        psum_in = FP32_1_0;
        @(negedge clk);
        x_in = BF16_0_0;
        psum_in = FP32_0_0;
        repeat(5) @(negedge clk); 
        if (sum_out == FP32_1_0) begin
            $display("Pass, output is 1.0 (0x%h)", sum_out);
        end else begin
            $display("Fail, expected 1.0 (0x%h), but got (0x%h)", FP32_1_0, sum_out);
        end
        repeat(5) @(negedge clk);

        //test 5: negative multiplication -> (-2.0 * 3.0) + 10.0 = 4.0
        test_name = "negative multiplication test";
        load_weights = 1'b1;
        weight_in = BF16_NEG_2_0;
        @(negedge clk);
        load_weights = 1'b0;
        weight_in = BF16_0_0;
        repeat(2) @(negedge clk);
        run_array = 1'b1;
        x_in = BF16_3_0;
        psum_in = FP32_10_0;
        @(negedge clk);
        x_in = BF16_0_0;
        psum_in = FP32_0_0;
        repeat(5) @(negedge clk); 
        if (sum_out == FP32_4_0) begin
            $display("Pass, output is 4.0 (0x%h)", sum_out);
        end else begin
            $display("Fail, expected 4.0 (0x%h), but got (0x%h)", FP32_4_0, sum_out);
        end
        repeat(5) @(negedge clk);

        //test 6: negative result -> (-2.0 * 3.0) + 1.0 = -5.0
        test_name = "negative result test";
        run_array = 1'b1;
        x_in = BF16_3_0;
        psum_in = FP32_1_0;
        @(negedge clk);
        x_in = BF16_0_0;
        psum_in = FP32_0_0;
        repeat(5) @(negedge clk); 
        if (sum_out == FP32_NEG_5_0) begin
            $display("Pass, output is -5.0 (0x%h)", sum_out);
        end else begin
            $display("Fail, expected -5.0 (0x%h), but got (0x%h)", FP32_NEG_5_0, sum_out);
        end
        repeat(5) @(negedge clk);
        
        $display("All tests completed!");
        $finish;
    end

endmodule

/* verilator coverage_on */