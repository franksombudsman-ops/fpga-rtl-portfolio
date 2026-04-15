`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2026 11:01:25 PM
// Design Name: 
// Module Name: debouncer
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


module debouncer #(
    parameter int COUNTER_WIDTH = 20,
    parameter int STABLE_COUNT  = 1_000_000   // 1M ticks = 10 ms at 100 MHz
) (
    input  logic clk,         // 100 MHz system clock
    input  logic rst_n,       // active-low reset
    input  logic button_in,   // raw bouncy button from the physical pin
    output logic button_out   // clean debounced signal
);

    logic [COUNTER_WIDTH-1:0] counter;
    logic                     sync_ff1, sync_ff2;
    logic                     last_sample;

    // 2FF synchronizer - safely bring the async button into our clock domain
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_ff1 <= 1'b0;
            sync_ff2 <= 1'b0;
        end else begin
            sync_ff1 <= button_in;
            sync_ff2 <= sync_ff1;
        end
    end

    // Debounce counter - only accept the button once it's been stable
    // for STABLE_COUNT clock ticks in a row (= 10 ms of quiet)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter     <= '0;
            last_sample <= 1'b0;
            button_out  <= 1'b0;
        end else begin
            last_sample <= sync_ff2;

            if (sync_ff2 != last_sample) begin
                counter <= '0;                  // button changed → restart timer
            end else if (counter < STABLE_COUNT) begin
                counter <= counter + 1'b1;      // still quiet, keep counting
            end else begin
                button_out <= sync_ff2;         // 10 ms of quiet → trust it
            end
        end
    end

endmodule
