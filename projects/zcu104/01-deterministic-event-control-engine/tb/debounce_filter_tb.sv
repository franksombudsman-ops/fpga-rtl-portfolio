// ============================================================================
// Deterministic Event & Control Engine
// Debounce Filter Testbench
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

`timescale 1ns/1ps

module debounce_filter_tb;

    localparam time CLK_PERIOD = 8ns;

    // Reduced only to accelerate simulation.
    localparam int unsigned TEST_DEBOUNCE_CYCLES = 4;

    logic clk     = 1'b0;
    logic rst     = 1'b1;
    logic sync_in = 1'b0;

    logic debounced_out;

    debounce_filter #(
        .DEBOUNCE_CYCLES(TEST_DEBOUNCE_CYCLES)
    ) dut (
        .clk           (clk),
        .rst           (rst),
        .sync_in       (sync_in),
        .debounced_out (debounced_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic check_output(
        input logic expected,
        input string test_name
    );
        #1;
        if (debounced_out !== expected) begin
            $error(
                "FAIL: %s | expected=%0b actual=%0b",
                test_name,
                expected,
                debounced_out
            );
        end
        else begin
            $display(
                "PASS: %s | debounced_out=%0b",
                test_name,
                debounced_out
            );
        end
    endtask

    initial begin

        // ------------------------------------------------------------
        // Reset
        // ------------------------------------------------------------
        repeat (3) @(posedge clk);
        rst <= 1'b0;

        @(posedge clk);
        check_output(1'b0, "Reset state");

        // ------------------------------------------------------------
        // Short HIGH disturbance: must be rejected
        // ------------------------------------------------------------
        @(negedge clk);
        sync_in <= 1'b1;

        repeat (2) @(posedge clk);
        check_output(1'b0, "Short HIGH disturbance rejected");

        @(negedge clk);
        sync_in <= 1'b0;

        @(posedge clk);
        check_output(1'b0, "Return to LOW cancels qualification");

        // ------------------------------------------------------------
        // Valid HIGH transition
        // ------------------------------------------------------------
        @(negedge clk);
        sync_in <= 1'b1;

        repeat (TEST_DEBOUNCE_CYCLES - 1) @(posedge clk);
        check_output(1'b0, "HIGH not accepted too early");

        @(posedge clk);
        check_output(1'b1, "HIGH accepted after required stability");

        // ------------------------------------------------------------
        // Short LOW disturbance: must be rejected
        // ------------------------------------------------------------
        @(negedge clk);
        sync_in <= 1'b0;

        repeat (2) @(posedge clk);
        check_output(1'b1, "Short LOW disturbance rejected");

        @(negedge clk);
        sync_in <= 1'b1;

        @(posedge clk);
        check_output(1'b1, "Return to HIGH cancels release");

        // ------------------------------------------------------------
        // Valid LOW transition
        // ------------------------------------------------------------
        @(negedge clk);
        sync_in <= 1'b0;

        repeat (TEST_DEBOUNCE_CYCLES - 1) @(posedge clk);
        check_output(1'b1, "LOW not accepted too early");

        @(posedge clk);
        check_output(1'b0, "LOW accepted after required stability");

        $display("========================================");
        $display("DEBOUNCE FILTER TEST COMPLETE");
        $display("========================================");

        $finish;
    end

endmodule