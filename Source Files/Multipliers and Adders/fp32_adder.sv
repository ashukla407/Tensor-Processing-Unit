`timescale 1ns / 10ps

module fp32_adder(
    input logic clk, n_rst, en,
    input logic [31:0] fp_1, fp_2,
    output logic overflow, underflow, nv,
    output logic [31:0] fp_out
);
    //----------------------------------------------
    // PIPELINE STAGE ONE: SETUP AND SIZE COMPARISON
    //----------------------------------------------
    logic s_high_s1, next_s_high_s1, s_low_s1, next_s_low_s1; //signs of larger and smaller input
    logic [7:0] e_high_s1, next_e_high_s1; //larger input exponent
    logic [23:0] m_high_s1, next_m_high_s1, m_low_s1, next_m_low_s1; //mantissas of larger and smaller inputs
    logic [7:0] e_difference, next_e_difference; //serves as the smaller input's exponent in calculation
    logic is_nan_s1, next_is_nan_s1, is_inf_s1, next_is_inf_s1; //error flag checkers
    logic fp_1_larger; //comparison variable for which input is larger

    always_ff @ (posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            s_high_s1 <= 'd0;
            s_low_s1 <= 'd0;
            e_high_s1 <= 'd0;
            m_high_s1 <= 'd0;
            m_low_s1 <= 'd0;
            e_difference <= 'd0;
            is_nan_s1 <= 'd0;
            is_inf_s1 <= 'd0;
        end
        else if (en) begin
            s_high_s1 <= next_s_high_s1;
            s_low_s1 <= next_s_low_s1;
            e_high_s1 <= next_e_high_s1;
            m_high_s1 <= next_m_high_s1;
            m_low_s1 <= next_m_low_s1;
            e_difference <= next_e_difference;
            is_nan_s1 <= next_is_nan_s1;
            is_inf_s1 <= next_is_inf_s1;
        end
    end
    always_comb begin
        next_is_nan_s1 = (fp_1[30:23] == 8'hFF && fp_1[22:0] != 23'd0) | 
                         (fp_2[30:23] == 8'hFF && fp_2[22:0] != 23'd0) |
                         (fp_1[30:23] == 8'hFF && fp_1[22:0] == 23'd0 &&
                          fp_2[30:23] == 8'hFF && fp_2[22:0] == 23'd0 &&
                          fp_1[31] != fp_2[31]); //checks for nan value from multiplier as well as adding infinity to negative infinity
        next_is_inf_s1 = (fp_1[30:23] == 8'hFF && fp_1[22:0] == 23'd0) | (fp_2[30:23] == 8'hFF && fp_2[22:0] == 23'd0); //checks if the input corresponds to a inf value
        fp_1_larger = (fp_1[30:0] >= fp_2[30:0]);
        if(fp_1_larger) begin
            next_s_high_s1 = fp_1[31];
            next_s_low_s1 = fp_2[31];
            next_e_high_s1 = fp_1[30:23];
            next_m_high_s1 = (fp_1[30:23] == 8'd0) ? {1'b0, fp_1[22:0]} : {1'b1, fp_1[22:0]};
            next_m_low_s1 = (fp_2[30:23] == 8'd0) ? {1'b0, fp_2[22:0]} : {1'b1, fp_2[22:0]};
            next_e_difference = fp_1[30:23] - fp_2[30:23];
        end
        else begin
            next_s_high_s1 = fp_2[31];
            next_s_low_s1 = fp_1[31];
            next_e_high_s1 = fp_2[30:23];
            next_m_high_s1 = (fp_2[30:23] == 8'd0) ? {1'b0, fp_2[22:0]} : {1'b1, fp_2[22:0]};
            next_m_low_s1 = (fp_1[30:23] == 8'd0) ? {1'b0, fp_1[22:0]} : {1'b1, fp_1[22:0]};
            next_e_difference = fp_2[30:23] - fp_1[30:23];
        end
    end


    //-------------------------
    // PIPELINE STAGE TWO: MATH
    //-------------------------
    logic s_out_s2, next_s_out_s2;
    logic [7:0] e_high_s2, next_e_high_s2; //larger input exponent
    logic [24:0] mantissa_sum_s2, next_mantissa_sum_s2; //24 mantissa bits + carry bit
    logic [23:0] shifted_m_low_s2;
    logic is_nan_s2, next_is_nan_s2, is_inf_s2, next_is_inf_s2;
    always_ff @ (posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            s_out_s2 <= 'd0;
            e_high_s2 <= 'd0;
            mantissa_sum_s2 <= 'd0;
            is_nan_s2 <= 'd0;
            is_inf_s2 <= 'd0;
        end
        else if (en) begin
            s_out_s2 <= next_s_out_s2;
            e_high_s2 <= next_e_high_s2;
            mantissa_sum_s2 <= next_mantissa_sum_s2;
            is_nan_s2 <= next_is_nan_s2;
            is_inf_s2 <= next_is_inf_s2;
        end
    end
    always_comb begin
        next_s_out_s2 = s_high_s1;
        next_e_high_s2 = e_high_s1;
        next_is_nan_s2 = is_nan_s1;
        next_is_inf_s2 = is_inf_s1;
        //optimized calculation, setting to 24 because if its greater than 24 we're shifting useless 0's
        if(e_difference > 8'd24) begin
            shifted_m_low_s2 = 'd0;
        end
        else begin
            shifted_m_low_s2 = m_low_s1 >> e_difference;
        end
        //mantissa addition
        if(s_high_s1 == s_low_s1) begin
            next_mantissa_sum_s2 = m_high_s1 + shifted_m_low_s2; //adds if same sign
        end
        else begin
            next_mantissa_sum_s2 = m_high_s1 - shifted_m_low_s2; //subtracts if different signs
        end
    end


    //---------------------------------------------------
    // PIPELINE STAGE THREE: NORMALIZATION AND OUTPUT MUX
    //---------------------------------------------------    
    logic [4:0] shift_left; //reshifter from stage 2
    logic [22:0] final_m;
    logic signed [9:0] final_e_calc;
    logic [31:0] next_fp_out;
    logic next_overflow, next_underflow, next_nv;
    always_ff @ (posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            fp_out <= 'd0;
            overflow <= 'd0;
            underflow <= 'd0;
            nv <= 'd0;
        end
        else if (en) begin
            fp_out <= next_fp_out;
            overflow <= next_overflow;
            underflow <= next_underflow;
            nv <= next_nv;
        end
    end
    always_comb begin
        shift_left = 5'd0; //avoid latching
        for (int i = 0; i <= 23; i++) begin
            if (mantissa_sum_s2[i]) begin
                shift_left = 5'd23 - i[4:0];
            end
        end
        if (mantissa_sum_s2 == 25'd0) begin
            final_m = 'd0;
            final_e_calc = 'd0;
        end 
        else if (mantissa_sum_s2[24]) begin
            final_m = mantissa_sum_s2[23:1]; 
            final_e_calc = $signed({2'd0, e_high_s2}) + 10'sd1;
        end 
        else begin
            logic [23:0] shifted_m;
            shifted_m = mantissa_sum_s2[23:0] << shift_left;
            final_m = shifted_m[22:0]; //take off implicit leading 1 used in calculations
            final_e_calc = $signed({2'd0, e_high_s2}) - $signed({5'd0, shift_left});
        end
        //error flag calculations
        next_nv = is_nan_s2; //doesnt trigger invalid wihtout an input being invalid
        next_overflow  = (is_inf_s2 && !next_nv) | (final_e_calc >= 10'sd255); //checking if the exponent is too large
        next_underflow = (final_e_calc <= 10'sd0) && (mantissa_sum_s2 != 25'd0); //checking if exponent and mantissa result in too small a value
        //output mux
        if (next_nv) begin
            next_fp_out = 32'h7FC00000;
        end
        else if (mantissa_sum_s2 == 25'd0 || next_underflow) begin
            next_fp_out = {s_out_s2, 8'd0, 23'd0}; //0 output if mantissa 0 or underflow
        end 
        else if (next_overflow) begin
            next_fp_out = {s_out_s2, 8'hFF, 23'd0}; //infinity output if overflow
        end 
        else begin
            next_fp_out = {s_out_s2, final_e_calc[7:0], final_m};
        end
    end
endmodule