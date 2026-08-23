`timescale 1ns/1ps

module tb_pmod_ad1_acquisition_engine;

    localparam int unsigned CLK_FREQ_HZ    = 125_000_000;
    localparam int unsigned SAMPLE_RATE_HZ =      10_000;
    localparam int unsigned SCLK_FREQ_HZ   =   2_500_000;

    logic clk;
    logic rst;
    logic enable;

    logic cs_n;
    logic sclk;
    logic sdata_a;
    logic sdata_b;

    logic [11:0] sample_a;
    logic [11:0] sample_b;

    logic sample_valid;
    logic busy;
    logic sample_tick;
    logic overrun;

    integer sample_count;

    time valid_time_1;
    time valid_time_2;
    time valid_time_3;


    // ---------------------------------------------------------
    // 125 MHz FPGA clock
    // ---------------------------------------------------------

    initial begin
        clk = 1'b0;
        forever #4 clk = ~clk;
    end


    // ---------------------------------------------------------
    // Complete acquisition subsystem
    // ---------------------------------------------------------

    pmod_ad1_acquisition_engine #(
        .CLK_FREQ_HZ    (CLK_FREQ_HZ),
        .SAMPLE_RATE_HZ (SAMPLE_RATE_HZ),
        .SCLK_FREQ_HZ   (SCLK_FREQ_HZ)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .enable       (enable),

        .cs_n         (cs_n),
        .sclk         (sclk),
        .sdata_a      (sdata_a),
        .sdata_b      (sdata_b),

        .sample_a     (sample_a),
        .sample_b     (sample_b),
        .sample_valid (sample_valid),

        .busy         (busy),
        .sample_tick  (sample_tick),
        .overrun      (overrun)
    );


    // ---------------------------------------------------------
    // Fake Pmod AD1
    // ---------------------------------------------------------

    pmod_ad1_model #(
        .SAMPLE_A (12'hA35),
        .SAMPLE_B (12'h5C7)
    ) adc_model (
        .cs_n    (cs_n),
        .sclk    (sclk),
        .sdata_a (sdata_a),
        .sdata_b (sdata_b)
    );


    // ---------------------------------------------------------
    // Count completed samples
    // ---------------------------------------------------------

    always @(posedge sample_valid) begin
        sample_count = sample_count + 1;

        $display(
            "Sample %0d complete at %0d ns: A=0x%03h B=0x%03h",
            sample_count,
            $time,
            sample_a,
            sample_b
        );
    end


    // ---------------------------------------------------------
    // Main verification
    // ---------------------------------------------------------

    initial begin

        rst          = 1'b1;
        enable       = 1'b0;
        sample_count = 0;

        $display("================================================");
        $display("Pmod AD1 Periodic Acquisition Engine Simulation");
        $display("FPGA clock : 125 MHz");
        $display("SPI clock  : 2.5 MHz");
        $display("Sample rate: 10 kS/s");
        $display("================================================");

        // Reset
        repeat (5) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        @(negedge clk);
        enable = 1'b1;


        // -----------------------------------------------------
        // First completed ADC sample
        // -----------------------------------------------------

        @(posedge sample_valid);
        valid_time_1 = $time;

        #1;

        if (sample_a !== 12'hA35)
            $fatal(1,
                "FAIL: Sample A expected A35, got %03h",
                sample_a);

        if (sample_b !== 12'h5C7)
            $fatal(1,
                "FAIL: Sample B expected 5C7, got %03h",
                sample_b);


        // -----------------------------------------------------
        // Second sample
        // -----------------------------------------------------

        @(posedge sample_valid);
        valid_time_2 = $time;

        if ((valid_time_2 - valid_time_1) != 100_000)
            $fatal(1,
                "FAIL: Sample interval = %0d ns, expected 100000 ns",
                valid_time_2 - valid_time_1);


        // -----------------------------------------------------
        // Third sample
        // -----------------------------------------------------

        @(posedge sample_valid);
        valid_time_3 = $time;

        if ((valid_time_3 - valid_time_2) != 100_000)
            $fatal(1,
                "FAIL: Sample interval = %0d ns, expected 100000 ns",
                valid_time_3 - valid_time_2);


        // -----------------------------------------------------
        // There should be no throughput failure.
        // -----------------------------------------------------

        if (overrun !== 1'b0)
            $fatal(1,
                "FAIL: Unexpected acquisition overrun detected.");


        $display("");
        $display("PASS: Periodic ADC acquisition operating correctly.");
        $display("PASS: Channel A = 0xA35.");
        $display("PASS: Channel B = 0x5C7.");
        $display("PASS: Completed sample interval = 100 us.");
        $display("PASS: Effective sample rate = 10 kS/s.");
        $display("PASS: No acquisition overrun detected.");
        $display("================================================");

        $finish;
    end

endmodule
