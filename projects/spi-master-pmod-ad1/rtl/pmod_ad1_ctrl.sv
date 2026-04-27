// =============================================================================
// pmod_ad1_ctrl.sv — Pmod AD1 controller (AD7476A, 12-bit SAR ADC)
//
// The AD7476A protocol:
//   - 16-bit SPI transfer (CS_N low for 16 SCLK cycles)
//   - Bit 15–14 : 0 (leading zeros after CS_N assertion)
//   - Bit 13    : NULL (first conversion bit, always 0)
//   - Bits 12–1 : 12-bit conversion result, MSB first
//   - Bit 0     : LSB repeated
//
// This module drives the SPI master and extracts [12:1] = the 12-bit result.
//
// sample_req_i : rising edge triggers one ADC conversion
// sample_valid_o : one-cycle pulse when adc_data_o is valid
// adc_data_o    : 12-bit unsigned ADC result (0 = 0 V, 4095 = Vref)
// =============================================================================

module pmod_ad1_ctrl #(
    parameter int CLK_HZ  = 100_000_000,   // system clock frequency
    parameter int SCLK_HZ = 10_000_000     // desired SPI clock (≤ 20 MHz for AD7476A)
) (
    input  logic        clk,
    input  logic        rst_n,

    // User interface
    input  logic        sample_req_i,    // pulse: start one conversion
    output logic        sample_valid_o,  // pulse: adc_data_o is valid
    output logic [11:0] adc_data_o,      // 12-bit ADC result

    // Pmod physical pins (AD7476A: no SDI / no MOSI needed)
    output logic        spi_cs_n,
    output logic        spi_sclk,
    input  logic        spi_sdo          // MISO from ADC
);

    // CLK_DIV = clk / (2 * SCLK_HZ) — halved because spi_master toggles
    // SCLK every CLK_DIV system clocks.
    localparam int CLK_DIV = CLK_HZ / (2 * SCLK_HZ);

    // ── SPI master ────────────────────────────────────────────────────────────
    logic [15:0] spi_rx;
    logic        spi_done;
    logic        spi_busy;

    spi_master #(
        .BITS    (16),
        .CLK_DIV (CLK_DIV)
    ) u_spi (
        .clk    (clk),
        .rst_n  (rst_n),
        .start_i(sample_req_i),
        .data_i (16'h0000),   // AD7476A has no MOSI data; drive zeros
        .data_o (spi_rx),
        .busy_o (spi_busy),
        .done_o (spi_done),
        .sclk_o (spi_sclk),
        .cs_n_o (spi_cs_n),
        .mosi_o (/* open */),
        .miso_i (spi_sdo)
    );

    // ── Result extraction ─────────────────────────────────────────────────────
    // AD7476A 16-bit frame layout:
    //   [15:14] = 00 (leading zeros)
    //   [13]    = NULL bit
    //   [12:1]  = 12-bit result (DB11..DB0)
    //   [0]     = repeated LSB
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_data_o    <= '0;
            sample_valid_o <= 1'b0;
        end else begin
            sample_valid_o <= 1'b0;   // default: one-cycle pulse
            if (spi_done) begin
                adc_data_o    <= spi_rx[12:1];
                sample_valid_o <= 1'b1;
            end
        end
    end

endmodule
