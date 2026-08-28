`timescale 1ns/1ps

module pmod_ad1_model (
    input  logic        cs_n,
    input  logic        sclk,

    input  logic [11:0] adc_a,
    input  logic [11:0] adc_b,

    output logic        sdata_a,
    output logic        sdata_b
);

    logic [15:0] frame_a;
    logic [15:0] frame_b;
    integer bit_index;

    // AD1 frame = four leading zero bits + 12-bit ADC value.
    always @(negedge cs_n) begin
        frame_a = {4'b0000, adc_a};
        frame_b = {4'b0000, adc_b};

        bit_index = 15;

        sdata_a = frame_a[15];
        sdata_b = frame_b[15];
    end

    // Prepare the next bit while SCLK is low.
    // FPGA samples on the following rising edge.
    always @(negedge sclk) begin
        if (!cs_n && bit_index > 0) begin
            bit_index = bit_index - 1;
            sdata_a   = frame_a[bit_index];
            sdata_b   = frame_b[bit_index];
        end
    end

endmodule
