`timescale 1ns/1ps

module tb_pmod_ad1_spi_master;

    localparam int unsigned CLK_FREQ_HZ  = 125_000_000;
    localparam int unsigned SCLK_FREQ_HZ =   2_500_000;

    logic clk;
    logic rst;

    logic start;
    logic busy;
    logic sample_valid;

    logic cs_n;
    logic sclk;
    logic sdata_a;
    logic sdata_b;

    logic [11:0] sample_a;
    logic [11:0] sample_b;

    integer observed_sclk_edges;

    // 125 MHz FPGA clock = 8 ns period
    initial begin
        clk = 1'b0;
        forever #4 clk = ~clk;
    end


    // DUT: our SPI master
    pmod_ad1_spi_master #(
        .CLK_FREQ_HZ  (CLK_FREQ_HZ),
        .SCLK_FREQ_HZ (SCLK_FREQ_HZ)
    ) dut (
        .clk          (clk),
        .rst          (rst),

        .start        (start),
        .busy         (busy),
        .sample_valid (sample_valid),

        .cs_n         (cs_n),
        .sclk         (sclk),
        .sdata_a      (sdata_a),
        .sdata_b      (sdata_b),

        .sample_a     (sample_a),
        .sample_b     (sample_b)
    );


    // Fake physical Pmod AD1
    pmod_ad1_model #(
        .SAMPLE_A (12'hA35),
        .SAMPLE_B (12'h5C7)
    ) adc_model (
        .cs_n    (cs_n),
        .sclk    (sclk),
        .sdata_a (sdata_a),
        .sdata_b (sdata_b)
    );


    // Count actual SPI rising edges.
    initial begin
        observed_sclk_edges = 0;
    end

    always @(posedge sclk) begin
        if (!cs_n)
            observed_sclk_edges = observed_sclk_edges + 1;
    end


    // Test sequence
    initial begin

        rst   = 1'b1;
        start = 1'b0;

        $display("========================================");
        $display("Pmod AD1 SPI Master Simulation");
        $display("========================================");

        // Hold reset for several FPGA clocks.
        repeat (5) @(posedge clk);

        @(negedge clk);
        rst = 1'b0;

        repeat (2) @(posedge clk);

        // Generate one-clock start request.
        @(negedge clk);
        start = 1'b1;

        @(negedge clk);
        start = 1'b0;

        $display("SPI transaction started.");

        // Wait for completed ADC sample.
        wait (sample_valid == 1'b1);

        #1;

        $display("Transaction complete.");
        $display("Channel A received: 0x%03h", sample_a);
        $display("Channel B received: 0x%03h", sample_b);
        $display("Observed SCLK rising edges: %0d",
                 observed_sclk_edges);

        // Verify Channel A.
        if (sample_a !== 12'hA35) begin
            $fatal(1,
                "FAIL: Channel A expected A35, received %03h",
                sample_a);
        end

        // Verify Channel B.
        if (sample_b !== 12'h5C7) begin
            $fatal(1,
                "FAIL: Channel B expected 5C7, received %03h",
                sample_b);
        end

        // Exactly sixteen serial clocks should have occurred.
        if (observed_sclk_edges != 16) begin
            $fatal(1,
                "FAIL: Expected 16 SCLK rising edges, observed %0d",
                observed_sclk_edges);
        end

        // Transaction must be finished.
        if (busy !== 1'b0) begin
            $fatal(1, "FAIL: busy remained asserted.");
        end

        if (cs_n !== 1'b1) begin
            $fatal(1, "FAIL: CS did not return HIGH.");
        end

        if (sclk !== 1'b0) begin
            $fatal(1, "FAIL: SCLK did not return LOW.");
        end

        // sample_valid should last exactly one FPGA clock.
        @(posedge clk);
        #1;

        if (sample_valid !== 1'b0) begin
            $fatal(1,
                "FAIL: sample_valid lasted longer than one clock.");
        end

        $display("");
        $display("PASS: SPI transaction completed correctly.");
        $display("PASS: 16 SCLK cycles generated.");
        $display("PASS: Channel A = 0xA35.");
        $display("PASS: Channel B = 0x5C7.");
        $display("PASS: sample_valid is one FPGA clock.");
        $display("========================================");

        $finish;
    end

endmodule
