// ============================================================================
// Project: Project 04 - Interrupt-Driven Sensor Control SoC
// Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
// Author: Frank Ouma
// Engineering: FPGA / SoC / Digital Hardware Engineering
// Email: frankotieno254@gmail.com
// Contact: +254725582132
// Copyright (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

`timescale 1ns/1ps

module soc_sensor_control_top #(
    parameter int CLK_FREQ_HZ    = 100_000_000,
    parameter int SAMPLE_RATE_HZ = 10_000,
    parameter int SCLK_FREQ_HZ   = 2_500_000,
    parameter int STARTUP_CYCLES = 50_000_000,
    parameter int PWM_DIVIDER    = 20
) (

    // Shared PS-generated PL clock
    input  logic        s_axi_aclk,
    input  logic        s_axi_aresetn,

    // AXI4-Lite slave interface
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // Physical Pmod AD1
    output logic        ad1_cs_n,
    output logic        ad1_sclk,
    input  logic        ad1_sdata_a,
    input  logic        ad1_sdata_b,

    // Physical actuator output
    output logic        actuator_pwm_out,

    // PL -> PS interrupt
    output logic        irq_out
);

    // ------------------------------------------------------------
    // AXI-controlled configuration
    // ------------------------------------------------------------

    logic        engine_enable;
    logic [11:0] threshold_high;
    logic [11:0] threshold_low;
    logic [7:0]  pwm_duty_cmd;

    // ------------------------------------------------------------
    // Live sensor/control signals
    // ------------------------------------------------------------

    logic [11:0] sample_a;
    logic [11:0] sample_b;
    logic        sample_valid;
    logic        sample_tick;
    logic        busy;
    logic        overrun;

    logic [11:0] filtered_sample;
    logic        filtered_valid;

    logic        control_request;
    logic        actuator_enable;
    logic [1:0]  state_code;

    logic [7:0]  pwm_duty_actual;
    logic        pwm_output;

    logic        datapath_rst;

    // Interrupt event generation
    logic        control_request_d;
    logic        control_event_pulse;

    // Engine disabled = datapath held in reset.
    assign datapath_rst =
        !s_axi_aresetn || !engine_enable;


    // ------------------------------------------------------------
    // Pmod AD1 acquisition
    //
    // 100 MHz PL clock
    // 10 kS/s acquisition
    // 2.5 MHz SPI clock
    // ------------------------------------------------------------

    pmod_ad1_acquisition_engine #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .SAMPLE_RATE_HZ (SAMPLE_RATE_HZ),
        .SCLK_FREQ_HZ   (SCLK_FREQ_HZ)
    ) acquisition_engine (
        .clk          (s_axi_aclk),
        .rst          (datapath_rst),
        .enable       (engine_enable),

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


    // ------------------------------------------------------------
    // Four-sample moving average
    // ------------------------------------------------------------

    adc_moving_average #(
        .DATA_WIDTH (12)
    ) channel_a_filter (
        .clk             (s_axi_aclk),
        .rst             (datapath_rst),

        .sample_in       (sample_a),
        .sample_valid    (sample_valid),

        .filtered_sample (filtered_sample),
        .filtered_valid  (filtered_valid)
    );


    // ------------------------------------------------------------
    // Runtime programmable hysteresis
    // ------------------------------------------------------------

    threshold_hysteresis #(
        .DATA_WIDTH (12)
    ) channel_a_decision (
        .clk             (s_axi_aclk),
        .rst             (datapath_rst),

        .sample_in       (filtered_sample),
        .sample_valid    (filtered_valid),

        .high_threshold  (threshold_high),
        .low_threshold   (threshold_low),

        .control_request (control_request)
    );


    // ------------------------------------------------------------
    // Generate interrupt event on either hysteresis transition.
    //
    // 0 -> 1 : sensor crossed HIGH threshold
    // 1 -> 0 : sensor crossed LOW threshold
    // ------------------------------------------------------------

    always_ff @(posedge s_axi_aclk) begin
        if (datapath_rst)
            control_request_d <= 1'b0;
        else
            control_request_d <= control_request;
    end

    assign control_event_pulse =
        engine_enable &&
        (control_request ^ control_request_d);


    // ------------------------------------------------------------
    // Actuator FSM
    //
    // 500 ms startup at 100 MHz
    // RUN duty comes directly from AXI configuration
    // ------------------------------------------------------------

    actuator_control_fsm #(
        .STARTUP_CYCLES (STARTUP_CYCLES)
    ) actuator_controller (
        .clk             (s_axi_aclk),
        .rst             (datapath_rst),

        .control_request (control_request),
        .run_duty        (pwm_duty_cmd),

        .actuator_enable (actuator_enable),
        .pwm_duty        (pwm_duty_actual),
        .state_code      (state_code)
    );


    // ------------------------------------------------------------
    // PWM
    //
    // 100 MHz / (20 * 256) = 19.53125 kHz
    // ------------------------------------------------------------

    pwm_generator #(
        .PWM_DIVIDER (PWM_DIVIDER)
    ) actuator_pwm (
        .clk     (s_axi_aclk),
        .rst     (datapath_rst),

        .enable  (actuator_enable),
        .duty    (pwm_duty_actual),

        .pwm_out (pwm_output)
    );

    assign actuator_pwm_out = pwm_output;


    // ------------------------------------------------------------
    // AXI4-Lite control/status peripheral + IRQ controller
    // ------------------------------------------------------------

    soc_control_axi_peripheral axi_peripheral (
        .s_axi_aclk          (s_axi_aclk),
        .s_axi_aresetn       (s_axi_aresetn),

        .s_axi_awaddr        (s_axi_awaddr),
        .s_axi_awvalid       (s_axi_awvalid),
        .s_axi_awready       (s_axi_awready),

        .s_axi_wdata         (s_axi_wdata),
        .s_axi_wstrb         (s_axi_wstrb),
        .s_axi_wvalid        (s_axi_wvalid),
        .s_axi_wready        (s_axi_wready),

        .s_axi_bresp         (s_axi_bresp),
        .s_axi_bvalid        (s_axi_bvalid),
        .s_axi_bready        (s_axi_bready),

        .s_axi_araddr        (s_axi_araddr),
        .s_axi_arvalid       (s_axi_arvalid),
        .s_axi_arready       (s_axi_arready),

        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready),

        .engine_enable       (engine_enable),
        .threshold_high      (threshold_high),
        .threshold_low       (threshold_low),
        .pwm_duty            (pwm_duty_cmd),

        .control_request     (control_request),
        .actuator_enable     (actuator_enable),
        .state_code          (state_code),
        .overrun             (overrun),

        .sensor_raw          (sample_a),
        .sensor_filtered     (filtered_sample),

        .event_pulse         (control_event_pulse),
        .irq_out             (irq_out)
    );

endmodule
