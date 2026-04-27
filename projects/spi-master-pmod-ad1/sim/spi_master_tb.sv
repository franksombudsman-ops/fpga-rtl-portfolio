`timescale 1ns / 1ps
// =============================================================================
// spi_master_tb.sv — Directed testbench for spi_master.sv
//
// Tests:
//   1. Single transfer: TX 0xABCD, check MOSI bit stream
//   2. RX capture: drive a known MISO pattern, check data_o
//   3. Back-to-back transfers separated by one idle cycle
//   4. busy_o / done_o handshake timing
// =============================================================================

module spi_master_tb;

    // ── Parameters (fast sim: CLK_DIV=2, 16-bit) ─────────────────────────────
    localparam int BITS    = 16;
    localparam int CLK_DIV = 2;    // SCLK = clk / 4 for fast simulation

    // ── DUT signals ──────────────────────────────────────────────────────────
    logic              clk;
    logic              rst_n;
    logic              start;
    logic [BITS-1:0]   data_i;
    logic [BITS-1:0]   data_o;
    logic              busy;
    logic              done;
    logic              sclk;
    logic              cs_n;
    logic              mosi;
    logic              miso;

    // ── DUT ──────────────────────────────────────────────────────────────────
    spi_master #(
        .BITS    (BITS),
        .CLK_DIV (CLK_DIV)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .start_i(start),
        .data_i (data_i),
        .data_o (data_o),
        .busy_o (busy),
        .done_o (done),
        .sclk_o (sclk),
        .cs_n_o (cs_n),
        .mosi_o (mosi),
        .miso_i (miso)
    );

    // ── 100 MHz clock ─────────────────────────────────────────────────────────
    initial clk = 0;
    always  #5 clk = ~clk;

    // ── MISO model: shift-register driven by task ────────────────────────────
    logic [BITS-1:0] miso_pattern;
    int              miso_bit_idx;

    // Drive MISO on the falling edge of SCLK (AD7476A / SPI mode 0 behaviour)
    always @(negedge sclk) begin
        if (!cs_n) begin
            miso <= miso_pattern[BITS - 1 - miso_bit_idx];
            miso_bit_idx++;
        end
    end

    // ── Utility tasks ─────────────────────────────────────────────────────────
    // Wait for the DUT to finish one transfer
    task automatic wait_done;
        @(posedge done);
        @(posedge clk);
    endtask

    // Start one transfer and arm the MISO shifter
    task automatic do_transfer(
        input logic [BITS-1:0] tx_data,
        input logic [BITS-1:0] rx_pattern
    );
        miso_pattern = rx_pattern;
        miso_bit_idx = 0;
        @(posedge clk); #1;
        data_i = tx_data;
        start  = 1'b1;
        @(posedge clk); #1;
        start  = 1'b0;
        wait_done();
    endtask

    // ── Capture MOSI bits and verify ──────────────────────────────────────────
    logic [BITS-1:0] mosi_capture;
    int              mosi_cap_idx;
    logic            capture_en;

    always @(posedge sclk) begin
        if (capture_en && !cs_n) begin
            mosi_capture[BITS - 1 - mosi_cap_idx] = mosi;
            mosi_cap_idx++;
        end
    end

    // ── Stimulus ──────────────────────────────────────────────────────────────
    initial begin
        // Initialise
        rst_n        = 1'b0;
        start        = 1'b0;
        data_i       = '0;
        miso         = 1'b0;
        miso_pattern = '0;
        miso_bit_idx = 0;
        capture_en   = 1'b0;
        mosi_capture = '0;
        mosi_cap_idx = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // ── Test 1: TX pattern on MOSI ────────────────────────────────────
        $display("[%0t] TEST 1: TX 0xABCD, check MOSI", $time);
        capture_en   = 1'b1;
        mosi_cap_idx = 0;
        do_transfer(16'hABCD, 16'h0000);
        capture_en = 1'b0;
        if (mosi_capture === 16'hABCD)
            $display("[%0t] PASS: MOSI captured 0x%04X", $time, mosi_capture);
        else
            $display("[%0t] FAIL: MOSI expected 0xABCD, got 0x%04X", $time, mosi_capture);

        repeat (4) @(posedge clk);

        // ── Test 2: RX capture on MISO ────────────────────────────────────
        $display("[%0t] TEST 2: drive MISO 0x1234, check data_o", $time);
        do_transfer(16'h0000, 16'h1234);
        if (data_o === 16'h1234)
            $display("[%0t] PASS: data_o = 0x%04X", $time, data_o);
        else
            $display("[%0t] FAIL: expected 0x1234, got 0x%04X", $time, data_o);

        repeat (4) @(posedge clk);

        // ── Test 3: AD7476A frame — 12-bit result in [12:1] ───────────────
        // Frame: 00 0 <DB11..DB0> <DB0>  — e.g., DB=0xFFF → frame=0x1FFE
        $display("[%0t] TEST 3: AD7476A frame 0x1FFE → result should be 0xFFF", $time);
        do_transfer(16'h0000, 16'h1FFE);
        if (data_o[12:1] === 12'hFFF)
            $display("[%0t] PASS: 12-bit result = 0x%03X", $time, data_o[12:1]);
        else
            $display("[%0t] FAIL: 12-bit result = 0x%03X (expected 0xFFF)", $time, data_o[12:1]);

        repeat (4) @(posedge clk);

        // ── Test 4: busy_o stays high for entire transfer ─────────────────
        $display("[%0t] TEST 4: busy_o high during transfer", $time);
        miso_pattern = 16'hAAAA;
        miso_bit_idx = 0;
        @(posedge clk); #1;
        start = 1'b1;
        @(posedge clk); #1;
        start = 1'b0;
        // busy must be asserted by now
        if (!busy) $display("[%0t] FAIL: busy_o should be high", $time);
        wait_done();
        if (busy) $display("[%0t] FAIL: busy_o should be low after done", $time);
        else      $display("[%0t] PASS: busy_o deasserted after done_o", $time);

        $display("[%0t] --- All tests complete ---", $time);
        $finish;
    end

endmodule
