`timescale 1ns / 10ps
/* verilator coverage_off */

module tb_uab_memory ();

    localparam CLK_PERIOD = 10;
    localparam ADDR_WIDTH = 15;
    localparam DATA_WIDTH = 4096;

    logic clk, n_rst;
    logic advance_layer;
    logic [ADDR_WIDTH-1:0] next_write_allocation;
    logic [ADDR_WIDTH-1:0] relative_read_addr;
    logic mxu_re;
    logic [DATA_WIDTH-1:0] mxu_rdata;
    logic [ADDR_WIDTH-1:0] relative_write_addr;
    logic mxu_we;
    logic [DATA_WIDTH-1:0] mxu_wdata;

    string test_name;

    uab_memory #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) DUT (.*);

    always begin
        clk = 0;
        #(CLK_PERIOD / 2.0);
        clk = 1;
        #(CLK_PERIOD / 2.0);
    end

    task reset_dut;
    begin
        n_rst = 0;
        advance_layer = 0;
        next_write_allocation = '0;
        relative_read_addr = '0;
        mxu_re = 0;
        relative_write_addr = '0;
        mxu_we = 0;
        mxu_wdata = '0;
        @(negedge clk);
        @(negedge clk);
        n_rst = 1;
        @(negedge clk);
    end
    endtask

    initial begin
        $dumpfile("waveform_uab.vcd");
        $dumpvars(0, tb_uab_memory); 

        //test 1: reset
        test_name = "reset test";
        reset_dut();
        repeat(3) @(negedge clk);

        //test 2: layer0 input hold
        //at reset both read_base and write_base are 0
        test_name = "layer0 host write";
        relative_write_addr = 15'd5;
        mxu_wdata = '0;
        mxu_wdata[31:0] = 32'hAAAA_BBBB;
        mxu_we = 1'b1;
        @(negedge clk);
        mxu_we = 1'b0;
        mxu_wdata = '0;
        repeat(3) @(negedge clk);

        //test 3: advance to layer1
        //tell uab we need 1000 words after finishing layer0
        test_name = "advance to layer1";
        advance_layer = 1'b1;
        next_write_allocation = 15'd1000;
        @(negedge clk);
        advance_layer = 1'b0;
        repeat(3) @(negedge clk);

        //test 4: layer1 execution
        test_name = "layer1 execution";
        //first read the data wrote in layer0
        //after the advanced layer the read_base is 0
        relative_read_addr = 15'd5;
        mxu_re = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        @(negedge clk); //sram read latency
        if (mxu_rdata[31:0] == 32'hAAAA_BBBB) begin
            $display("Pass: Layer 1 successfully read Layer 0's inputs.");
        end else begin
            $display("Fail: Layer 1 pointer arithmetic failed to read old layer data.");
        end
        //next write layer1 results
        relative_write_addr = 15'd10; //maps to 1010
        mxu_wdata = '0;
        mxu_wdata[31:0] = 32'hFACE_FEED;
        mxu_we = 1'b1;
        @(negedge clk);
        mxu_we = 1'b0;
        mxu_wdata = '0;
        repeat(3) @(negedge clk);

        //test 5: advance to layer2
        //tell uab we need 500 words after finishing layer1
        test_name = "advance to layer2";
        advance_layer = 1'b1;
        next_write_allocation = 15'd500;
        @(negedge clk);
        advance_layer = 1'b0;
        repeat(3) @(negedge clk);

        //test 6: layer2 Execution
        test_name = "layer 2 execution";
        //read_base 1000
        //reading relative address 10 should pull from address 1010
        relative_read_addr = 15'd10;
        mxu_re = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        @(negedge clk); //sram read latency
        if (mxu_rdata[31:0] == 32'hFACE_FEED) begin
            $display("Pass: Layer 2 successfully read Layer 1's outputs.");
        end else begin
            $display("Fail: Layer 2 pointer arithmetic failed to track shifted base.");
        end
        repeat(3) @(negedge clk);

        //test 7: wrap around check
        //0 to 32,767 address space, push past
        test_name = "address space wrap-around";
        advance_layer = 1'b1;
        next_write_allocation = 15'd32000; //pushes write_base past 32767
        @(negedge clk);
        advance_layer = 1'b0;
        repeat(2) @(negedge clk);
        relative_write_addr = 15'd100;
        mxu_wdata = '0;
        mxu_wdata[31:0] = 32'h1111_2222;
        mxu_we = 1'b1;
        @(negedge clk);
        mxu_we = 1'b0;
        mxu_wdata = '0;
        advance_layer = 1'b1;
        next_write_allocation = 15'd100; //read_base following write_base
        @(negedge clk);
        advance_layer = 1'b0;
        repeat(2) @(negedge clk);
        relative_read_addr = 15'd100;
        mxu_re = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        @(negedge clk);
        if (mxu_rdata[31:0] == 32'h1111_2222) begin
            $display("Pass: UAB successfully wrapped around the 15-bit memory boundary.");
        end else begin
            $display("Fail: UAB wrap-around corrupted memory pointers.");
        end

        //test 8: simultaneous read/write check
        test_name = "simultaneous read/write";
        //read from relative address 100 while writing to relative address 200
        relative_read_addr = 15'd100;
        relative_write_addr = 15'd200;
        mxu_wdata = '0;
        mxu_wdata[31:0] = 32'h3333_4444;
        mxu_re = 1'b1;
        mxu_we = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        mxu_we = 1'b0;
        mxu_wdata = '0;
        @(negedge clk); //sram read latency
        if (mxu_rdata[31:0] == 32'h1111_2222) begin
            $display("Pass: Dual-port read successful during simultaneous write.");
        end else begin
            $display("Fail: Dual-port read corrupted by simultaneous write.");
        end
        //verify the simultaneous write landed in memory
        relative_read_addr = 15'd200;
        mxu_re = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        @(negedge clk);
        if (mxu_rdata[31:0] == 32'h3333_4444) begin
            $display("Pass: Dual-port write successful during simultaneous read.");
        end else begin
            $display("Fail: Dual-port write corrupted by simultaneous read.");
        end
        repeat(3) @(negedge clk);

        //test 9: zero allocation advance
        //if a layer requires no new memory, read_base and write_base lock together
        test_name = "zero allocation advance";
        advance_layer = 1'b1;
        next_write_allocation = 15'd0;
        @(negedge clk);
        advance_layer = 1'b0;
        repeat(2) @(negedge clk);
        relative_write_addr = 15'd10;
        mxu_wdata = '0;
        mxu_wdata[31:0] = 32'h9999_8888;
        mxu_we = 1'b1;
        @(negedge clk);
        mxu_we = 1'b0;
        mxu_wdata = '0;
        //write allocation 0 means read_base == write_base
        //reading at relative 10 should hit the same address as writing at relative 10
        relative_read_addr = 15'd10;
        mxu_re = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        @(negedge clk);
        if (mxu_rdata[31:0] == 32'h9999_8888) begin
            $display("Pass: Zero allocation advance maintained pointer alignment.");
        end else begin
            $display("Fail: Zero allocation advance misaligned pointers.");
        end

        repeat(5) @(negedge clk);
        $display("All UAB tests completed!");
        $finish;
    end

endmodule

/* verilator coverage_on */