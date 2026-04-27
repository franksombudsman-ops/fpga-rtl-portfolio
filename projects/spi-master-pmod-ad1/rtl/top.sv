// =============================================================================
// top.sv — SPI master / Pmod AD1 top-level integration (KR260)
//
// Samples the AD7476A 12-bit ADC on Pmod 2 (J3) at a rate controlled by a
// simple free-running timer.  The 12-bit result drives the lower 12 bits of
// the KR260 Pmod LEDs for a basic visual sanity-check during bring-up.
//
// Sample rate = CLK_HZ / SAMPLE_DIV  (default ≈ 1 kHz at 100 MHz)
// =============================================================================

module top #(
    parameter int CLK_HZ     = 100_000_000,
    parameter int SCLK_HZ    = 10_000_000,
    parameter int SAMPLE_DIV = 100_000      // 1 kHz sample rate
) (
    input  logic        clk,       // 100 MHz PL clock from Zynq PS
    input  logic        rst_n,     // active-low reset (Pmod button)

    // Pmod AD1 (J3) SPI signals
    output logic        ad_cs_n,   // chip-select (active-low)
    output logic        ad_sclk,   // SPI clock
    input  logic        ad_sdo,    // ADC serial data out → FPGA MISO

    // Debug: show top 3 ADC bits on Pmod 1 LEDs (reuse from project 1 header)
    output logic [2:0]  leds       // leds[2:0] = adc_data[11:9]
);

    // ── Sample-rate timer ─────────────────────────────────────────────────────
    localparam int TIMER_W = $clog2(SAMPLE_DIV);

    logic [TIMER_W-1:0] timer;
    logic               sample_req;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer      <= '0;
            sample_req <= 1'b0;
        end else begin
            sample_req <= 1'b0;
            if (timer == TIMER_W'(SAMPLE_DIV - 1)) begin
                timer      <= '0;
                sample_req <= 1'b1;
            end else begin
                timer <= timer + 1'b1;
            end
        end
    end

    // ── ADC controller ────────────────────────────────────────────────────────
    logic [11:0] adc_result;
    logic        adc_valid;

    pmod_ad1_ctrl #(
        .CLK_HZ  (CLK_HZ),
        .SCLK_HZ (SCLK_HZ)
    ) u_adc (
        .clk           (clk),
        .rst_n         (rst_n),
        .sample_req_i  (sample_req),
        .sample_valid_o(adc_valid),
        .adc_data_o    (adc_result),
        .spi_cs_n      (ad_cs_n),
        .spi_sclk      (ad_sclk),
        .spi_sdo       (ad_sdo)
    );

    // ── Result register + LED output ──────────────────────────────────────────
    logic [11:0] adc_hold;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)       adc_hold <= '0;
        else if (adc_valid) adc_hold <= adc_result;
    end

    // Top 3 bits give a coarse voltage indication across the 3 Pmod LEDs
    assign leds = adc_hold[11:9];

endmodule
