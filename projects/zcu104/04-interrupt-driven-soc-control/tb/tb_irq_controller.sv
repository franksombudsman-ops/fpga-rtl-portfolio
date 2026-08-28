`timescale 1ns/1ps

module tb_irq_controller;

    logic clk = 0;
    logic rst_n = 0;

    logic event_pulse = 0;
    logic irq_enable  = 0;
    logic irq_clear   = 0;

    logic irq_pending;
    logic irq_out;
    logic [31:0] event_count;

    irq_controller dut (
        .clk(clk),
        .rst_n(rst_n),
        .event_pulse(event_pulse),
        .irq_enable(irq_enable),
        .irq_clear(irq_clear),
        .irq_pending(irq_pending),
        .irq_out(irq_out),
        .event_count(event_count)
    );

    always #5 clk = ~clk;   // 100 MHz

    task automatic check(
        input string name,
        input logic expected_pending,
        input logic expected_irq,
        input logic [31:0] expected_count
    );
        begin
            #1;
            if ((irq_pending !== expected_pending) ||
                (irq_out     !== expected_irq) ||
                (event_count !== expected_count)) begin

                $display("FAIL: %s", name);
                $display(" pending=%b expected=%b", irq_pending, expected_pending);
                $display(" irq=%b expected=%b", irq_out, expected_irq);
                $display(" count=%0d expected=%0d",
                         event_count, expected_count);
                $fatal;
            end
            else begin
                $display("PASS: %s", name);
            end
        end
    endtask

    initial begin

        // Reset
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        @(posedge clk);
        check("reset state", 1'b0, 1'b0, 32'd0);

        // Masked event
        @(negedge clk);
        event_pulse = 1'b1;

        @(posedge clk);
        check("masked event becomes pending", 1'b1, 1'b0, 32'd1);

        @(negedge clk);
        event_pulse = 1'b0;

        // Enable pending IRQ
        irq_enable = 1'b1;
        check("enabling exposes pending IRQ", 1'b1, 1'b1, 32'd1);

        // Clear
        @(negedge clk);
        irq_clear = 1'b1;

        @(posedge clk);
        check("software clear", 1'b0, 1'b0, 32'd1);

        @(negedge clk);
        irq_clear = 1'b0;

        // Normal enabled event
        event_pulse = 1'b1;

        @(posedge clk);
        check("enabled event asserts IRQ", 1'b1, 1'b1, 32'd2);

        @(negedge clk);
        event_pulse = 1'b0;

        // Clear and new event simultaneously
        irq_clear   = 1'b1;
        event_pulse = 1'b1;

        @(posedge clk);
        check("simultaneous clear and event", 1'b1, 1'b1, 32'd3);

        @(negedge clk);
        irq_clear   = 1'b0;
        event_pulse = 1'b0;

        // Final clear
        irq_clear = 1'b1;

        @(posedge clk);
        check("final clear", 1'b0, 1'b0, 32'd3);

        @(negedge clk);
        irq_clear = 1'b0;

        $display("");
        $display("ALL INTERRUPT CONTROLLER TESTS PASSED");
        $display("");

        $finish;
    end

endmodule
