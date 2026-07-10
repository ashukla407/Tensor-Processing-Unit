`timescale 1ns / 10ps

module result_deskew (
    input  logic clk, n_rst, en,
    input  logic [31:0] skewed_results_in [0:255], //256 vectors from mxu calculations
    output logic [8191:0] flat_results_out //8192 bit array
);
    generate //flatten waterfall logic into one huge array
        for (genvar i = 0; i < 256; i++) begin : gen_deskew
            logic [31:0] delayed_result;
            //reverse delay logic to send all vectors at the same time
            delayer #(.DATA_WIDTH(32), .DELAY_CYCLES(255 - i))
            res_delay_inst (.clk(clk), .n_rst(n_rst), .en(en), .d_in(skewed_results_in[i]),
            .d_out(delayed_result));
            //put the aligned vector into a huge bus to give to the output
            assign flat_results_out[(i*32) +: 32] = delayed_result;
        end
    endgenerate
endmodule