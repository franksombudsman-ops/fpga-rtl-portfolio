// =============================================================================
// pmod_ad1_reader.sv — Pmod AD1 (AD7476A 12-bit SAR ADC) reader
//
// Wraps spi_master with DATA_WIDTH=16 and adds an autonomous sample timer.
// The AD7476A returns a 16-bit frame each SPI transaction:
//   bits [15:12] — four leading zeros
//   bits [11:0]  — 12-bit conversion result, MSB first
//
// The sample timer fires a start pulse every (CLK_FREQ / SAMPLE_RATE) clocks.
// If the previous transaction has not completed when the timer fires, the
// sample is skipped to avoid corrupting an in-flight transfer.
//
// Outputs:
//   adc_data   — 12-bit unsigned result (valid when data_valid is high)
//   data_valid — one-cycle pulse coincident with valid adc_data
// =============================================================================

module pmod_ad1_reader #(
    parameter int CLK_FREQ    = 100_000_000,
    parameter int SPI_FREQ    =   1_000_000,
    parameter int SAMPLE_RATE =        1000   // conversions per second
) (
    input  logic        clk,
    input  logic        rst_n,

    // SPI bus
    output logic        sclk,
    output logic        mosi,
    output logic        cs_n,
    input  logic        miso,

    // ADC result
    output logic [11:0] adc_data,
    output logic        data_valid
);

    // ── Sample-rate timer ─────────────────────────────────────────────────────
    localparam int TIMER_MAX = CLK_FREQ / SAMPLE_RATE;
    localparam int TIMER_W   = $clog2(TIMER_MAX);

    logic [TIMER_W-1:0] timer;
    logic               spi_start;
    logic               spi_busy;
    logic               spi_done;
    logic [15:0]        spi_rx;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer     <= '0;
            spi_start <= 1'b0;
        end else begin
            spi_start <= 1'b0;
            if (timer == TIMER_W'(TIMER_MAX - 1)) begin
                timer <= '0;
                if (!spi_busy)
                    spi_start <= 1'b1;
            end else begin
                timer <= timer + 1'b1;
            end
        end
    end

    // ── SPI master instance ───────────────────────────────────────────────────
    spi_master #(
        .CLK_FREQ   (CLK_FREQ),
        .SPI_FREQ   (SPI_FREQ),
        .DATA_WIDTH (16)
    ) u_spi (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (spi_start),
        .data_in  (16'h0000),   // AD7476A has no MOSI data; transmit zeros
        .miso     (miso),
        .sclk     (sclk),
        .mosi     (mosi),
        .cs_n     (cs_n),
        .data_out (spi_rx),
        .done     (spi_done),
        .busy     (spi_busy)
    );

    // ── Result extraction ─────────────────────────────────────────────────────
    // AD7476A frame: {4'b0000, adc[11:0]} — extract lower 12 bits
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_data   <= '0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;
            if (spi_done) begin
                adc_data   <= spi_rx[11:0];
                data_valid <= 1'b1;
            end
        end
    end

endmodule
