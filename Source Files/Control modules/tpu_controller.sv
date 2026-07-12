`timescale 1ns / 10ps

module tpu_controller #(
    parameter IMEM_ADDR_WIDTH = 12,
    parameter UAB_ADDR_WIDTH  = 15,
    parameter ACC_ADDR_WIDTH  = 11
)(
    input  logic clk,
    input  logic n_rst,
    output logic [IMEM_ADDR_WIDTH-1:0] imem_addr,
    input  logic [31:0] imem_data,
    output logic pipeline_en,
    output logic uab_advance_layer,
    output logic [UAB_ADDR_WIDTH-1:0] uab_next_alloc,
    output logic [UAB_ADDR_WIDTH-1:0] uab_rel_raddr,
    output logic uab_re,
    output logic [UAB_ADDR_WIDTH-1:0] uab_rel_waddr,
    output logic uab_we,
    output logic wdb_swap_banks,
    output logic [ACC_ADDR_WIDTH-1:0] acc_raddr,
    output logic acc_re,
    output logic [ACC_ADDR_WIDTH-1:0] acc_waddr,
    output logic acc_we,
    output logic mxu_load_weights,
    output logic mxu_run_array,
    output logic act_apply_relu,
    output logic dma_req_valid,
    output logic [3:0]  dma_req_type,
    output logic [27:0] dma_req_payload,
    input  logic dma_idle,
    output logic host_interrupt
);
    localparam OP_NOP       = 4'h0;
    localparam OP_LD_WT     = 4'h1;
    localparam OP_SYNC      = 4'h2;
    localparam OP_WDB_SWAP  = 4'h3;
    localparam OP_SET_UAB   = 4'h4;
    localparam OP_MATMUL    = 4'h5;
    localparam OP_ACT_SAVE  = 4'h6;
    localparam OP_UAB_ADV   = 4'h7;
    localparam OP_LD_UAB    = 4'h8;
    localparam OP_ST_UAB    = 4'h9;
    localparam OP_LD_BIAS   = 4'hA;
    localparam OP_REPEAT    = 4'hB;
    localparam OP_HALT      = 4'hF;
    
    // Fixed: 256 rows * 6 cycles latency = 1536
    localparam SYSTOLIC_LATENCY = 1536; 
    
    typedef enum logic [2:0] {
        FETCH       = 3'b000,
        DECODE      = 3'b001,
        EXEC_STREAM = 3'b010,
        WAIT_SYNC   = 3'b011,
        HALTED      = 3'b100
    } state_t;

    state_t state, next_state;
    logic [IMEM_ADDR_WIDTH-1:0] pc, next_pc;
    logic [31:0] current_instr;
    logic in_loop;
    logic [7:0] active_loop_count;
    logic [7:0] active_instr_count_reset;
    logic [IMEM_ADDR_WIDTH-1:0] loop_start_pc;
    logic [8:0] stream_counter;
    logic [UAB_ADDR_WIDTH-1:0] stream_uab_addr;
    logic [ACC_ADDR_WIDTH-1:0] stream_acc_addr;
    logic issue_acc_we, issue_uab_we;
    logic [ACC_ADDR_WIDTH-1:0] issue_acc_waddr;
    logic [UAB_ADDR_WIDTH-1:0] issue_uab_waddr;
    logic [10:0] array_in_flight;
    logic array_idle;
    assign array_idle = (array_in_flight == '0);

    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            array_in_flight <= '0;
            state <= FETCH;
            pc <= '0;
            current_instr <= '0;
            in_loop <= 1'b0;
            active_loop_count <= '0;
            active_instr_count_reset <= '0;
            loop_start_pc <= '0;
            stream_counter <= '0;
            stream_uab_addr <= '0;
            stream_acc_addr <= '0;
            host_interrupt <= 1'b0;
        end else begin
            state <= next_state;
            pc <= next_pc;
            
            case ({ mxu_run_array, (acc_we | uab_we) })
                2'b10: array_in_flight <= array_in_flight + 1;
                2'b01: array_in_flight <= array_in_flight - 1;
                default: array_in_flight <= array_in_flight;
            endcase

            if (state == FETCH) current_instr <= imem_data;
            
            if (state == DECODE) begin
                if (current_instr[31:28] == OP_REPEAT) begin
                    in_loop <= 1'b1;
                    active_loop_count <= current_instr[15:8];
                    active_instr_count_reset <= current_instr[7:0];
                    loop_start_pc <= pc;
                end
                if (current_instr[31:28] == OP_MATMUL || current_instr[31:28] == OP_ACT_SAVE) begin
                    stream_counter <= 9'd256;
                    stream_acc_addr <= current_instr[26:16];
                    stream_uab_addr <= current_instr[14:0];
                end
            end
            
            if (state == EXEC_STREAM && stream_counter > 0) begin
                stream_counter <= stream_counter - 1;
                stream_acc_addr <= stream_acc_addr + 1;
                stream_uab_addr <= stream_uab_addr + 1;
            end

            if (next_state == FETCH && state != FETCH && in_loop && (pc == loop_start_pc + active_instr_count_reset)) begin
                if (active_loop_count > 0) active_loop_count <= active_loop_count - 1;
                else in_loop <= 1'b0;
            end

            if (state == HALTED) host_interrupt <= 1'b1;
        end
    end

    assign imem_addr = pc;

    always_comb begin
        next_pc = pc;
        if (next_state == FETCH && state != FETCH) begin
            if (in_loop && (pc == loop_start_pc + active_instr_count_reset)) begin
                if (active_loop_count > 0) next_pc = loop_start_pc; 
                else next_pc = pc + 1;
            end else next_pc = pc + 1; 
        end
    end

    always_comb begin
        next_state = state;
        pipeline_en = 1'b1;
        mxu_run_array = 1'b0;
        mxu_load_weights = 1'b0;
        uab_advance_layer = 1'b0;
        uab_next_alloc = '0;
        uab_re = 1'b0;
        uab_rel_raddr = '0;
        wdb_swap_banks = 1'b0;
        acc_re = 1'b0;
        acc_raddr = '0;
        issue_acc_we = 1'b0;
        issue_acc_waddr = '0;
        issue_uab_we = 1'b0;
        issue_uab_waddr = '0;
        act_apply_relu = 1'b0;
        dma_req_valid = 1'b0;
        dma_req_type = '0;
        dma_req_payload = '0;

        case (state)
            FETCH: next_state = DECODE;
            DECODE: begin
                case (current_instr[31:28])
                    OP_NOP, OP_REPEAT: next_state = FETCH;
                    OP_HALT:           next_state = HALTED;
                    OP_WDB_SWAP: begin wdb_swap_banks = 1'b1; next_state = FETCH; end
                    OP_UAB_ADV: begin uab_advance_layer = 1'b1; uab_next_alloc = current_instr[14:0]; next_state = FETCH; end
                    OP_LD_WT, OP_LD_UAB, OP_ST_UAB, OP_LD_BIAS: begin
                        dma_req_valid = 1'b1; dma_req_type = current_instr[31:28]; dma_req_payload = current_instr[27:0]; next_state = FETCH;
                    end
                    OP_SYNC: next_state = WAIT_SYNC;
                    OP_MATMUL, OP_ACT_SAVE: next_state = EXEC_STREAM;
                    default: next_state = FETCH;
                endcase
            end
            EXEC_STREAM: begin
                if (stream_counter > 0) begin
                    mxu_run_array = 1'b1;
                    if (current_instr[31:28] == OP_MATMUL) begin
                        uab_re = 1'b1; uab_rel_raddr = stream_uab_addr;
                        if (current_instr[27]) begin acc_re = 1'b1; acc_raddr = stream_acc_addr; end
                        issue_acc_we = 1'b1; issue_acc_waddr = stream_acc_addr;
                    end else if (current_instr[31:28] == OP_ACT_SAVE) begin
                        acc_re = 1'b1; acc_raddr = stream_acc_addr; act_apply_relu = current_instr[27];
                        issue_uab_we = 1'b1; issue_uab_waddr = stream_uab_addr;
                    end
                end else next_state = FETCH;
            end
            WAIT_SYNC: begin
                if ((current_instr[0] && !dma_idle) || (current_instr[1] && !array_idle)) next_state = WAIT_SYNC;
                else next_state = FETCH;
            end
            HALTED: next_state = HALTED;
            default: next_state = FETCH;
        endcase
    end

    delayer #(.DATA_WIDTH(1 + ACC_ADDR_WIDTH), .DELAY_CYCLES(SYSTOLIC_LATENCY))
    u_acc_shadow (.clk(clk), .n_rst(n_rst), .en(pipeline_en),
    .d_in({issue_acc_we, issue_acc_waddr}), .d_out(delayed_acc_ctrl));

    delayer #(.DATA_WIDTH(1 + UAB_ADDR_WIDTH), .DELAY_CYCLES(SYSTOLIC_LATENCY))
    u_uab_shadow (.clk(clk), .n_rst(n_rst), .en(pipeline_en),
    .d_in({issue_uab_we, issue_uab_waddr}),.d_out(delayed_uab_ctrl));

    assign acc_we = delayed_acc_ctrl[ACC_ADDR_WIDTH];
    assign acc_waddr = delayed_acc_ctrl[ACC_ADDR_WIDTH-1:0];
    assign uab_we = delayed_uab_ctrl[UAB_ADDR_WIDTH];
    assign uab_rel_waddr = delayed_uab_ctrl[UAB_ADDR_WIDTH-1:0];
endmodule