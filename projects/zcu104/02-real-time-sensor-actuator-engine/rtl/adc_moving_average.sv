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

    logic [2:0] sample_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            sample_0        <= '0;
            sample_1        <= '0;
            sample_2        <= '0;
            sample_count    <= '0;
            filtered_sample <= '0;
            filtered_valid  <= 1'b0;
        end else begin

            filtered_valid <= 1'b0;

            if (sample_valid) begin

                // Shift sample history
                sample_2 <= sample_1;
                sample_1 <= sample_0;
                sample_0 <= sample_in;

                // Count received samples until first complete window
                if (sample_count < 4)
                    sample_count <= sample_count + 1'b1;

                // Four-sample moving average:
                //
                // sample_in = newest sample
                // sample_0  = previous sample
                // sample_1  = previous-1
                // sample_2  = previous-2
                //
                // Extend each 12-bit sample to 14 bits before addition
                // to prevent overflow when summing four full-scale values.
                if (sample_count >= 3) begin

                    filtered_sample <= (
                          {2'b00, sample_in}
                        + {2'b00, sample_0}
                        + {2'b00, sample_1}
                        + {2'b00, sample_2}
                    ) >> 2;

                    filtered_valid <= 1'b1;
                end
            end
        end
    end

endmodule
