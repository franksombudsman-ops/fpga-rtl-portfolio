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

module pmod_ad1_acquisition_engine #(
    parameter int unsigned CLK_FREQ_HZ    = 125_000_000,
    parameter int unsigned SAMPLE_RATE_HZ =      10_000,
    parameter int unsigned SCLK_FREQ_HZ   =   2_500_000
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        enable,

    // Pmod AD1 physical interface
    output logic        cs_n,
    output logic        sclk,
    input  logic        sdata_a,
    input  logic        sdata_b,

    // Acquired samples
    output logic [11:0] sample_a,
    output logic [11:0] sample_b,
    output logic        sample_valid,

    // Status / debug
    output logic        busy,
    output logic        sample_tick,
    output logic        overrun
);

    logic spi_start;

    // ---------------------------------------------------------
    // Deterministic sample-rate generator
    // ---------------------------------------------------------

    sample_rate_generator #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .SAMPLE_RATE_HZ (SAMPLE_RATE_HZ)
    ) sample_timer (
        .clk         (clk),
        .rst         (rst),
        .enable      (enable),
        .sample_tick (sample_tick)
    );


    // Start a transaction only if the SPI engine is available.
    assign spi_start = sample_tick && !busy;


    // ---------------------------------------------------------
    // SPI ADC transaction engine
    // ---------------------------------------------------------

    pmod_ad1_spi_master #(
        .CLK_FREQ_HZ  (CLK_FREQ_HZ),
        .SCLK_FREQ_HZ (SCLK_FREQ_HZ)
    ) spi_master (
        .clk          (clk),
        .rst          (rst),

        .start        (spi_start),
        .busy         (busy),
        .sample_valid (sample_valid),

        .cs_n         (cs_n),
        .sclk         (sclk),
        .sdata_a      (sdata_a),
        .sdata_b      (sdata_b),

        .sample_a     (sample_a),
        .sample_b     (sample_b)
    );


    // ---------------------------------------------------------
    // Sticky overrun detector
    //
    // Once an overrun occurs, keep the flag HIGH until reset.
    // ---------------------------------------------------------

    always_ff @(posedge clk) begin
        if (rst) begin
            overrun <= 1'b0;

        end else if (sample_tick && busy) begin
            overrun <= 1'b1;
        end
    end

endmodule
