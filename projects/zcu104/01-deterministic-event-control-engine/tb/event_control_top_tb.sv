// ============================================================================
// Deterministic Event & Control Engine
// Full-System Integration Testbench
//
// Verifies complete asynchronous-event qualification, counting, and
// deterministic non-retriggerable output control.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

`timescale 1ns/1ps

module event_control_top_tb;

    localparam time CLK_PERIOD = 8ns;

    // Reduced verification parameters.
    localparam int unsigned TEST_DEBOUNCE_CYCLES = 4;
    localparam int unsigned TEST_COUNT_WIDTH     = 4;
    localparam int unsigned TEST_ACTIVE_CYCLES   = 40;

    logic clk         = 1'b0;
    logic rst         = 1'b1;
    logic event_async = 1'b0;

    logic event_sync;
    logic event_debounced;
    logic event_pulse;
    logic [TEST_COUNT_WIDTH-1:0] event_count;
    logic output_active;

    event_control_top #(
        .SYNCHRONIZER_STAGES (2),
        .DEBOUNCE_CYCLES     (TEST_DEBOUNCE_CYCLES),
        .EVENT_COUNT_WIDTH   (TEST_COUNT_WIDTH),
        .OUTPUT_ACTIVE_CYCLES(TEST_ACTIVE_CYCLES)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .event_async     (event_async),
        .event_sync      (event_sync),
        .event_debounced (event_debounced),
        .event_pulse     (event_pulse),
        .event_count     (event_count),
        .output_active   (output_active)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic check_count(
        input logic [TEST_COUNT_WIDTH-1:0] expected,
        input string test_name
    );
        #1;

        if (event_count !== expected)
            $error(
                "FAIL: %s | expected count=%0d actual=%0d",
                test_name, expected, event_count
            );
        else
            $display(
                "PASS: %s | event_count=%0d",
                test_name, event_count
            );
    endtask

    task automatic check_output(
        input logic expected,
        input string test_name
    );
        #1;

        if (output_active !== expected)
            $error(
                "FAIL: %s | expected output=%0b actual=%0b",
                test_name, expected, output_active
            );
        else
            $display(
                "PASS: %s | output_active=%0b",
                test_name, output_active
            );
    endtask

    task automatic bouncing_press;
        #3 event_async <= 1'b1;
        #5 event_async <= 1'b0;
        #3 event_async <= 1'b1;
        #6 event_async <= 1'b0;
        #5 event_async <= 1'b1;
    endtask

    task automatic bouncing_release;
        #3 event_async <= 1'b0;
        #5 event_async <= 1'b1;
        #3 event_async <= 1'b0;
        #6 event_async <= 1'b1;
        #5 event_async <= 1'b0;
    endtask

    initial begin

        // ------------------------------------------------------------
        // Reset
        // ------------------------------------------------------------
        repeat (4) @(posedge clk);

        @(negedge clk);
        rst <= 1'b0;

        repeat (2) @(posedge clk);

        check_count(4'd0, "System count after reset");
        check_output(1'b0, "System output idle after reset");

        // ------------------------------------------------------------
        // Bounce without a valid sustained press.
        // ------------------------------------------------------------
        #3 event_async <= 1'b1;
        #4 event_async <= 1'b0;
        #3 event_async <= 1'b1;
        #4 event_async <= 1'b0;

        repeat (8) @(posedge clk);

        check_count(4'd0, "Input bounce creates no event");
        check_output(1'b0, "Input bounce creates no output");

        // ------------------------------------------------------------
        // First valid physical press with mechanical-style bounce.
        // ------------------------------------------------------------
        bouncing_press();

        wait (event_count == 4'd1);
        #1;

        check_count(4'd1, "First valid press counted");
        check_output(1'b1, "First valid press activates output");

        // ------------------------------------------------------------
        // While the first output interval is active:
        // release the button and generate another qualified press.
        //
        // The second event MUST be counted but MUST NOT restart
        // or extend the existing output interval.
        // ------------------------------------------------------------
        fork

            begin : output_duration_check

                repeat (TEST_ACTIVE_CYCLES - 1) @(posedge clk);
                check_output(
                    1'b1,
                    "Output remains active before original timeout"
                );

                @(posedge clk);
                check_output(
                    1'b0,
                    "Output terminates at original timeout"
                );

            end

            begin : second_event_during_active

                repeat (3) @(posedge clk);

                bouncing_release();

                // Allow release to pass synchronization and debounce.
                repeat (10) @(posedge clk);

                check_count(
                    4'd1,
                    "Qualified release creates no new event"
                );

                bouncing_press();

                wait (event_count == 4'd2);
                #1;

                check_count(
                    4'd2,
                    "Second valid press counted during active output"
                );

                check_output(
                    1'b1,
                    "Second event does not interrupt active output"
                );

            end

        join

        // ------------------------------------------------------------
        // Confirm second event did not extend first output interval.
        // ------------------------------------------------------------
        check_count(
            4'd2,
            "Two qualified physical presses recorded"
        );

        check_output(
            1'b0,
            "Active interval was not retriggered"
        );

        $display("========================================");
        $display("FULL EVENT CONTROL ENGINE TEST COMPLETE");
        $display("========================================");

        $finish;

    end

endmodule