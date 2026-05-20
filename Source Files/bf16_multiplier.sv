`timescale 1ns / 10ps

module bf16_multiplier(
    input logic [15:0] bf_1, bf_2,
    output logic overflow, underflow, nv,
    output logic [31:0] fp_1
);
    //splitting the inputs
    logic s_1, s_2;
    logic [7:0] e_1, e_2;
    logic [6:0] m_1, m_2;
    //final output calculations
    logic s_out;
    logic [15:0] product; //mantissa multiplication
    logic norm_shift; //shifting exponent based on mantissa overflow
    logic [22:0] valid_mantissa;
    logic signed [9:0] e_calc; //exponent calculation
    //error flag calculations
    logic is_inf, is_nan, flush_zero;

    //assigning the split inputs
    assign s_1 = bf_1[15];
    assign s_2 = bf_2[15];
    assign e_1 = bf_1[14:7];
    assign e_2 = bf_2[14:7];
    assign m_1 = bf_1[6:0];
    assign m_2 = bf_2[6:0];

    //sign calculation
    assign s_out = s_1 ^ s_2;

    //product calculation
    assign product = {1'b1, m_1} * {1'b1, m_2};
    assign norm_shift = product[15];
    assign valid_mantissa = norm_shift ? {product[14:0], 8'd0} : {product[13:0], 9'd0};

    //exponent calculation
    assign e_calc = $signed({2'd0, e_1}) + $signed({2'd0, e_2}) - 10'sd127 + $signed({1'b0, norm_shift});

    //error flag calculations
    assign flush_zero = (e_1 == 'd0) | (e_2 == 'd0);
    assign is_inf = (e_1 == 8'hff && m_1 == 7'd0) | (e_2 == 8'hff && m_2 == 7'd0);
    assign is_nan = (e_1 == 8'hff && m_1 != 7'd0) | (e_2 == 8'hff && m_2 != 7'd0);
    //error flag assignments
    assign overflow = is_inf | (e_calc >= 10'sd255);
    assign underflow = flush_zero | (e_calc <= 10'sd0);
    assign nv = is_nan | (is_inf && flush_zero);

    always_comb begin : OutputCalculation
        if(nv) begin
            fp_1 = 32'h7FC00000;
        end
        else if(is_inf) begin
            fp_1 = {s_out, 8'hFF, 23'd0};
        end
        else if(flush_zero) begin
            fp_1 = {s_out, 8'd0, 23'd0};
        end
        else if(overflow) begin
            fp_1 = {s_out, 8'hFF, 23'd0};
        end
        else if(underflow) begin
            fp_1 = {s_out, 8'd0, 23'd0};
        end
        else begin
            fp_1 = {s_out, e_calc[7:0], valid_mantissa};
        end
    end
    
endmodule