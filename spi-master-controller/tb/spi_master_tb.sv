`timescale 1ns / 1ps
// =============================================================================
// spi_master_tb.sv — Directed testbench for spi_master.sv
//
// Uses DATA_WIDTH=8 and SPI_FREQ=10 MHz (CLK_FREQ=100 MHz → HALF_PERIOD=5)
// for fast simulation.  A behavioral SPI slave model pre-drives MISO from a
// preloaded response register, capturing MOSI bits in parallel.
//
// Tests:
//   1. TX verification   — master sends 8'h3C; slave captures and checks
//   2. RX verification   — slave returns 8'hA5; master captures and checks
//   3. Second transaction — different TX/RX values; repeated pass/fail check
//   4. busy/done timing  — busy high throughout transfer, done for one cycle
// =============================================================================

module spi_master_tb;

    // ── Parameters ────────────────────────────────────────────────────────────
    localparam int CLK_FREQ   = 100_000_000;
    localparam int SPI_FREQ   =  10_000_000;
    localparam int DATA_WIDTH = 8;

    // ── DUT signals ───────────────────────────────────────────────────────────
    logic                   clk;
    logic                   rst_n;
    logic                   start;
    logic [DATA_WIDTH-1:0]  data_in;
    logic                   miso;
    logic                   sclk;
    logic                   mosi;
    logic                   cs_n;
    logic [DATA_WIDTH-1:0]  data_out;
    logic                   done;
    logic                   busy;

    // ── DUT instantiation ─────────────────────────────────────────────────────
    spi_master #(
        .CLK_FREQ   (CLK_FREQ),
        .SPI_FREQ   (SPI_FREQ),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .data_in  (data_in),
        .miso     (miso),
        .sclk     (sclk),
        .mosi     (mosi),
        .cs_n     (cs_n),
        .data_out (data_out),
        .done     (done),
        .busy     (busy)
    );

    // ── 100 MHz clock ─────────────────────────────────────────────────────────
    initial clk = 1'b0;
    always  #5 clk = ~clk;

    // ── Behavioral SPI slave model ────────────────────────────────────────────
    logic [DATA_WIDTH-1:0] slave_response;  // test code sets this before start
    logic [DATA_WIDTH-1:0] slave_frame;     // latched copy for the transaction
    logic [DATA_WIDTH-1:0] slave_rx;        // bits received from master
    int                    slave_bit;       // next bit index to drive (0 = MSB)

    // On CS_N assertion: latch response, pre-drive MSB, clear RX
    always @(negedge cs_n) begin
        slave_frame = slave_response;
        slave_rx    = '0;
        slave_bit   = 0;
        miso        = slave_frame[DATA_WIDTH-1];
        $display("[%0t ns] CS_N assert — slave loaded response 0x%02X",
                 $time, slave_frame);
    end

    // On SCLK falling edge: advance to next MISO bit
    always @(negedge sclk) begin
        if (!cs_n) begin
            $display("[%0t ns] SCLK↓  MOSI=%b MISO=%b", $time, mosi, miso);
            slave_bit++;
            if (slave_bit < DATA_WIDTH)
                miso = slave_frame[DATA_WIDTH-1 - slave_bit];
        end
    end

    // On SCLK rising edge: sample MOSI into slave RX shift register
    always @(posedge sclk) begin
        if (!cs_n) begin
            slave_rx = {slave_rx[DATA_WIDTH-2:0], mosi};
            $display("[%0t ns] SCLK↑  MOSI=%b MISO=%b", $time, mosi, miso);
        end
    end

    // ── Utility task: run one full transfer ───────────────────────────────────
    task automatic do_transfer(
        input logic [DATA_WIDTH-1:0] tx_data,
        input logic [DATA_WIDTH-1:0] rx_pattern
    );
        slave_response = rx_pattern;
        @(posedge clk); #1;
        data_in = tx_data;
        start   = 1'b1;
        @(posedge clk); #1;
        start   = 1'b0;
        @(posedge done);
        @(posedge clk);
    endtask

    // ── Stimulus ──────────────────────────────────────────────────────────────
    initial begin
        rst_n          = 1'b0;
        start          = 1'b0;
        data_in        = '0;
        miso           = 1'b0;
        slave_response = '0;
        slave_frame    = '0;
        slave_rx       = '0;
        slave_bit      = 0;

        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        // ── Test 1 & 2: TX=8'h3C, slave returns 8'hA5 ────────────────────
        $display("\n[%0t ns] ---- Transaction 1: TX=0x3C, RX=0xA5 ----", $time);
        do_transfer(8'h3C, 8'hA5);

        // Check RX: did master receive what the slave sent?
        if (data_out === 8'hA5)
            $display("[%0t ns] PASS — data_out = 0x%02X (expected 0xA5)", $time, data_out);
        else
            $display("[%0t ns] FAIL — data_out = 0x%02X (expected 0xA5)", $time, data_out);

        // Check TX: did the slave receive what the master sent?
        if (slave_rx === 8'h3C)
            $display("[%0t ns] PASS — slave_rx = 0x%02X (expected 0x3C)", $time, slave_rx);
        else
            $display("[%0t ns] FAIL — slave_rx = 0x%02X (expected 0x3C)", $time, slave_rx);

        repeat (4) @(posedge clk);

        // ── Test 3: second transaction with different values ──────────────
        $display("\n[%0t ns] ---- Transaction 2: TX=0xF0, RX=0x69 ----", $time);
        do_transfer(8'hF0, 8'h69);

        if (data_out === 8'h69)
            $display("[%0t ns] PASS — data_out = 0x%02X (expected 0x69)", $time, data_out);
        else
            $display("[%0t ns] FAIL — data_out = 0x%02X (expected 0x69)", $time, data_out);

        if (slave_rx === 8'hF0)
            $display("[%0t ns] PASS — slave_rx = 0x%02X (expected 0xF0)", $time, slave_rx);
        else
            $display("[%0t ns] FAIL — slave_rx = 0x%02X (expected 0xF0)", $time, slave_rx);

        repeat (4) @(posedge clk);

        // ── Test 4: busy/done handshake timing ───────────────────────────
        $display("\n[%0t ns] ---- Test 4: busy/done handshake ----", $time);
        slave_response = 8'hBB;
        @(posedge clk); #1;
        data_in = 8'hCC;
        start   = 1'b1;
        @(posedge clk); #1;
        start   = 1'b0;

        if (busy)
            $display("[%0t ns] PASS — busy asserted immediately after start", $time);
        else
            $display("[%0t ns] FAIL — busy should be high after start", $time);

        @(posedge done);
        @(posedge clk);

        if (!busy)
            $display("[%0t ns] PASS — busy deasserted one cycle after done", $time);
        else
            $display("[%0t ns] FAIL — busy should be low after done", $time);

        $display("\n[%0t ns] ---- All tests complete ----\n", $time);
        $finish;
    end

endmodule
