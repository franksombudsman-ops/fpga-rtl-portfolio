// ============================================================================
// Deterministic Event & Control Engine
// Functional Top-Level
//
// Integrates asynchronous event qualification, event counting, and
// deterministic non-retriggerable output control.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

module event_control_top #(
    parameter int unsigned SYNCHRONIZER_STAGES   = 2,
    parameter int unsigned CLK_FREQ_HZ           = 125_000_000,
    parameter int unsigned DEBOUNCE_TIME_MS      = 10,
    parameter int unsigned DEBOUNCE_CYCLES =
        (CLK_FREQ_HZ / 1000) * DEBOUNCE_TIME_MS,
    parameter int unsigned EVENT_COUNT_WIDTH     = 16,
    parameter int unsigned OUTPUT_ACTIVE_TIME_MS = 500,
    parameter int unsigned OUTPUT_ACTIVE_CYCLES =
        (CLK_FREQ_HZ / 1000) * OUTPUT_ACTIVE_TIME_MS
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         event_async,

    output logic                         event_sync,
    output logic                         event_debounced,
    output logic                         event_pulse,
    output logic [EVENT_COUNT_WIDTH-1:0] event_count,
    output logic                         output_active
);

    event_frontend #(
        .SYNCHRONIZER_STAGES (SYNCHRONIZER_STAGES),
        .CLK_FREQ_HZ         (CLK_FREQ_HZ),
        .DEBOUNCE_TIME_MS    (DEBOUNCE_TIME_MS),
        .DEBOUNCE_CYCLES     (DEBOUNCE_CYCLES),
        .EVENT_COUNT_WIDTH   (EVENT_COUNT_WIDTH)
    ) u_event_frontend (
        .clk             (clk),
        .rst             (rst),
        .event_async     (event_async),
        .event_sync      (event_sync),
        .event_debounced (event_debounced),
        .event_pulse     (event_pulse),
        .event_count     (event_count)
    );

    output_controller #(
        .CLK_FREQ_HZ           (CLK_FREQ_HZ),
        .OUTPUT_ACTIVE_TIME_MS (OUTPUT_ACTIVE_TIME_MS),
        .OUTPUT_ACTIVE_CYCLES  (OUTPUT_ACTIVE_CYCLES)
    ) u_output_controller (
        .clk           (clk),
        .rst           (rst),
        .event_pulse   (event_pulse),
        .output_active (output_active)
    );

endmodule