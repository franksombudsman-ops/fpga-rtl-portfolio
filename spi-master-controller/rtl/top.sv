// =============================================================================
// top.sv — Top-level integration wrapper for spi-master-controller
//
// Instantiates pmod_ad1_reader and wires its SPI bus and ADC result directly
// to top-level ports.  Intended for simulation and hardware deployment on the
// Arty A7 or Xilinx Kria KR260 (100 MHz PL clock from Zynq PS).
// =============================================================================

module top #(
    parameter int CLK_FREQ    = 100_000_000,
    parameter int SPI_FREQ    =   1_000_000,
    parameter int SAMPLE_RATE =        1000
) (
    input  logic        clk,
    input  logic        rst_n,

    // Pmod AD1 SPI signals
    output logic        sclk,
    output logic        mosi,
    input  logic        miso,
    output logic        cs_n,

    // ADC result
    output logic [11:0] adc_data,
    output logic        data_valid
);

    pmod_ad1_reader #(
        .CLK_FREQ    (CLK_FREQ),
        .SPI_FREQ    (SPI_FREQ),
        .SAMPLE_RATE (SAMPLE_RATE)
    ) u_reader (
        .clk        (clk),
        .rst_n      (rst_n),
        .sclk       (sclk),
        .mosi       (mosi),
        .cs_n       (cs_n),
        .miso       (miso),
        .adc_data   (adc_data),
        .data_valid (data_valid)
    );

endmodule
