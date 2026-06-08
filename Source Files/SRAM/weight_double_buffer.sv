`timescale 1ns / 10ps

module weight_double_buffer #(
    parameter ADDR_WIDTH = 11, //2048 words = 8mb across 2 banks
    parameter DATA_WIDTH = 4096 //16 bits for 256 weights
)(
    input  logic clk,
    input  logic n_rst,
    //host streams weights from off chip DRAM, write only
    input  logic [ADDR_WIDTH-1:0] dma_addr,
    input  logic [DATA_WIDTH-1:0] dma_data,
    input  logic dma_we,
    //request weights going into the mxu, read only
    input  logic [ADDR_WIDTH-1:0] mxu_addr,
    input  logic mxu_re,
    output logic [DATA_WIDTH-1:0] mxu_data,
    //tpu sends signal when a layer is complete
    input  logic swap_banks
);
    //State machine checking ping pong logic of WDB, 0 means bank 0 R bank 1 W and vice versa
    logic active_read_bank;
    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            active_read_bank <= 1'b0;
        end 
        else if (swap_banks) begin
            active_read_bank <= ~active_read_bank;
        end
    end

    //bank 0 internal logic
    logic [ADDR_WIDTH-1:0] b0_addr_a, b0_addr_b;
    logic [DATA_WIDTH-1:0] b0_data_in_a, b0_data_out_b;
    logic b0_we_a, b0_en_a, b0_en_b;
    //bank 1 internal logic
    logic [ADDR_WIDTH-1:0] b1_addr_a, b1_addr_b;
    logic [DATA_WIDTH-1:0] b1_data_in_a, b1_data_out_b;
    logic b1_we_a, b1_en_a, b1_en_b;
    always_comb begin
        if (active_read_bank == 1'b0) begin
            //bank 0 R bank 1 W
            b0_addr_b    = mxu_addr;
            b0_en_b      = mxu_re;
            b0_addr_a    = '0;
            b0_we_a      = 1'b0;
            b0_en_a      = 1'b0;
            b0_data_in_a = '0;
            b1_addr_a    = dma_addr;
            b1_we_a      = dma_we;
            b1_en_a      = dma_we; 
            b1_data_in_a = dma_data;
            b1_addr_b    = '0;
            b1_en_b      = 1'b0;
            
            mxu_data = b0_data_out_b;
        end 
        else begin
            //bank 0 W bank 1 R
            b1_addr_b    = mxu_addr;
            b1_en_b      = mxu_re;
            b1_addr_a    = '0;
            b1_we_a      = 1'b0;
            b1_en_a      = 1'b0;
            b1_data_in_a = '0;
            b0_addr_a    = dma_addr;
            b0_we_a      = dma_we;
            b0_en_a      = dma_we;
            b0_data_in_a = dma_data;
            b0_addr_b    = '0;
            b0_en_b      = 1'b0;
            
            mxu_data = b1_data_out_b;
        end
    end
    //instantiate sram wrapper
    sram_bank_wrapper #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)) 
    bank_0 (.clk(clk), .addr_a(b0_addr_a), .data_in_a(b0_data_in_a), .we_a(b0_we_a),
            .en_a(b0_en_a), .data_out_a(), .addr_b(b0_addr_b), .en_b(b0_en_b),
            .data_out_b(b0_data_out_b));
    sram_bank_wrapper #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH))
    bank_1 (.clk(clk), .addr_a(b1_addr_a), .data_in_a(b1_data_in_a), .we_a(b1_we_a),
            .en_a(b1_en_a), .data_out_a(), .addr_b(b1_addr_b), .en_b(b1_en_b),
            .data_out_b(b1_data_out_b));
endmodule