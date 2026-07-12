`timescale 1ns / 10ps

module tpu_top #(
    parameter IMEM_ADDR_WIDTH = 12,
    parameter UAB_ADDR_WIDTH  = 15,
    parameter WDB_ADDR_WIDTH  = 11,
    parameter ACC_ADDR_WIDTH  = 11
)(
    input  logic clk,
    input  logic n_rst,
    input  logic [IMEM_ADDR_WIDTH-1:0] host_imem_waddr,
    input  logic [31:0] host_imem_wdata,
    input  logic host_imem_we,
    input  logic [WDB_ADDR_WIDTH-1:0]  dma_wdb_addr,
    input  logic [4095:0] dma_wdb_data,
    input  logic dma_wdb_we,
    output logic host_interrupt,
    output logic dma_req_valid,
    output logic [3:0] dma_req_type,
    output logic [27:0] dma_req_payload,
    input  logic dma_idle
);
    logic [IMEM_ADDR_WIDTH-1:0] ctrl_imem_addr;
    logic [31:0] ctrl_imem_data;
    logic pipeline_en;
    logic mxu_load_weights;
    logic mxu_run_array;
    logic act_apply_relu;
    logic uab_advance_layer;
    logic [UAB_ADDR_WIDTH-1:0] uab_next_alloc;
    logic [UAB_ADDR_WIDTH-1:0] uab_rel_raddr;
    logic uab_re;
    logic [UAB_ADDR_WIDTH-1:0] uab_rel_waddr;
    logic uab_we;
    logic wdb_swap_banks;
    logic [ACC_ADDR_WIDTH-1:0] acc_raddr;
    logic acc_re;
    logic [ACC_ADDR_WIDTH-1:0] acc_waddr;
    logic acc_we;

    sram_bank_wrapper #(.ADDR_WIDTH(IMEM_ADDR_WIDTH), .DATA_WIDTH(32))
    u_imem (.clk(clk), .addr_a(host_imem_waddr), .data_in_a(host_imem_wdata),
    .we_a(host_imem_we), .en_a(host_imem_we), .data_out_a(), .addr_b(ctrl_imem_addr),
    .en_b(1'b1), .data_out_b(ctrl_imem_data));

    tpu_controller #(.IMEM_ADDR_WIDTH(IMEM_ADDR_WIDTH), .UAB_ADDR_WIDTH(UAB_ADDR_WIDTH),
    .ACC_ADDR_WIDTH(ACC_ADDR_WIDTH))
    u_controller (.clk(clk), .n_rst(n_rst), .imem_addr(ctrl_imem_addr),
    .imem_data(ctrl_imem_data), .pipeline_en(pipeline_en),
    .uab_advance_layer(uab_advance_layer), .uab_next_alloc(uab_next_alloc),
    .uab_rel_raddr(uab_rel_raddr), .uab_re(uab_re), .uab_rel_waddr(uab_rel_waddr),
    .uab_we(uab_we), .wdb_swap_banks(wdb_swap_banks), .acc_raddr(acc_raddr),
    .acc_re(acc_re), .acc_waddr(acc_waddr), .acc_we(acc_we),
    .mxu_load_weights(mxu_load_weights), .mxu_run_array(mxu_run_array),
    .act_apply_relu(act_apply_relu), .dma_req_valid(dma_req_valid),
    .dma_req_type(dma_req_type), .dma_req_payload(dma_req_payload),
    .dma_idle(dma_idle), .host_interrupt(host_interrupt));

    tpu_core #(.UAB_ADDR_WIDTH(UAB_ADDR_WIDTH), .WDB_ADDR_WIDTH(WDB_ADDR_WIDTH),
    .ACC_ADDR_WIDTH(ACC_ADDR_WIDTH))
    u_core (.clk(clk), .n_rst(n_rst), .pipeline_en(pipeline_en),
    .uab_advance_layer(uab_advance_layer), .uab_next_alloc(uab_next_alloc),
    .uab_rel_raddr(uab_rel_raddr), .uab_re(uab_re), .uab_rel_waddr(uab_rel_waddr),
    .uab_we(uab_we), .wdb_swap_banks(wdb_swap_banks), .acc_raddr(acc_raddr),
    .acc_re(acc_re), .acc_waddr(acc_waddr), .acc_we(acc_we),
    .mxu_load_weights(mxu_load_weights), .mxu_run_array(mxu_run_array),
    .act_apply_relu(act_apply_relu), .dma_wdb_addr(dma_wdb_addr),
    .dma_wdb_data(dma_wdb_data), .dma_wdb_we(dma_wdb_we), .wdb_mxu_addr('0),
    .wdb_mxu_re(1'b0));

endmodule