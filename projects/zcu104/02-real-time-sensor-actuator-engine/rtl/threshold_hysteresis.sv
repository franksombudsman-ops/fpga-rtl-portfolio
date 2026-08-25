`timescale 1ns/1ps

module threshold_hysteresis #(
    parameter int DATA_WIDTH = 12,
    parameter logic [DATA_WIDTH-1:0] HIGH_THRESHOLD = 12'hC00,
    parameter logic [DATA_WIDTH-1:0] LOW_THRESHOLD  = 12'hB80
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic [DATA_WIDTH-1:0] sample_in,
    input  logic                  sample_valid,
    output logic                  control_request
);

always_ff @(posedge clk) begin
    if (rst) begin
        control_request <= 1'b0;
    end
    else if (sample_valid) begin
        if (!control_request && sample_in >= HIGH_THRESHOLD)
            control_request <= 1'b1;

        else if (control_request && sample_in <= LOW_THRESHOLD)
            control_request <= 1'b0;
    end
end

endmodule
