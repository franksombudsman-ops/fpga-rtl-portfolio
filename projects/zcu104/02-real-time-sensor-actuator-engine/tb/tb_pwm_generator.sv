`timescale 1ns/1ps

module tb_pwm_generator;

    localparam int TEST_DIVIDER = 4;
    localparam int PERIOD_CLOCKS = 256 * TEST_DIVIDER;

    logic clk = 1'b0;
    logic rst;
    logic enable;
    logic [7:0] duty;
    logic pwm_out;

    integer high_count;
    integer i;

    always #4 clk = ~clk;   // 125 MHz

    pwm_generator #(
        .PWM_DIVIDER(TEST_DIVIDER)
    ) dut (
        .clk     (clk),
        .rst     (rst),
        .enable  (enable),
        .duty    (duty),
        .pwm_out (pwm_out)
    );

    task automatic reset_pwm;
        begin
            rst = 1'b1;
            repeat (3) @(posedge clk);
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    task automatic measure_pwm(
        input logic test_enable,
        input logic [7:0] test_duty,
        input integer expected_high
    );
        begin
            enable = test_enable;
            duty   = test_duty;

            reset_pwm();

            high_count = 0;

            for (i = 0; i < PERIOD_CLOCKS; i = i + 1) begin
                @(posedge clk);
                #1;
                if (pwm_out)
                    high_count = high_count + 1;
            end

            if (high_count != expected_high)
                $fatal(1,
                    "FAIL: duty=%0d expected_high=%0d measured=%0d",
                    test_duty, expected_high, high_count);
        end
    endtask

    initial begin
        rst    = 1'b0;
        enable = 1'b0;
        duty   = 8'd0;

        measure_pwm(1'b0, 8'd153, 0);
        measure_pwm(1'b1, 8'd0, 0);

        // 153 × divider clock periods HIGH
        measure_pwm(1'b1, 8'd153, 153 * TEST_DIVIDER);

        // True 100%
        measure_pwm(1'b1, 8'hFF, PERIOD_CLOCKS);

        $display("PASS: divided PWM generator verification complete");
        $display("PWM period = %0d FPGA clocks", PERIOD_CLOCKS);
        $display("RUN duty = 153/256 = 59.77 percent");
        $display("STARTUP duty = 100 percent");

        $finish;
    end

endmodule
