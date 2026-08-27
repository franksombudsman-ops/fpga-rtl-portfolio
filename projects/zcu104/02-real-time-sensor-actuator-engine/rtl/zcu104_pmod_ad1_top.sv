`timescale 1ns/1ps

module zcu104_pmod_ad1_top (
    input  logic clk_300_p,
    input  logic clk_300_n,
    input  logic pb_reset,

    // Pmod AD1
    output logic ad1_cs_n,
    output logic ad1_sclk,
    input  logic ad1_sdata_a,
    input  logic ad1_sdata_b,

    // ZCU104 status LEDs
    output logic led_clock_locked,
    output logic led_overrun,
    output logic led_sample_a_msb,
    output logic led_sample_b_msb,
    output logic actuator_pwm_out
);

    logic clk_125;
    logic clock_locked;
    logic rst;

    // ---------------------------------------------------------
    // Raw ADC acquisition signals
    // ---------------------------------------------------------

    (* MARK_DEBUG = "TRUE" *) logic [11:0] sample_a;
    (* MARK_DEBUG = "TRUE" *) logic [11:0] sample_b;
    (* MARK_DEBUG = "TRUE" *) logic        sample_valid;

    (* MARK_DEBUG = "TRUE" *) logic        busy;
    (* MARK_DEBUG = "TRUE" *) logic        sample_tick;
    (* MARK_DEBUG = "TRUE" *) logic        overrun;

    // ---------------------------------------------------------
    // Filtered ADC signals
    // ---------------------------------------------------------

    (* MARK_DEBUG = "TRUE" *) logic [11:0] filtered_sample;
    (* MARK_DEBUG = "TRUE" *) logic        filtered_valid;

    // ---------------------------------------------------------
    // Control decision signal
    // ---------------------------------------------------------

    (* MARK_DEBUG = "TRUE" *) logic        control_request;

    // ---------------------------------------------------------
    // Actuator controller signals
    // ---------------------------------------------------------

    (* MARK_DEBUG = "TRUE" *) logic        actuator_enable;
    (* MARK_DEBUG = "TRUE" *) logic [7:0]  pwm_duty;
    (* MARK_DEBUG = "TRUE" *) logic [1:0]  state_code;
    (* MARK_DEBUG = "TRUE" *) logic        pwm_output;

    // ---------------------------------------------------------
    // ZCU104 300 MHz differential clock -> 125 MHz
    // ---------------------------------------------------------

    zcu104_clk_wiz clk_wiz (
        .clk_in1_p (clk_300_p),
        .clk_in1_n (clk_300_n),
        .reset     (1'b0),
        .clk_out1  (clk_125),
        .locked    (clock_locked)
    );

    // ---------------------------------------------------------
    // Reset conditioning
    // ---------------------------------------------------------

    reset_conditioner #(
        .STAGES (2)
    ) reset_ctrl (
        .clk           (clk_125),
        .reset_request (pb_reset),
        .clock_locked  (clock_locked),
        .rst           (rst)
    );

    // ---------------------------------------------------------
    // Real-time Pmod AD1 acquisition subsystem
    // ---------------------------------------------------------

    pmod_ad1_acquisition_engine #(
        .CLK_FREQ_HZ    (125_000_000),
        .SAMPLE_RATE_HZ (10_000),
        .SCLK_FREQ_HZ   (2_500_000)
    ) acquisition_engine (
        .clk          (clk_125),
        .rst          (rst),
        .enable       (1'b1),

        .cs_n         (ad1_cs_n),
        .sclk         (ad1_sclk),
        .sdata_a      (ad1_sdata_a),
        .sdata_b      (ad1_sdata_b),

        .sample_a     (sample_a),
        .sample_b     (sample_b),
        .sample_valid (sample_valid),

        .busy         (busy),
        .sample_tick  (sample_tick),
        .overrun      (overrun)
    );

    // ---------------------------------------------------------
    // Channel A four-sample moving-average filter
    // ---------------------------------------------------------

    adc_moving_average #(
        .DATA_WIDTH (12)
    ) channel_a_filter (
        .clk             (clk_125),
        .rst             (rst),

        .sample_in       (sample_a),
        .sample_valid    (sample_valid),

        .filtered_sample (filtered_sample),
        .filtered_valid  (filtered_valid)
    );

    // ---------------------------------------------------------
    // Channel A threshold + hysteresis decision logic
    // ---------------------------------------------------------

    threshold_hysteresis #(
        .DATA_WIDTH     (12),
        .HIGH_THRESHOLD (12'hC00),
        .LOW_THRESHOLD  (12'hB80)
    ) channel_a_decision (
        .clk             (clk_125),
        .rst             (rst),
        .sample_in       (filtered_sample),
        .sample_valid    (filtered_valid),
        .control_request (control_request)
    );

    // ---------------------------------------------------------
    // Actuator control FSM
    // ---------------------------------------------------------

    actuator_control_fsm #(
        .STARTUP_CYCLES (62_500_000), // 500 ms @ 125 MHz
        .RUN_DUTY       (8'd153)       // ~60%
    ) actuator_controller (
        .clk             (clk_125),
        .rst             (rst),
        .control_request (control_request),

        .actuator_enable (actuator_enable),
        .pwm_duty        (pwm_duty),
        .state_code      (state_code)
    );

    // ---------------------------------------------------------
    // PWM output generator
    // ---------------------------------------------------------

    pwm_generator #(
        .PWM_DIVIDER (25)       // ~19.53 kHz @ 125 MHz
    ) actuator_pwm (
        .clk     (clk_125),
        .rst     (rst),
        .enable  (actuator_enable),
        .duty    (pwm_duty),
        .pwm_out (pwm_output)
    );

    // ---------------------------------------------------------
    // Simple physical status indicators
    // ---------------------------------------------------------

    assign led_clock_locked = clock_locked;
    assign led_overrun      = overrun;

    assign led_sample_a_msb = sample_a[11];
    assign led_sample_b_msb = sample_b[11];
    assign actuator_pwm_out = pwm_output;

endmodule
