`timescale 1ns/1ps

module sample_rate_generator #(
    parameter int unsigned CLK_FREQ_HZ    = 125_000_000,
    parameter int unsigned SAMPLE_RATE_HZ =      10_000
) (
    input  logic clk,
    input  logic rst,
    input  logic enable,

    output logic sample_tick
);

    localparam int unsigned CYCLES_PER_SAMPLE =
        CLK_FREQ_HZ / SAMPLE_RATE_HZ;

    localparam int unsigned COUNTER_WIDTH =
        (CYCLES_PER_SAMPLE <= 1)
        ? 1
        : $clog2(CYCLES_PER_SAMPLE);

    logic [COUNTER_WIDTH-1:0] cycle_count;

    always_ff @(posedge clk) begin

        if (rst) begin
            cycle_count <= '0;
            sample_tick <= 1'b0;

        end else begin

            // Default behavior:
            // sample_tick only remains HIGH for one FPGA clock.
            sample_tick <= 1'b0;

            if (!enable) begin
                cycle_count <= '0;

            end else if (cycle_count == CYCLES_PER_SAMPLE - 1) begin

                cycle_count <= '0;
                sample_tick <= 1'b1;

            end else begin
                cycle_count <= cycle_count + 1'b1;
            end

        end
    end

endmodule
