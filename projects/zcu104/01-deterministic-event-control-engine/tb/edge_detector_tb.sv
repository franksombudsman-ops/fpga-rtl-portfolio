// ============================================================================
// Deterministic Event & Control Engine
// Rising-Edge Detector Testbench
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

`timescale 1ns/1ps

module edge_detector_tb;

    localparam time CLK_PERIOD = 8ns;

    logic clk          = 1'b0;
    logic rst          = 1'b1;
    logic debounced_in = 1'b0;
    logic event_pulse;

    edge_detector dut (
        .clk          (clk),
        .rst          (rst),
        .debounced_in (debounced_in),
        .event_pulse  (event_pulse)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic check_event(
        input logic expected,
        input string test_name
    );
        #1;

        if (event_pulse !== expected) begin
            $error(
                "FAIL: %s | expected=%0b actual=%0b",
                test_name,
                expected,
                event_pulse
            );
        end
        else begin
            $display(
                "PASS: %s | event_pulse=%0b",
                test_name,
                event_pulse
            );
        end
    endtask

    initial begin

        // ------------------------------------------------------------
        // Reset behavior
        // ------------------------------------------------------------
        repeat (3) @(posedge clk);

        debounced_in <= 1'b1;
        check_event(1'b0, "Event suppressed during reset");

        @(negedge clk);
        debounced_in <= 1'b0;

        @(posedge clk);
        rst <= 1'b0;

        // ------------------------------------------------------------
        // Rising edge
        // ------------------------------------------------------------
        @(negedge clk);
        debounced_in <= 1'b1;

        #1;
        check_event(1'b1, "Rising edge generates event");

        @(posedge clk);
        #1;
        check_event(1'b0, "Event lasts only one clock interval");

        // ------------------------------------------------------------
        // Held HIGH
        // ------------------------------------------------------------
        repeat (3) begin
            @(posedge clk);
            check_event(1'b0, "Held HIGH does not retrigger");
        end

        // ------------------------------------------------------------
        // Falling edge
        // ------------------------------------------------------------
        @(negedge clk);
        debounced_in <= 1'b0;

        @(posedge clk);
        check_event(1'b0, "Falling edge generates no event");

        // ------------------------------------------------------------
        // Second valid rising edge
        // ------------------------------------------------------------
        @(negedge clk);
        debounced_in <= 1'b1;

        #1;
        check_event(1'b1, "Second rising edge generates event");

        @(posedge clk);
        #1;
        check_event(1'b0, "Second event terminates correctly");

        $display("========================================");
        $display("EDGE DETECTOR TEST COMPLETE");
        $display("========================================");

        $finish;
    end

endmodule