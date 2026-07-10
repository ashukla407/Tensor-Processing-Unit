`timescale 1ns / 10ps

module activation_unit (
    input  logic clk,
    input  logic n_rst,
    input  logic en,
    input  logic apply_relu, 
    input  logic [8191:0] flat_fp32_in,  
    output logic [4095:0] flat_bf16_out  
);
    generate
        for (genvar i = 0; i < 256; i++) begin : gen_quantize
            logic [31:0] fp32_val;
            logic [15:0] bf16_val;
            assign fp32_val = flat_fp32_in[(i * 32) +: 32];
            always_ff @(posedge clk, negedge n_rst) begin
                if (!n_rst) begin
                    bf16_val <= 16'd0;
                end else if (en) begin
                    if (apply_relu && fp32_val[31] == 1'b1) begin
                        bf16_val <= 16'd0;
                    end else begin
                        bf16_val <= fp32_val[31:16];
                    end
                end
            end
            assign flat_bf16_out[(i * 16) +: 16] = bf16_val;
        end
    endgenerate
endmodule