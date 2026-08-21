// ============================================================================
// Deterministic Event & Control Engine
// Output Controller Testbench
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

`timescale 1ns/1ps

module output_controller_tb;

    localparam time CLK_PERIOD = 8ns;
    localparam int unsigned TEST_ACTIVE_CYCLES = 6;

    logic clk         = 1'b0;
    logic rst         = 1'b1;
    logic event_pulse = 1'b0;
    logic output_active;

    output_controller #(
        .OUTPUT_ACTIVE_CYCLES(TEST_ACTIVE_CYCLES)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .event_pulse   (event_pulse),
        .output_active (output_active)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic check_output(
        input logic expected,
        input string test_name
    );
        #1;

        if (output_active !== expected) begin
            $error(
                "FAIL: %s | expected=%0b actual=%0b",
                test_name,
                expected,
                output_active
            );
        end
        else begin
            $display(
                "PASS: %s | output_active=%0b",
                test_name,
                output_active
            );
        end
    endtask

    initial begin

        // ------------------------------------------------------------
        // Reset
        // ------------------------------------------------------------
        repeat (3) @(posedge clk);

        @(negedge clk);
        rst <= 1'b0;

        @(posedge clk);
        check_output(1'b0, "Controller idle after reset");

        // ------------------------------------------------------------
        // First event
        // ------------------------------------------------------------
        @(negedge clk);
        event_pulse <= 1'b1;

        @(posedge clk);
        #1;
        event_pulse <= 1'b0;

        check_output(1'b1, "Event starts active interval");

        // ------------------------------------------------------------
        // Event during ACTIVE state.
        // Must NOT restart or extend timer.
        // ------------------------------------------------------------
        repeat (2) @(posedge clk);

        @(negedge clk);
        event_pulse <= 1'b1;

        @(posedge clk);
        #1;
        event_pulse <= 1'b0;

        check_output(1'b1, "Event during ACTIVE does not interrupt output");

        // ------------------------------------------------------------
        // Continue until defined interval expires.
        // ------------------------------------------------------------
        repeat (2) @(posedge clk);
        check_output(1'b1, "Output remains active before timeout");

        @(posedge clk);
        check_output(1'b0, "Output returns idle after timeout");

        // ------------------------------------------------------------
        // Second independent event
        // ------------------------------------------------------------
        @(negedge clk);
        event_pulse <= 1'b1;

        @(posedge clk);
        #1;
        event_pulse <= 1'b0;

        check_output(1'b1, "Second event starts new active interval");

        repeat (6) @(posedge clk);
        check_output(1'b0, "Second interval terminates correctly");

        $display("========================================");
        $display("OUTPUT CONTROLLER TEST COMPLETE");
        $display("========================================");

        $finish;
    end

endmodule