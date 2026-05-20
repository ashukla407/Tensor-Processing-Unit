`timescale 1ns / 10ps

module bf16_multiplier(
    input logic clk, n_rst,
    input logic [15:0] bf_1, bf_2,
    output logic overflow, underflow, nv,
    output logic [31:0] fp_1
);
    //-------------------------
    //PIPELINE STAGE ONE: SETUP
    //-------------------------
    //sign, exponent, and mantissa registers
    logic s_out_s1, next_s_out_s1; //calculated signs
    logic [7:0] e_1_s1, e_2_s1; //registered input exponents
    logic [6:0] m_1_s1, m_2_s1; //registered input mantissas

    always_ff @ (posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            s_out_s1 <= 'd0;
            e_1_s1 <= 'd0;
            e_2_s1 <= 'd0;
            m_1_s1 <= 'd0;
            m_2_s1 <= 'd0;
        end
        else begin
            s_out_s1 <= next_s_out_s1;
            e_1_s1 <= bf_1[14:7];
            e_2_s1 <= bf_2[14:7];
            m_1_s1 <= bf_1[6:0];
            m_2_s1 <= bf_2[6:0];
        end
    end
    always_comb begin
        next_s_out_s1 = bf_1[15] ^ bf_2[15];
    end


    //-------------------------
    //PIPELINE STAGE TWO: MATH
    //-------------------------
    //final output calculations
    logic s_out_s2; //registered sign
    logic [15:0] product_s2, next_product_s2; //product calculation (not 22 bits yet to save space in this pipeline stage)
    logic signed [9:0] initial_e_calc_s2, next_initial_e_calc_s2; //exponent calculation without norm shift
    logic is_inf_s2, next_is_inf_s2, is_nan_s2, next_is_nan_s2, flush_zero_s2, next_flush_zero_s2; //error flags to calculate

    always_ff @ (posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            s_out_s2 <= 'd0;
            product_s2 <= 'd0;
            initial_e_calc_s2 <= 'd0;
            is_inf_s2 <= 'd0;
            is_nan_s2 <= 'd0;
            flush_zero_s2 <= 'd0;
        end
        else begin
            s_out_s2 <= s_out_s1;
            product_s2 <= next_product_s2;
            initial_e_calc_s2 <= next_initial_e_calc_s2;
            is_inf_s2 <= next_is_inf_s2;
            is_nan_s2 <= next_is_nan_s2;
            flush_zero_s2 <= next_flush_zero_s2;
        end
    end
    always_comb begin
        next_product_s2 = {1'b1, m_1_s1} * {1'b1, m_2_s1};
        next_initial_e_calc_s2 = $signed({2'd0, e_1_s1}) + $signed({2'd0, e_2_s1}) - 10'sd127;
        next_flush_zero_s2 = (e_1_s1 == 'd0) | (e_2_s1 == 'd0);
        next_is_inf_s2 = (e_1_s1 == 8'hff && m_1_s1 == 7'd0) | (e_2_s1 == 8'hff && m_2_s1 == 7'd0);
        next_is_nan_s2 = (e_1_s1 == 8'hff && m_1_s1 != 7'd0) | (e_2_s1 == 8'hff && m_2_s1 != 7'd0);
    end

    
    //---------------------------------------------------
    //PIPELINE STAGE THREE: NORMILIZATION AND OUTPUTS MUX
    //---------------------------------------------------
    logic [22:0] valid_mantissa_s3; //final valid fp32 mantissa value
    logic norm_shift_s3; //shifting exponent based on mantissa overflow
    logic signed [9:0] final_e_calc_s3; //calculating final exponent with norm_shift in account
    logic [31:0] next_fp_1_s3;
    logic next_overflow, next_underflow, next_nv;

    always_ff @ (posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            fp_1 <= 'd0;
            overflow <= 'd0;
            underflow <= 'd0;
            nv <= 'd0;
        end
        else begin
            fp_1 <= next_fp_1_s3;
            overflow <= next_overflow;
            underflow <= next_underflow;
            nv <= next_nv;
        end
    end

    always_comb begin
        norm_shift_s3 = product_s2[15];
        valid_mantissa_s3 = norm_shift_s3 ? {product_s2[14:0], 8'd0} : {product_s2[13:0], 9'd0};
        final_e_calc_s3 = initial_e_calc_s2 + $signed({1'b0, norm_shift_s3});
        next_overflow = is_inf_s2 | (final_e_calc_s3 >= 10'sd255);
        next_underflow = flush_zero_s2 | (final_e_calc_s3 <= 10'sd0);
        next_nv = is_nan_s2 | (is_inf_s2 && flush_zero_s2);
        //output calculation
        if(next_nv) begin
            next_fp_1_s3 = 32'h7FC00000;
        end
        else if(is_inf_s2) begin
            next_fp_1_s3 = {s_out_s2, 8'hFF, 23'd0};
        end
        else if(flush_zero_s2) begin
            next_fp_1_s3 = {s_out_s2, 8'd0, 23'd0};
        end
        else if(next_overflow) begin
            next_fp_1_s3 = {s_out_s2, 8'hFF, 23'd0};
        end
        else if(next_underflow) begin
            next_fp_1_s3 = {s_out_s2, 8'd0, 23'd0};
        end
        else begin
            next_fp_1_s3 = {s_out_s2, final_e_calc_s3[7:0], valid_mantissa_s3};
        end
    end

    //------------------------
    //OLD, NON-PIPELINED ADDER
    //------------------------
    /*
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
    */
    
endmodule