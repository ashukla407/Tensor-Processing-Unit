`timescale 1ns / 10ps

module tpu_core #(
    parameter UAB_ADDR_WIDTH = 15,
    parameter WDB_ADDR_WIDTH = 11,
    parameter ACC_ADDR_WIDTH = 11
)(
    input logic clk,
    input logic n_rst,
    input logic pipeline_en, //global pipeline enable
    input logic uab_advance_layer,
    input logic [UAB_ADDR_WIDTH-1:0] uab_next_alloc,
    input logic [UAB_ADDR_WIDTH-1:0] uab_rel_raddr,
    input logic uab_re,
    input logic [UAB_ADDR_WIDTH-1:0] uab_rel_waddr,
    input logic uab_we,
    input logic wdb_swap_banks,
    input logic [WDB_ADDR_WIDTH-1:0] dma_wdb_addr,
    input logic [4095:0] dma_wdb_data,
    input logic dma_wdb_we,
    input logic [WDB_ADDR_WIDTH-1:0] wdb_mxu_addr,
    input logic wdb_mxu_re,
    input logic [ACC_ADDR_WIDTH-1:0] acc_raddr,
    input logic acc_re,
    input logic [ACC_ADDR_WIDTH-1:0] acc_waddr,
    input logic acc_we,
    input logic mxu_load_weights,
    input logic mxu_run_array,
    input logic act_apply_relu
);
    logic [4095:0] flat_uab_rdata;
    logic [4095:0] flat_uab_wdata;    
    logic [4095:0] flat_wdb_rdata;
    logic [8191:0] flat_acc_rdata;
    logic [8191:0] flat_deskewed_results;
    logic [15:0] skewed_act_in [0:255];
    logic [15:0] unpacked_weights [0:255];
    logic [31:0] unpacked_psum_in [0:255];
    logic [31:0] mxu_psum_out [0:255];
    
    //weight wires between modules
    generate
        for (genvar i = 0; i < 256; i++) begin : gen_unpack
            assign unpacked_weights[i] = flat_wdb_rdata[(i*16) +: 16];
            assign unpacked_psum_in[i] = flat_acc_rdata[(i*32) +: 32];
        end
    endgenerate

    //uab instantiation
    uab_memory_space #(.ADDR_WIDTH(UAB_ADDR_WIDTH), .DATA_WIDTH(4096))
    u_uab (.clk(clk), .n_rst(n_rst), .advance_layer(uab_advance_layer),
    .next_write_allocation(uab_next_alloc), .relative_read_addr(uab_rel_raddr),
    .mxu_re(uab_re), .mxu_rdata(flat_uab_rdata), .relative_write_addr(uab_rel_waddr),
    .mxu_we(uab_we), .mxu_wdata(flat_uab_wdata));

    //activation skew control instantiation
    activation_skew u_skew (.clk(clk), .n_rst(n_rst), .en(pipeline_en),
    .flat_activations_in(flat_uab_rdata), .skewed_activations_out(skewed_act_in));
    
    //weight double buffer instantiation
    weight_double_buffer #(.ADDR_WIDTH(WDB_ADDR_WIDTH), .DATA_WIDTH(4096))
    u_wdb (.clk(clk), .n_rst(n_rst), .dma_addr(dma_wdb_addr), .dma_data(dma_wdb_data),
    .dma_we(dma_wdb_we), .mxu_addr(wdb_mxu_addr), .mxu_re(wdb_mxu_re),
    .mxu_data(flat_wdb_rdata),
    .swap_banks(wdb_swap_banks));

    //sram wrapper instantiation
    sram_bank_wrapper #(.ADDR_WIDTH(ACC_ADDR_WIDTH), .DATA_WIDTH(8192))
    u_acc_sram (.clk(clk), .addr_a(acc_waddr), .data_in_a(flat_deskewed_results),
    .we_a(acc_we), .en_a(acc_we), .data_out_a(), .addr_b(acc_raddr), .en_b(acc_re),
    .data_out_b(flat_acc_rdata));

    //mxu instantiation
    mxu u_mxu (.clk(clk), .n_rst(n_rst), .load_weights(mxu_load_weights),
    .run_array(mxu_run_array), .weight_in_top(unpacked_weights), .act_in_left(skewed_act_in),
    .psum_in_top(unpacked_psum_in), .psum_out_bottom(mxu_psum_out));

    //deskew result instantiation
    result_deskew u_deskew (.clk(clk), .n_rst(n_rst), .en(pipeline_en),
    .skewed_results_in(mxu_psum_out), .flat_results_out(flat_deskewed_results));

    //activation unit instantiation
    activation_unit u_act_unit (.clk(clk), .n_rst(n_rst), .en(pipeline_en),
    .apply_relu(act_apply_relu), .flat_fp32_in(flat_deskewed_results),
    .flat_bf16_out(flat_uab_wdata));

endmodule