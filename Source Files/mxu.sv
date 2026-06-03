`timescale 1ns / 10ps

module mxu (
    input  logic clk, n_rst,
    input  logic load_weights,
    input  logic run_array,
    input  logic [15:0] weight_in_top [0:255],
    input  logic [15:0] act_in_left [0:255],
    input  logic [31:0] psum_in_top [0:255],
    output logic [31:0] psum_out_bottom [0:255]
);
    logic [15:0] act_wire [0:255][0:256];
    logic [15:0] weight_wire [0:256][0:255];
    logic [31:0] psum_wire [0:256][0:255];

    //Assign input values to internal array
    generate
        for (genvar i = 0; i < 256; i++) begin
            assign act_wire[i][0] = act_in_left[i];
            assign weight_wire[0][i] = weight_in_top[i];
            assign psum_wire[0][i] = psum_in_top[i];
            assign psum_out_bottom[i] = psum_wire[256][i];
        end
    endgenerate

    //256x256 grid
    generate
        for (genvar row = 0; row < 256; row++) begin
            for (genvar col = 0; col < 256; col++) begin
                mac_pe u_pe (
                    .clk            (clk),
                    .n_rst          (n_rst),
                    .load_weights   (load_weights),
                    .run_array      (run_array),
                    .x_in           (act_wire[row][col]),
                    .weight_in      (weight_wire[row][col]),
                    .psum_in        (psum_wire[row][col]),
                    .x_out          (act_wire[row][col+1]),
                    .weight_out     (weight_wire[row+1][col]),
                    .sum_out        (psum_wire[row+1][col])
                );
            end
        end
    endgenerate
endmodule