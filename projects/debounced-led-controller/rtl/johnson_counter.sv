`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2026 06:07:46 AM
// Design Name: 
// Module Name: johnson_counter
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module johnson_counter #(
    parameter int WIDTH = 4
) (
    input  logic             clk,      // system clock
    input  logic             rst_n,    // active-low reset
    input  logic             advance,  // one-cycle pulse: step the counter
    output logic [WIDTH-1:0] q         // current state → drives LEDs
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            q <= '0;                       // reset to all zeros
        end else if (advance) begin
            q <= {~q[0], q[WIDTH-1:1]};    // shift right, invert-feedback
        end
        // else: hold current value
    end

endmodule