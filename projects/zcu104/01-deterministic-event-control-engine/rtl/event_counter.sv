// ============================================================================
// Deterministic Event & Control Engine
// Event Counter
//
// Records qualified synchronous events using a parameterized modulo counter.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

module event_counter #(
    parameter int unsigned COUNT_WIDTH = 16
) (
    input  logic                   clk,
    input  logic                   rst,
    input  logic                   event_pulse,
    output logic [COUNT_WIDTH-1:0] event_count
);

    always_ff @(posedge clk) begin
        if (rst) begin
            event_count <= '0;
        end
        else if (event_pulse) begin
            event_count <= event_count + 1'b1;
        end
    end

endmodule