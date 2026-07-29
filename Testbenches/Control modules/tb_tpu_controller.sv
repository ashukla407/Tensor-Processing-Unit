`timescale 1ns / 10ps
/* verilator coverage_off */

module tb_tpu_controller ();

    localparam CLK_PERIOD = 10;

    localparam IMEM_ADDR_WIDTH = 12;
    localparam UAB_ADDR_WIDTH  = 15;
    localparam ACC_ADDR_WIDTH  = 11;

    logic clk, n_rst;
    logic [IMEM_ADDR_WIDTH-1:0] imem_addr;
    logic [31:0] imem_data;
    logic pipeline_en, uab_advance_layer;
    logic [UAB_ADDR_WIDTH-1:0] uab_next_alloc, uab_rel_raddr, uab_rel_waddr;
    logic uab_re, uab_we;
    logic wdb_swap_banks;
    logic [ACC_ADDR_WIDTH-1:0] acc_raddr, acc_waddr;
    logic acc_re, acc_we;
    logic mxu_load_weights, mxu_run_array, act_apply_relu;
    logic dma_req_valid;
    logic [3:0] dma_req_type;
    logic [27:0] dma_req_payload;
    logic dma_idle;
    logic host_interrupt;

    string test_name;

    tpu_controller #(.IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH), .UAB_ADDR_WIDTH(UAB_ADDR_WIDTH),
                     .ACC_ADDR_WIDTH(ACC_ADDR_WIDTH))
                     DUT (.*);

    always begin
        clk = 0;
        #(CLK_PERIOD / 2.0);
        clk = 1;
        #(CLK_PERIOD / 2.0);
    end

    task reset_dut;
    begin
        n_rst = 0;
        imem_data = 32'h0000_0000; //nop
        dma_idle = 1'b1;
        @(negedge clk);
        @(negedge clk);
        n_rst = 1;
        @(negedge clk);
    end
    endtask

    initial begin
        $dumpfile("waveform_tpu_controller.vcd");
        $dumpvars(0, tb_tpu_controller); 

        test_name = "Initialization & Reset";
        reset_dut();
        repeat(3) @(negedge clk);

        //test 1: dma request
        test_name = "dma request";
        imem_data = 32'h100A_0B0C; // OP_LD_WT (0x1), Payload: 0x0A0B0C
        @(negedge clk); //fetch -> decode
        @(negedge clk); //decode -> fetch
        if (dma_req_valid == 1'b1 && dma_req_type == 4'h1 && dma_req_payload == 28'h0A0B0C) 
            $display("Pass: DMA Request correctly parsed and asserted.");
        else $display("Fail: DMA Request invalid.");
        imem_data = 32'h0000_0000;
        repeat(3) @(negedge clk);

        //test 2: sync stall
        test_name = "sync stall";
        dma_idle = 1'b0; // Force DMA to appear busy
        imem_data = 32'h2000_0001; // OP_SYNC wait_for_dma=1
        @(negedge clk); //fetch -> decode
        @(negedge clk); //decode -> wait_sync
        imem_data = 32'h0000_0000; 
        repeat(3) @(negedge clk); // Should stall here
        if (DUT.state == 3'b011) $display("Pass: Controller stalled successfully in WAIT_SYNC.");
        else $display("Fail: Controller did not stall.");
        dma_idle = 1'b1; // Release the DMA
        @(negedge clk); //wait_sync -> fetch
        if (DUT.state == 3'b000) $display("Pass: Controller escaped WAIT_SYNC upon idle.");
        else $display("Fail: Controller stuck in WAIT_SYNC.");
        repeat(3) @(negedge clk);

        //test 3: uab advance
        test_name = "uab advance";
        imem_data = 32'h7000_0100; // OP_UAB_ADV, Alloc Size: 0x100
        @(negedge clk); //fetch -> decode
        @(negedge clk); //decode -> fetch
        if (uab_advance_layer == 1'b1 && uab_next_alloc == 15'h0100)
            $display("Pass: UAB Advance correctly pulsed.");
        else $display("Fail: UAB Advance invalid.");
        imem_data = 32'h0000_0000;
        repeat(3) @(negedge clk);

        //test 4: hardware loop pc jump
        test_name = "hardware loop pc jump";
        imem_data = 32'hB000_0102; // OP_REPEAT loop=1, instr=2
        @(negedge clk); //fetch -> decode
        @(negedge clk); //decode -> fetch
        imem_data = 32'h0000_0000; 
        // Let the NOPs execute. 2 NOPs should trigger the loop to jump back.
        repeat(6) @(negedge clk); 
        if (imem_addr < 10) // Basic bounds check to ensure PC looped backward
            $display("Pass: Program Counter looped backward.");
        else $display("Fail: Program Counter ignored REPEAT block.");
        repeat(3) @(negedge clk);

        //test 5: wdb_swap
        test_name = "wdb_swap";
        imem_data = 32'h3000_0000; 
        @(negedge clk); //fetch -> decode
        @(negedge clk); //decode -> execute
        if (wdb_swap_banks == 1'b1) $display("Pass: wdb_swap_banks asserted.");
        else $display("Fail: wdb_swap_banks not asserted.");        
        //back to nop
        imem_data = 32'h0000_0000;
        repeat(3) @(negedge clk);

        //test 6: matmul stream
        //acc_en=0, acc_addr=0, uab_read_addr=0
        test_name = "matmul stream";
        imem_data = 32'h5000_0000;
        @(negedge clk); //fetch-> decode
        imem_data = 32'h0000_0000; //nop instruction, should be ignored
        @(negedge clk); //decode-> execute
        //should hold run array for 256 cycles
        if (mxu_run_array == 1'b1) $display("Pass: Array stream started.");
        else $display("Fail: Array stream not started.");
        //wait until end of stream
        repeat(255) @(negedge clk);
        if (mxu_run_array == 1'b1) $display("Pass: Array stream held for 256th cycle.");
        else $display("Fail: Array stream dropped early.");
        //wait one cycle to stop run array
        @(negedge clk);
        if (mxu_run_array == 1'b0) $display("Pass: Array stream correctly terminated after 256 cycles.");
        else $display("Fail: Array stream overran.");

        //test 7: shadow pipeline (1793 cycle latency)
        test_name = "shadow pipeline";
        //wait 1792 - 256 = 1536 cycles
        repeat(1535) @(negedge clk);
        if (acc_we == 1'b0) $display("Pass: acc_we is low before expected cycle.");
        else $display("Fail: acc_we asserted too early.");
        @(negedge clk); //cycle 1792
        if (acc_we == 1'b1) $display("Pass: acc_we correctly asserted exactly on cycle 1792.");
        else $display("Fail: acc_we did not assert on cycle 1792.");
        //wait for the write pulse
        repeat(256) @(negedge clk);

        //test 8: halt
        test_name = "halt";
        imem_data = 32'hF000_0000;
        @(negedge clk);
        @(negedge clk);
        if (host_interrupt == 1'b1) $display("Pass: host_interrupt asserted.");
        else $display("Fail: host_interrupt not asserted.");

        repeat(5) @(negedge clk);
        $display("All Controller tests completed!");
        $finish;
    end

endmodule

/* verilator coverage_on */