`timescale 1ns/1ps

module adc_moving_average #(
    parameter int DATA_WIDTH = 12
)(
    input  logic                  clk,
    input  logic                  rst,

    input  logic [DATA_WIDTH-1:0] sample_in,
    input  logic                  sample_valid,

    output logic [DATA_WIDTH-1:0] filtered_sample,
    output logic                  filtered_valid
);

    logic [DATA_WIDTH-1:0] sample_0;
    logic [DATA_WIDTH-1:0] sample_1;
    logic [DATA_WIDTH-1:0] sample_2;
    logic [DATA_WIDTH-1:0] sample_3;

    logic [DATA_WIDTH+1:0] sum;

    logic [2:0] sample_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            sample_0        <= '0;
            sample_1        <= '0;
            sample_2        <= '0;
            sample_3        <= '0;
            sum             <= '0;
            sample_count    <= '0;
            filtered_sample <= '0;
            filtered_valid  <= 1'b0;
        end else begin

            filtered_valid <= 1'b0;

            if (sample_valid) begin

                sample_3 <= sample_2;
                sample_2 <= sample_1;
                sample_1 <= sample_0;
                sample_0 <= sample_in;

                if (sample_count < 4)
                    sample_count <= sample_count + 1'b1;

                if (sample_count >= 3) begin
                    sum <= sample_in
                         + sample_0
                         + sample_1
                         + sample_2;

                    filtered_sample <=
                        (sample_in
                         + sample_0
                         + sample_1
                         + sample_2) >> 2;

                    filtered_valid <= 1'b1;
                end
            end
        end
    end

endmodule
