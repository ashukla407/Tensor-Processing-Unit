`timescale 1ns / 10ps

module delayer #(
    parameter DATA_WIDTH = 32,
    parameter DELAY_CYCLES = 1
)(
    input  logic clk, n_rst, en,
    input  logic [DATA_WIDTH-1:0] d_in,
    output logic [DATA_WIDTH-1:0] d_out
);
    generate
        if (DELAY_CYCLES == 0) begin
            assign d_out = d_in;
        end
        else begin
            logic [DATA_WIDTH-1:0] shift_reg [1:DELAY_CYCLES];
            always_ff @(posedge clk, negedge n_rst) begin
                if (!n_rst) begin
                    for (int i = 1; i <= DELAY_CYCLES; i++) begin
                        shift_reg[i] <= 'd0;
                    end
                end else if (en) begin // <-- The Hardware Clock Gate
                    shift_reg[1] <= d_in;
                    for (int i = 2; i <= DELAY_CYCLES; i++) begin
                        shift_reg[i] <= shift_reg[i-1];
                    end
                end
            end
            assign d_out = shift_reg[DELAY_CYCLES];
        end
    endgenerate
endmodule