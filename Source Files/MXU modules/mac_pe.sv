`timescale 1ns / 10ps

module mac_pe (
    input  logic clk, n_rst,
    input  logic load_weights,
    input  logic run_array,
    input  logic [15:0] x_in,
    input  logic [15:0] weight_in,
    input  logic [31:0] psum_in,
    output logic [15:0] x_out,
    output logic [15:0] weight_out,
    output logic [31:0] sum_out
);
    logic [15:0] locked_weight; //shift registered weights within systolic array
    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            locked_weight <= 16'h0;
        end else if (load_weights) begin
            locked_weight <= weight_in;
        end
    end
    assign weight_out = locked_weight;

    logic [31:0] product;
    logic [31:0] delayed_psum;
    //multiplier taking 3 cycles
    bf16_multiplier mult (
        .clk(clk), .n_rst(n_rst), .en(run_array),
        .bf_1(x_in), .bf_2(locked_weight),
        .overflow(), .underflow(), .nv(),
        .fp_1(product)
    );
    //partial sum delay to line up with multiplier
    delayer #(.DATA_WIDTH(32), .DELAY_CYCLES(3)) psum_delay (
        .clk(clk), .n_rst(n_rst), .en(run_array),
        .d_in(psum_in), .d_out(delayed_psum)
    );
    //adder taking 3 cycles
    fp32_adder add (
        .clk(clk), .n_rst(n_rst), .en(run_array),
        .fp_1(product), .fp_2(delayed_psum),
        .overflow(), .underflow(), .nv(), .fp_out(sum_out)
    );
    //activation delay of 1 cycle
    delayer #(.DATA_WIDTH(16), .DELAY_CYCLES(1)) act_delay (
        .clk(clk), .n_rst(n_rst), .en(run_array),
        .d_in(x_in), .d_out(x_out)
    );
endmodule