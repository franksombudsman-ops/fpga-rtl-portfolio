// ============================================================================
// Deterministic Event & Control Engine
// Event Front-End Integration Testbench
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

`timescale 1ns/1ps

module event_frontend_tb;

    localparam time CLK_PERIOD = 8ns;

    // Reduced verification parameters.
    localparam int unsigned TEST_DEBOUNCE_CYCLES = 4;
    localparam int unsigned TEST_COUNT_WIDTH     = 4;

    logic clk         = 1'b0;
    logic rst         = 1'b1;
    logic event_async = 1'b0;

    logic event_sync;
    logic event_debounced;
    logic event_pulse;
    logic [TEST_COUNT_WIDTH-1:0] event_count;

    event_frontend #(
        .SYNCHRONIZER_STAGES (2),
        .DEBOUNCE_CYCLES     (TEST_DEBOUNCE_CYCLES),
        .EVENT_COUNT_WIDTH   (TEST_COUNT_WIDTH)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .event_async     (event_async),
        .event_sync      (event_sync),
        .event_debounced (event_debounced),
        .event_pulse     (event_pulse),
        .event_count     (event_count)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic check_count(
        input logic [TEST_COUNT_WIDTH-1:0] expected,
        input string test_name
    );
        #1;

        if (event_count !== expected) begin
            $error(
                "FAIL: %s | expected=%0d actual=%0d",
                test_name,
                expected,
                event_count
            );
        end
        else begin
            $display(
                "PASS: %s | event_count=%0d",
                test_name,
                event_count
            );
        end
    endtask

    initial begin

        // ------------------------------------------------------------
        // Reset
        // ------------------------------------------------------------
        repeat (4) @(posedge clk);

        @(negedge clk);
        rst <= 1'b0;

        repeat (2) @(posedge clk);
        check_count(4'd0, "Reset state");

        // ------------------------------------------------------------
        // Simulated mechanical bounce before first valid press.
        // These transitions are deliberately asynchronous to the clock.
        // ------------------------------------------------------------
        #3 event_async <= 1'b1;
        #5 event_async <= 1'b0;
        #3 event_async <= 1'b1;
        #6 event_async <= 1'b0;
        #5 event_async <= 1'b1;
        #4 event_async <= 1'b0;

        // No stable press has occurred.
        repeat (3) @(posedge clk);
        check_count(4'd0, "Bounce does not create event");

        // ------------------------------------------------------------
        // First valid press
        // ------------------------------------------------------------
        #3 event_async <= 1'b1;

        // Allow synchronizer + debounce + edge detector + counter latency.
        repeat (10) @(posedge clk);
        check_count(4'd1, "First physical press creates one event");

        // Keep the button held.
        repeat (8) @(posedge clk);
        check_count(4'd1, "Held button does not retrigger");

        // ------------------------------------------------------------
        // Bouncing release
        // ------------------------------------------------------------
        #3 event_async <= 1'b0;
        #5 event_async <= 1'b1;
        #4 event_async <= 1'b0;
        #3 event_async <= 1'b1;
        #6 event_async <= 1'b0;

        repeat (10) @(posedge clk);
        check_count(4'd1, "Release produces no event");

        // ------------------------------------------------------------
        // Second valid press
        // ------------------------------------------------------------
        #5 event_async <= 1'b1;

        repeat (10) @(posedge clk);
        check_count(4'd2, "Second physical press creates second event");

        repeat (6) @(posedge clk);
        check_count(4'd2, "Second held press does not retrigger");

        $display("========================================");
        $display("EVENT FRONT-END INTEGRATION TEST COMPLETE");
        $display("========================================");

        $finish;
    end

endmodule