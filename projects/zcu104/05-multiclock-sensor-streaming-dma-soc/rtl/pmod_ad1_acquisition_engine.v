`timescale 1ns/1ps

/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 */

module pmod_ad1_acquisition_engine #(
    parameter integer CLK_FREQ_HZ    = 125000000,
    parameter integer SAMPLE_RATE_HZ = 10000,
    parameter integer SCLK_FREQ_HZ   = 2500000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        enable,

    output wire        cs_n,
    output wire        sclk,
    input  wire        sdata_a,
    input  wire        sdata_b,

    output wire [11:0] sample_a,
    output wire [11:0] sample_b,
    output wire        sample_valid,

    output wire        busy,
    output wire        sample_tick,
    output reg         overrun
);

    wire spi_start;

    assign spi_start = sample_tick && !busy;

    sample_rate_generator #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .SAMPLE_RATE_HZ (SAMPLE_RATE_HZ)
    ) sample_timer (
        .clk         (clk),
        .rst         (rst),
        .enable      (enable),
        .sample_tick (sample_tick)
    );

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

    always @(posedge clk) begin
        if (rst) begin
            overrun <= 1'b0;
        end else if (sample_tick && busy) begin
            overrun <= 1'b1;
        end
    end

endmodule
