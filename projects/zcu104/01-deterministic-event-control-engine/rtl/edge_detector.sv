// ============================================================================
// Deterministic Event & Control Engine
// Rising-Edge Detector
//
// Converts a qualified synchronous LOW-to-HIGH transition into a
// single-system-clock event pulse.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

module edge_detector (
    input  logic clk,
    input  logic rst,
    input  logic debounced_in,
    output logic event_pulse
);

    logic debounced_d;

    always_ff @(posedge clk) begin
        if (rst) begin
            debounced_d <= 1'b0;
        end
        else begin
            debounced_d <= debounced_in;
        end
    end

    assign event_pulse = ~rst & debounced_in & ~debounced_d;

endmodule