// ============================================================================
// Deterministic Event & Control Engine
// ZCU104 Board-Level Top
//
// Integrates the ZCU104 differential board clock, clock-generation IP,
// reset conditioning, physical pushbutton inputs, diagnostic indicators,
// and the complete deterministic event-control engine.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

module zcu104_event_control_top (
    input  logic clk_300_p,
    input  logic clk_300_n,

    input  logic pb_event,
    input  logic pb_reset,

    output logic led_active,
    output logic led_count_lsb,
    output logic led_event_qualified,
    output logic led_clock_locked,
    output logic pmod_led
);

    // ------------------------------------------------------------------------
    // Generated 125 MHz system clock
    // ------------------------------------------------------------------------

    logic clk_125;
    logic clock_locked;
    logic sys_rst;

    // ------------------------------------------------------------------------
    // Internal engine signals
    //
    // MARK_DEBUG preserves these important signals for later ILA observation.
    // ------------------------------------------------------------------------

    (* MARK_DEBUG = "TRUE" *)
    logic event_sync;

    (* MARK_DEBUG = "TRUE" *)
    logic event_debounced;

    (* MARK_DEBUG = "TRUE" *)
    logic event_pulse;

    (* MARK_DEBUG = "TRUE" *)
    logic [15:0] event_count;

    (* MARK_DEBUG = "TRUE" *)
    logic output_active;


    // ------------------------------------------------------------------------
    // ZCU104 Clocking Wizard
    //
    // Physical input:
    //     300 MHz differential clock
    //
    // Generated clock:
    //     125 MHz
    //
    // The Clocking Wizard itself is not reset by the application pushbutton.
    // It remains operational while the application logic is reset.
    // ------------------------------------------------------------------------

    zcu104_clk_wiz u_zcu104_clk_wiz (
        .clk_in1_p (clk_300_p),
        .clk_in1_n (clk_300_n),
        .reset     (1'b0),
        .clk_out1  (clk_125),
        .locked    (clock_locked)
    );


    // ------------------------------------------------------------------------
    // Reset conditioning
    //
    // Reset asserts immediately when:
    //     - PB reset is pressed, or
    //     - the generated clock loses lock.
    //
    // Reset release is synchronized to clk_125.
    // ------------------------------------------------------------------------

    reset_conditioner #(
        .STAGES (2)
    ) u_reset_conditioner (
        .clk           (clk_125),
        .reset_request (pb_reset),
        .clock_locked  (clock_locked),
        .rst           (sys_rst)
    );


    // ------------------------------------------------------------------------
    // Complete Event Control Engine
    // ------------------------------------------------------------------------

    event_control_top #(
        .SYNCHRONIZER_STAGES   (2),
        .CLK_FREQ_HZ           (125_000_000),
        .DEBOUNCE_TIME_MS      (10),
        .EVENT_COUNT_WIDTH     (16),
        .OUTPUT_ACTIVE_TIME_MS (500)
    ) u_event_control_engine (
        .clk             (clk_125),
        .rst             (sys_rst),
        .event_async     (pb_event),

        .event_sync      (event_sync),
        .event_debounced (event_debounced),
        .event_pulse     (event_pulse),
        .event_count     (event_count),
        .output_active   (output_active)
    );


    // ------------------------------------------------------------------------
    // Physical board diagnostics
    // ------------------------------------------------------------------------

    assign led_active          = output_active;
    assign led_count_lsb       = event_count[0];
    assign led_event_qualified = event_debounced;
    assign led_clock_locked    = clock_locked;
    assign pmod_led = output_active;

endmodule