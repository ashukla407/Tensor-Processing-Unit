`timescale 1ns / 10ps

module uab_memory #(
    parameter ADDR_WIDTH = 15,  // 32,768 words = 16mb
    parameter DATA_WIDTH = 4096 //16 bits for 256 activations
)(
    input  logic clk,
    input  logic n_rst,
    //TPU control
    input  logic advance_layer,
    input  logic [ADDR_WIDTH-1:0] next_write_allocation,
    //activations sent into mxu
    input  logic [ADDR_WIDTH-1:0] relative_read_addr,
    input  logic mxu_re,
    output logic [DATA_WIDTH-1:0] mxu_rdata,
    //data coming out of the mxu
    input  logic [ADDR_WIDTH-1:0] relative_write_addr,
    input  logic mxu_we,
    input  logic [DATA_WIDTH-1:0] mxu_wdata
);
    logic [ADDR_WIDTH-1:0] read_base_ptr;
    logic [ADDR_WIDTH-1:0] write_base_ptr;
    //pointer management state machine
    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            read_base_ptr <= '0;
            write_base_ptr <= '0;
        end else if (advance_layer) begin
            read_base_ptr <= write_base_ptr;
            write_base_ptr <= write_base_ptr + next_write_allocation;
        end
    end

    logic [ADDR_WIDTH-1:0] absolute_read_addr;
    logic [ADDR_WIDTH-1:0] absolute_write_addr;
    always_comb begin
        absolute_read_addr = read_base_ptr + relative_read_addr;
        absolute_write_addr = write_base_ptr + relative_write_addr;
    end

    //port a read/write
    //port b read only
    sram_bank_wrapper #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_uab_sram (
        .clk(clk),
        .addr_a (absolute_write_addr),
        .data_in_a (mxu_wdata),
        .we_a (mxu_we),
        .en_a (mxu_we),
        .data_out_a (),
        .addr_b (absolute_read_addr),
        .en_b (mxu_re),
        .data_out_b (mxu_rdata)
    );
endmodule