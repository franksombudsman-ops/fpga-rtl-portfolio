`timescale 1ns/1ps
module pmod_ad1_model #(
    parameter logic [11:0] SAMPLE_A = 12'hA35,
    parameter logic [11:0] SAMPLE_B = 12'h5C7
) (
    input  logic cs_n,
    input  logic sclk,

    output logic sdata_a,
    output logic sdata_b
);

    // Pmod AD1 transfer:
    // 4 leading zero bits + 12 ADC data bits.
    localparam logic [15:0] FRAME_A = {4'b0000, SAMPLE_A};
    localparam logic [15:0] FRAME_B = {4'b0000, SAMPLE_B};

    integer bit_index;

    initial begin
        bit_index = 15;
        sdata_a   = 1'b0;
        sdata_b   = 1'b0;
    end

    // CS falling starts a new ADC frame.
    // The first bit is made available before the first rising SCLK edge.
    always @(negedge cs_n) begin
        bit_index = 15;

        sdata_a <= FRAME_A[15];
        sdata_b <= FRAME_B[15];
    end

    // ADC advances to the next bit on each falling SCLK edge.
    always @(negedge sclk) begin
        if (!cs_n) begin
            if (bit_index > 0) begin
                bit_index = bit_index - 1;

                sdata_a <= FRAME_A[bit_index];
                sdata_b <= FRAME_B[bit_index];
            end
        end
    end

endmodule
