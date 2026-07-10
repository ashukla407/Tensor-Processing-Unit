`timescale 1ns / 10ps

module activation_skew (
    input  logic clk, n_rst, en,
    input  logic [4095:0] flat_activations_in, // 4096 bit vector from uab
    output logic [15:0] skewed_activations_out [0:255] // 256 wires to mxu
);
    generate //shift register logic
        for (genvar i = 0; i < 256; i++) begin : gen_skew
            logic [15:0] row_data_in;
            //extract the row we need to send to the mxu from the giant vector sent from uab
            assign row_data_in = flat_activations_in[(i*16) +: 16];
            //use already written delayer to delay each row by its corresponding delay
            delayer #(.DATA_WIDTH(16), .DELAY_CYCLES(i)) 
            act_delay_inst (.clk(clk), .n_rst(n_rst), .en(en), .d_in(row_data_in),
            .d_out(skewed_activations_out[i]));
        end
    endgenerate
endmodule