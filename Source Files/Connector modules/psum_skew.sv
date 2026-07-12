`timescale 1ns / 10ps

module psum_skew (
    input  logic clk, n_rst, en,
    input  logic [31:0] flat_psum_in [0:255], 
    output logic [31:0] skewed_psum_out [0:255] 
);
    generate 
        for (genvar i = 0; i < 256; i++) begin : gen_psum_skew
            delayer #(.DATA_WIDTH(32), .DELAY_CYCLES(i)) 
            psum_delay_inst (.clk(clk), .n_rst(n_rst), .en(en), .d_in(flat_psum_in[i]),
            .d_out(skewed_psum_out[i]));
        end
    endgenerate
endmodule