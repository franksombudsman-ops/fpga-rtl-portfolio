// ============================================================================
// Deterministic Event & Control Engine
// Debounce Filter
//
// Qualifies synchronized input transitions by requiring continuous stability
// for a defined number of system-clock cycles.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

module debounce_filter #(
    parameter int unsigned CLK_FREQ_HZ      = 125_000_000,
    parameter int unsigned DEBOUNCE_TIME_MS = 10,

    parameter int unsigned DEBOUNCE_CYCLES =
        (CLK_FREQ_HZ / 1000) * DEBOUNCE_TIME_MS
) (
    input  logic clk,
    input  logic rst,
    input  logic sync_in,
    output logic debounced_out
);

    localparam int unsigned COUNTER_WIDTH =
        (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);

    logic [COUNTER_WIDTH-1:0] debounce_counter;

    always_ff @(posedge clk) begin
        if (rst) begin
            debounced_out   <= 1'b0;
            debounce_counter <= '0;
        end
        else if (sync_in == debounced_out) begin
            // Input agrees with the currently accepted state.
            // Any incomplete qualification period is cancelled.
            debounce_counter <= '0;
        end
        else if (DEBOUNCE_CYCLES <= 1) begin
            // Supports intentionally reduced timing configurations.
            debounced_out    <= sync_in;
            debounce_counter <= '0;
        end
        else if (debounce_counter == DEBOUNCE_CYCLES - 1) begin
            // The candidate state has remained continuously stable
            // for the complete qualification interval.
            debounced_out    <= sync_in;
            debounce_counter <= '0;
        end
        else begin
            debounce_counter <= debounce_counter + 1'b1;
        end
    end

endmodule