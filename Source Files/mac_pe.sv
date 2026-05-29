    `timescale 1ns / 10ps

    module mac_pe(
        input logic clk, n_rst,
        input logic [15:0] x_in, weight,
        input logic [31:0] psum_in,
        output logic [15:0] x_out,
        output logic [31:0] sum_out
    );
        //3 cycle multuiplier instantiation
        logic [31:0] product;
        bf16_multiplier mult(.clk(clk), .n_rst(n_rst), .bf_1(x_in), .bf_2(weight),
                        .overflow(), .underflow(), .nv(),
                        .fp_1(product));
        //delayed input psum to be added after 3 clock cycles
        logic [31:0] delayed_psum;
        delayer #(.DATA_WIDTH(32), .DELAY_CYCLES(3)) psum_delay(.clk(clk), .n_rst(n_rst),
                .d_in(psum_in), .d_out(delayed_psum));
        //adder, takes 3 cycles
        fp32_adder add(.clk(clk), .n_rst(n_rst), .fp_1(product), .fp_2(delayed_psum),
                        .overflow(), .underflow(), .nv(), .fp_out(sum_out));
        //delaying the data by 6 cycles to 
        delayer #(.DATA_WIDTH(16), .DELAY_CYCLES(6)) act_delay(.clk(clk), .n_rst(n_rst),
                .d_in(x_in), .d_out(x_out));

    endmodule