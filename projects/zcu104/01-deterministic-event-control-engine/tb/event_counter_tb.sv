// ============================================================================
// Deterministic Event & Control Engine
// Event Counter Testbench
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

`timescale 1ns/1ps

module event_counter_tb;

    localparam time CLK_PERIOD = 8ns;
    localparam int unsigned TEST_COUNT_WIDTH = 4;

    logic clk         = 1'b0;
    logic rst         = 1'b1;
    logic event_pulse = 1'b0;

    logic [TEST_COUNT_WIDTH-1:0] event_count;

    event_counter #(
        .COUNT_WIDTH(TEST_COUNT_WIDTH)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .event_pulse (event_pulse),
        .event_count (event_count)
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

    task automatic generate_event;
        @(negedge clk);
        event_pulse <= 1'b1;

        @(posedge clk);
        #1;

        @(negedge clk);
        event_pulse <= 1'b0;
    endtask

    initial begin

        // ------------------------------------------------------------
        // Reset
        // ------------------------------------------------------------
        repeat (3) @(posedge clk);

        @(negedge clk);
        rst <= 1'b0;

        @(posedge clk);
        check_count(4'd0, "Reset clears counter");

        // ------------------------------------------------------------
        // Single event
        // ------------------------------------------------------------
        generate_event();
        check_count(4'd1, "Single event increments count");

        // ------------------------------------------------------------
        // Four additional events
        // Total should now equal five.
        // ------------------------------------------------------------
        repeat (4) begin
            generate_event();
        end

        check_count(4'd5, "Five events counted correctly");

        // ------------------------------------------------------------
        // No event: count must hold.
        // ------------------------------------------------------------
        repeat (3) @(posedge clk);
        check_count(4'd5, "Count holds without event");

        // ------------------------------------------------------------
        // Advance from 5 to 15.
        // ------------------------------------------------------------
        repeat (10) begin
            generate_event();
        end

        check_count(4'd15, "Maximum 4-bit count reached");

        // ------------------------------------------------------------
        // Rollover: 15 + 1 = 0.
        // ------------------------------------------------------------
        generate_event();
        check_count(4'd0, "Counter rollover");

        $display("========================================");
        $display("EVENT COUNTER TEST COMPLETE");
        $display("========================================");

        $finish;
    end

endmodule