`timescale 1ns / 10ps
/* verilator coverage_off */

module tb_weight_double_buffer ();

    localparam CLK_PERIOD = 10;
    localparam ADDR_WIDTH = 11;
    localparam DATA_WIDTH = 4096;

    logic clk, n_rst;
    logic [ADDR_WIDTH-1:0] dma_addr;
    logic [DATA_WIDTH-1:0] dma_data;
    logic dma_we;
    logic [ADDR_WIDTH-1:0] mxu_addr;
    logic mxu_re;
    logic [DATA_WIDTH-1:0] mxu_data;
    logic swap_banks;

    string test_name;

    weight_double_buffer #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) DUT (.*);

    always begin
        clk = 0;
        #(CLK_PERIOD / 2.0);
        clk = 1;
        #(CLK_PERIOD / 2.0);
    end

    task reset_dut;
    begin
        n_rst = 0;
        dma_addr = '0;
        dma_data = '0;
        dma_we = 0;
        mxu_addr = '0;
        mxu_re = 0;
        swap_banks = 0;
        @(negedge clk);
        @(negedge clk);
        n_rst = 1;
        @(negedge clk);
    end
    endtask

    initial begin
        $dumpfile("waveform_wdb.vcd");
        $dumpvars(0, tb_weight_double_buffer); 

        //test 1: reset
        test_name = "reset test";
        reset_dut();
        repeat(3) @(negedge clk);

        //test 2: write to hidden bank (bank 1)
        test_name = "write to hidden bank";
        dma_addr = 11'd5;
        dma_data = '0; 
        dma_data[31:0] = 32'hDEADBEEF; //recognizable value
        dma_we = 1'b1;
        @(negedge clk);
        dma_we = 1'b0;
        dma_data = '0;
        //read attempt from active bank at the same address
        mxu_addr = 11'd5;
        mxu_re = 1'b1;
        @(negedge clk); 
        mxu_re = 1'b0;
        @(negedge clk); //sram read latency
        //bank1 should read ! the value of bank0
        if (mxu_data[31:0] !== 32'hDEADBEEF) begin
            $display("Pass: Bank 0 successfully isolated from Bank 1 writes.");
        end else begin
            $display("Fail: Data leaked across banks!");
        end
        repeat(3) @(negedge clk);

        //test 3: swap banks and verify
        test_name = "swap and read active bank (bank 1)";
        swap_banks = 1'b1;
        @(negedge clk);
        swap_banks = 1'b0;
        //read from address 5 now that bank1 active
        mxu_addr = 11'd5;
        mxu_re = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        @(negedge clk); 
        if (mxu_data[31:0] == 32'hDEADBEEF) begin
            $display("Pass: Successfully swapped and read DEADBEEF from Bank 1.");
        end else begin
            $display("Fail: Failed to read expected data from swapped Bank 1.");
        end
        repeat(3) @(negedge clk);

        //test 4: write to new hidden bank (bank 0)
        test_name = "write hidden bank (bank 0)";
        dma_addr = 11'd10;
        dma_data = '0;
        dma_data[31:0] = 32'hCAFEBABE;
        dma_we = 1'b1;
        @(negedge clk);
        dma_we = 1'b0;
        repeat(3) @(negedge clk);

        //test 5: swap back and verify
        test_name = "swap and read active bank (Bank 0)";
        swap_banks = 1'b1;
        @(negedge clk);
        swap_banks = 1'b0;
        //bank0 active, read from address 10
        mxu_addr = 11'd10;
        mxu_re = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        @(negedge clk); 
        if (mxu_data[31:0] == 32'hCAFEBABE) begin
            $display("Pass: Successfully swapped and read CAFEBABE from Bank 0.");
        end else begin
            $display("Fail: Failed to read expected data from swapped Bank 0.");
        end
        
        //test 6: simultaneous read/write to same address on different banks
        test_name = "simultaneous read/write collision check";
        //bank0 active, bank1 hidden
        dma_addr = 11'd20;
        dma_data = '0;
        dma_data[31:0] = 32'h99999999;
        dma_we = 1'b1;
        mxu_addr = 11'd20;
        mxu_re = 1'b1;
        @(negedge clk);
        dma_we = 1'b0;
        mxu_re = 1'b0;
        @(negedge clk); //sram read latency
        if (mxu_data[31:0] !== 32'h99999999) begin
            $display("Pass: MXU read active bank successfully while DMA wrote hidden bank.");
        end else begin
            $display("Fail: MXU read corrupted by simultaneous DMA write.");
        end
        repeat(3) @(negedge clk);

        //test 7: max address boundary check
        test_name = "max address boundary check";
        //write to highest possible address (2047)
        dma_addr = 11'h7FF; 
        dma_data = '0;
        dma_data[31:0] = 32'hFACEFEED;
        dma_we = 1'b1;
        @(negedge clk);
        dma_we = 1'b0;
        swap_banks = 1'b1;
        @(negedge clk);
        swap_banks = 1'b0;
        //bank1 now active, read from max address
        mxu_addr = 11'h7FF;
        mxu_re = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        @(negedge clk);
        if (mxu_data[31:0] == 32'hFACEFEED) begin
            $display("Pass: Max address boundary write and read successful.");
        end else begin
            $display("Fail: Max address boundary check failed.");
        end
        repeat(3) @(negedge clk);

        //test 8: rapid back-to-back swaps
        test_name = "rapid swap check";
        //swap twice in a row: bank1 -> bank0 -> bank1
        swap_banks = 1'b1;
        @(negedge clk);
        @(negedge clk);
        swap_banks = 1'b0;
        //read highest address again, should output same as previous test
        mxu_addr = 11'h7FF;
        mxu_re = 1'b1;
        @(negedge clk);
        mxu_re = 1'b0;
        @(negedge clk);
        if (mxu_data[31:0] == 32'hFACEFEED) begin
            $display("Pass: Rapid back-to-back swaps resolved correctly.");
        end else begin
            $display("Fail: Rapid swapping lost track of active bank.");
        end

        repeat(5) @(negedge clk);
        $display("All WDB tests completed!");
        $finish;
    end

endmodule

/* verilator coverage_on */