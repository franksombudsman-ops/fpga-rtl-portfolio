`timescale 1ns / 1ps
// =============================================================================
// pmod_ad1_tb.sv — Directed testbench for pmod_ad1_reader.sv
//
// Uses SPI_FREQ=10 MHz and SAMPLE_RATE=100_000 so the autonomous sample timer
// fires every 1000 system clocks (100 MHz / 100 000), keeping simulation fast.
//
// An AD7476A behavioral model drives MISO with {4'b0000, 12-bit test value}
// each time CS_N goes low.  The test checks two consecutive ADC samples with
// known values, verifying the 12-bit frame extraction in pmod_ad1_reader.
//
// Tests:
//   1. First  sample — slave returns {4'b0000, 12'hABC}; check adc_data==0xABC
//   2. Second sample — slave returns {4'b0000, 12'h321}; check adc_data==0x321
// =============================================================================

module pmod_ad1_tb;

    // ── Parameters ────────────────────────────────────────────────────────────
    localparam int CLK_FREQ    = 100_000_000;
    localparam int SPI_FREQ    =  10_000_000;
    localparam int SAMPLE_RATE =     100_000;  // timer fires every 1000 clocks

    // ── DUT signals ───────────────────────────────────────────────────────────
    logic        clk;
    logic        rst_n;
    logic        sclk;
    logic        mosi;
    logic        miso;
    logic        cs_n;
    logic [11:0] adc_data;
    logic        data_valid;

    // ── DUT instantiation ─────────────────────────────────────────────────────
    pmod_ad1_reader #(
        .CLK_FREQ    (CLK_FREQ),
        .SPI_FREQ    (SPI_FREQ),
        .SAMPLE_RATE (SAMPLE_RATE)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .sclk       (sclk),
        .mosi       (mosi),
        .cs_n       (cs_n),
        .miso       (miso),
        .adc_data   (adc_data),
        .data_valid (data_valid)
    );

    // ── 100 MHz clock ─────────────────────────────────────────────────────────
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // ── AD7476A behavioral model ──────────────────────────────────────────────
    // Frame format: {4'b0000, adc[11:0]} — 16 bits, MSB first
    logic [15:0] adc_response;   // test code writes this before each transaction
    logic [15:0] adc_frame;      // latched on CS_N assertion
    int          adc_bit;        // bit index within current frame (0 = MSB)

    // CS_N assertion: latch frame, pre-drive first bit
    always @(negedge cs_n) begin
        adc_frame = adc_response;
        adc_bit   = 0;
        miso      = adc_frame[15];  // MSB of frame (always 0)
        $display("[%0t ns] CS_N assert — ADC loaded frame 0x%04X",
                 $time, adc_frame);
    end

    // SCLK falling edge: shift out next MISO bit
    always @(negedge sclk) begin
        if (!cs_n) begin
            adc_bit++;
            if (adc_bit < 16)
                miso = adc_frame[15 - adc_bit];
        end
    end

    // ── Stimulus ──────────────────────────────────────────────────────────────
    initial begin
        rst_n        = 1'b0;
        miso         = 1'b0;
        adc_response = {4'b0000, 12'hABC};   // first test value

        repeat (5) @(posedge clk);
        rst_n = 1'b1;

        // ── Sample 1: expect 0xABC ─────────────────────────────────────────
        $display("\n[%0t ns] Waiting for first data_valid (ADC value 0xABC)...", $time);
        @(posedge data_valid);
        @(posedge clk);

        if (adc_data === 12'hABC)
            $display("[%0t ns] PASS — adc_data = 0x%03X (expected 0xABC)", $time, adc_data);
        else
            $display("[%0t ns] FAIL — adc_data = 0x%03X (expected 0xABC)", $time, adc_data);

        // Switch to second test value (well before next CS_N assertion)
        adc_response = {4'b0000, 12'h321};
        $display("[%0t ns] Updated slave response to 0x321", $time);

        // ── Sample 2: expect 0x321 ─────────────────────────────────────────
        $display("[%0t ns] Waiting for second data_valid (ADC value 0x321)...", $time);
        @(posedge data_valid);
        @(posedge clk);

        if (adc_data === 12'h321)
            $display("[%0t ns] PASS — adc_data = 0x%03X (expected 0x321)", $time, adc_data);
        else
            $display("[%0t ns] FAIL — adc_data = 0x%03X (expected 0x321)", $time, adc_data);

        $display("\n[%0t ns] ---- All tests complete ----\n", $time);
        $finish;
    end

endmodule
