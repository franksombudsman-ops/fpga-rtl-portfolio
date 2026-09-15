`timescale 1ns/1ps

/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 */

module sample_rate_generator #(
    parameter integer CLK_FREQ_HZ    = 125000000,
    parameter integer SAMPLE_RATE_HZ = 10000
) (
    input  wire clk,
    input  wire rst,
    input  wire enable,
    output reg  sample_tick
);

    localparam integer CYCLES_PER_SAMPLE =
        CLK_FREQ_HZ / SAMPLE_RATE_HZ;

    localparam integer COUNTER_WIDTH =
        (CYCLES_PER_SAMPLE <= 1) ?
        1 : $clog2(CYCLES_PER_SAMPLE);

    reg [COUNTER_WIDTH-1:0] cycle_count;

    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0;
            sample_tick <= 1'b0;
        end else begin
            sample_tick <= 1'b0;

            if (!enable) begin
                cycle_count <= 0;
            end else if (cycle_count == CYCLES_PER_SAMPLE - 1) begin
                cycle_count <= 0;
                sample_tick <= 1'b1;
            end else begin
                cycle_count <= cycle_count + 1'b1;
            end
        end
    end

endmodule
