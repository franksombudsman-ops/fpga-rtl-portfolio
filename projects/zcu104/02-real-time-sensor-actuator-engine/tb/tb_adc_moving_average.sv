`timescale 1ns/1ps

module tb_adc_moving_average;

    localparam int DATA_WIDTH = 12;

    logic clk;
    logic rst;

    logic [DATA_WIDTH-1:0] sample_in;
    logic                  sample_valid;

    logic [DATA_WIDTH-1:0] filtered_sample;
    logic                  filtered_valid;

    initial clk = 1'b0;
    always #4 clk = ~clk;   // 125 MHz

    adc_moving_average #(
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .sample_in       (sample_in),
        .sample_valid    (sample_valid),
        .filtered_sample (filtered_sample),
        .filtered_valid  (filtered_valid)
    );

    task automatic send_sample(
        input logic [DATA_WIDTH-1:0] value
    );
        begin
            @(negedge clk);
            sample_in    = value;
            sample_valid = 1'b1;

            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    initial begin

        rst          = 1'b1;
        sample_in    = '0;
        sample_valid = 1'b0;

        repeat (4) @(posedge clk);
        rst = 1'b0;

        // First four samples:
        // (1000 + 1010 + 990 + 1008) / 4 = 1002

        send_sample(12'd1000);
        send_sample(12'd1010);
        send_sample(12'd990);
        send_sample(12'd1008);

        // Check IMMEDIATELY after fourth sample.
        if (filtered_valid !== 1'b1)
            $error("FAIL: filtered_valid did not assert");
        else
            $display("PASS filtered_valid asserted on first window");

        if (filtered_sample !== 12'd1002)
            $error(
                "FAIL: expected 1002, received=%0d",
                filtered_sample
            );
        else
            $display(
                "PASS first window: filtered_sample=%0d",
                filtered_sample
            );

        // Fifth sample creates rolling window:
        // (1010 + 990 + 1008 + 1020) / 4 = 1007

        send_sample(12'd1020);

        if (filtered_valid !== 1'b1)
            $error("FAIL: filtered_valid missing on fifth sample");
        else
            $display("PASS filtered_valid asserted on rolling window");

        if (filtered_sample !== 12'd1007)
            $error(
                "FAIL: expected 1007, received=%0d",
                filtered_sample
            );
        else
            $display(
                "PASS rolling window: filtered_sample=%0d",
                filtered_sample
            );

        // One clock later filtered_valid must return LOW.
        @(posedge clk);
        #1;

        if (filtered_valid !== 1'b0)
            $error("FAIL: filtered_valid should be one clock wide");
        else
            $display("PASS filtered_valid is one clock wide");

        $display("PASS adc_moving_average verification complete");

        $finish;
    end

endmodule
