`timescale 1ns / 10ps

module mxu_256x256 (
    input  logic clk, n_rst,
    input  logic load_weights, //High to stream weights into the grid
    input  logic run_array, //High to step the execution pipelines
    input  logic [15:0] weight_in_top [0:255], // 1D stream from memory controller
    input  logic [15:0] act_in_left [0:255], // 1D stream from activation FIFO/SRAM
    input  logic [31:0] psum_in_top [0:255], // Initial psums entering top edge
    output logic [31:0] psum_out_bottom [0:255]  // Final computed matrix out the bottom
);

    //=========================================
    // INTERNAL 2D ROUTING FABRIC
    //=========================================
    // Index 0 is the incoming boundary data. Indices 1-255 are PE-to-PE connections.
    // Index 256 captures the boundary outputs leaving the edges.
    logic [15:0] act_wire    [0:255][0:256]; // Horizontal data wires [Row][Col]
    logic [15:0] weight_wire [0:256][0:255]; // Vertical weight wires [Row][Col]
    logic [31:0] psum_wire   [0:256][0:255]; // Vertical partial sum wires [Row][Col]

    //=========================================
    // BOUNDARY IO CONNECTIONS
    //=========================================
    generate
        for (genvar i = 0; i < 256; i++) begin : gen_boundaries
            // Left boundary activation injection
            assign act_wire[i][0]      = act_in_left[i];
            
            // Top boundary weight and partial sum injection
            assign weight_wire[0][i]   = weight_in_top[i];
            assign psum_wire[0][i]     = psum_in_top[i];
            
            // Bottom boundary data capture
            assign psum_out_bottom[i]  = psum_wire[256][i];
        end
    endgenerate

    //=========================================
    // STRUCTURAL GRID INTERCONNECT (65,536 PEs)
    //=========================================
    generate
        for (genvar row = 0; row < 256; row++) begin : gen_row
            for (genvar col = 0; col < 256; col++) begin : gen_col
                
                mac_pe u_pe (
                    .clk            (clk),
                    .n_rst          (n_rst),
                    .load_weights   (load_weights),
                    .run_array      (run_array),
                    
                    // Input ports grab data from current matrix coordinates
                    .x_in           (act_wire[row][col]),
                    .weight_in      (weight_wire[row][col]),
                    .psum_in        (psum_wire[row][col]),
                    
                    // Output ports push data downstream (Right and Down)
                    .x_out          (act_wire[row][col+1]),    // Flows Right
                    .weight_out     (weight_wire[row+1][col]),   // Flows Down
                    .sum_out        (psum_wire[row+1][col])    // Flows Down
                );
                
            end
        end
    endgenerate

endmodule