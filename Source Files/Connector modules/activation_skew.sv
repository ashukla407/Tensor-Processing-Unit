`timescale 1ns / 10ps

module activation_skew (
    input  logic clk, n_rst, en,
    input  logic [4095:0] flat_activations_in, 
    output logic [15:0]   skewed_activations_out [0:255]
);
    generate
        for (genvar i = 0; i < 256; i++) begin : gen_skew
            logic [15:0] row_data_in;
            assign row_data_in = flat_activations_in[(i*16) +: 16];
            //skew matches the 6 cycle pipeline
            delayer #(.DATA_WIDTH(16), .DELAY_CYCLES(6 * i)) 
            act_delay_inst (.clk(clk), .n_rst(n_rst), .en(en), .d_in(row_data_in),
            .d_out(skewed_activations_out[i]));
        end
    endgenerate
endmodule