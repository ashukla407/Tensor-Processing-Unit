`timescale 1ns / 10ps

module bf16_multiplier(
    input logic [15:0] bf_1, bf_2,
    output logic overflow, underflow, nv, nx,
    output logic [31:0] fp_1
);
    logic s_1, s_2;
    logic [7:0] e_1, e_2;
    logic [22:0] m_1, m_2;
    assign s_1 = bf_1[15];
    assign s_2 = bf_2[15];
    assign e_1 = bf_1[14:7];
    assign e_2 = bf_2[14:7];
    assign m_1 = {bf_1[6:0], 16'd0};
    assign m_2 = {bf_2[6:0], 16'd0};
    
endmodule