`timescale 1ns/1ps

module tb_sample_rate_generator;

    localparam int unsigned CLK_FREQ_HZ    = 125_000_000;
    localparam int unsigned SAMPLE_RATE_HZ =      10_000;

    localparam time EXPECTED_PERIOD_NS = 100_000;
    localparam time EXPECTED_PULSE_NS  = 8;

    logic clk;
    logic rst;
    logic enable;
    logic sample_tick;

    time tick_time_1;
    time tick_time_2;
    time tick_time_3;
    time pulse_end_time;

    // 125 MHz clock = 8 ns period
    initial begin
        clk = 1'b0;
        forever #4 clk = ~clk;
    end


    sample_rate_generator #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .SAMPLE_RATE_HZ (SAMPLE_RATE_HZ)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .enable      (enable),
        .sample_tick (sample_tick)
    );


    initial begin

        rst    = 1'b1;
        enable = 1'b0;

        $display("========================================");
        $display("Sample Rate Generator Simulation");
        $display("FPGA clock     : 125 MHz");
        $display("Sample rate    : 10 kS/s");
        $display("Expected period: 100 us");
        $display("========================================");

        // Reset
        repeat (5) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        @(negedge clk);
        enable = 1'b1;

        // --------------------------
        // First sampling pulse
        // --------------------------

        @(posedge sample_tick);
        tick_time_1 = $time;

        $display("Tick 1 at %0d ns", tick_time_1);

        @(negedge sample_tick);
        pulse_end_time = $time;

        if ((pulse_end_time - tick_time_1) != EXPECTED_PULSE_NS)
            $fatal(1,
                "FAIL: sample_tick width = %0d ns, expected 8 ns",
                pulse_end_time - tick_time_1);


        // --------------------------
        // Second sampling pulse
        // --------------------------

        @(posedge sample_tick);
        tick_time_2 = $time;

        $display("Tick 2 at %0d ns", tick_time_2);

        if ((tick_time_2 - tick_time_1) != EXPECTED_PERIOD_NS)
            $fatal(1,
                "FAIL: Tick period = %0d ns, expected 100000 ns",
                tick_time_2 - tick_time_1);


        // --------------------------
        // Third sampling pulse
        // --------------------------

        @(posedge sample_tick);
        tick_time_3 = $time;

        $display("Tick 3 at %0d ns", tick_time_3);

        if ((tick_time_3 - tick_time_2) != EXPECTED_PERIOD_NS)
            $fatal(1,
                "FAIL: Tick period = %0d ns, expected 100000 ns",
                tick_time_3 - tick_time_2);


        $display("");
        $display("PASS: Sample rate generator operating correctly.");
        $display("PASS: Sampling period = 100 us.");
        $display("PASS: Sampling rate = 10 kS/s.");
        $display("PASS: sample_tick width = one 125 MHz clock.");
        $display("========================================");

        $finish;
    end

endmodule
