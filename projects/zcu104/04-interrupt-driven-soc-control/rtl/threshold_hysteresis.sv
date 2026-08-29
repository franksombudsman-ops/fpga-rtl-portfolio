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

module threshold_hysteresis #(
    parameter int DATA_WIDTH = 12
)(
    input  logic                  clk,
    input  logic                  rst,

    input  logic [DATA_WIDTH-1:0] sample_in,
    input  logic                  sample_valid,

    // Runtime configuration from AXI
    input  logic [DATA_WIDTH-1:0] high_threshold,
    input  logic [DATA_WIDTH-1:0] low_threshold,

    output logic                  control_request
);

    always_ff @(posedge clk) begin
        if (rst) begin
            control_request <= 1'b0;
        end
        else if (sample_valid) begin

            if (!control_request &&
                sample_in >= high_threshold)
                control_request <= 1'b1;

            else if (control_request &&
                     sample_in <= low_threshold)
                control_request <= 1'b0;
        end
    end

endmodule
