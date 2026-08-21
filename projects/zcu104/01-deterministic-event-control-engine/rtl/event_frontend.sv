// ============================================================================
// Deterministic Event & Control Engine
// Event Front-End
//
// Integrates asynchronous input synchronization, debounce qualification,
// rising-edge detection, and qualified-event counting.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

module event_frontend #(
    parameter int unsigned SYNCHRONIZER_STAGES = 2,
    parameter int unsigned CLK_FREQ_HZ         = 125_000_000,
    parameter int unsigned DEBOUNCE_TIME_MS    = 10,
    parameter int unsigned DEBOUNCE_CYCLES =
        (CLK_FREQ_HZ / 1000) * DEBOUNCE_TIME_MS,
    parameter int unsigned EVENT_COUNT_WIDTH   = 16
) (
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         event_async,

    output logic                         event_sync,
    output logic                         event_debounced,
    output logic                         event_pulse,
    output logic [EVENT_COUNT_WIDTH-1:0] event_count
);

    input_synchronizer #(
        .STAGES      (SYNCHRONIZER_STAGES),
        .RESET_VALUE (1'b0)
    ) u_input_synchronizer (
        .clk      (clk),
        .rst      (rst),
        .async_in (event_async),
        .sync_out (event_sync)
    );

    debounce_filter #(
        .CLK_FREQ_HZ      (CLK_FREQ_HZ),
        .DEBOUNCE_TIME_MS (DEBOUNCE_TIME_MS),
        .DEBOUNCE_CYCLES  (DEBOUNCE_CYCLES)
    ) u_debounce_filter (
        .clk           (clk),
        .rst           (rst),
        .sync_in       (event_sync),
        .debounced_out (event_debounced)
    );

    edge_detector u_edge_detector (
        .clk          (clk),
        .rst          (rst),
        .debounced_in (event_debounced),
        .event_pulse  (event_pulse)
    );

    event_counter #(
        .COUNT_WIDTH(EVENT_COUNT_WIDTH)
    ) u_event_counter (
        .clk         (clk),
        .rst         (rst),
        .event_pulse (event_pulse),
        .event_count (event_count)
    );

endmodule