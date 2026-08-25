`timescale 1ns/1ps

module tb_actuator_control_fsm;

    logic clk = 0;
    logic rst;
    logic control_request;

    logic       actuator_enable;
    logic [7:0] pwm_duty;
    logic [1:0] state_code;

    always #4 clk = ~clk;   // 125 MHz

    actuator_control_fsm #(
        .STARTUP_CYCLES (4),
        .RUN_DUTY       (8'd153)
    ) dut (
        .clk             (clk),
        .rst             (rst),
        .control_request (control_request),
        .actuator_enable (actuator_enable),
        .pwm_duty        (pwm_duty),
        .state_code      (state_code)
    );

    initial begin
        rst             = 1'b1;
        control_request = 1'b0;

        repeat (3) @(posedge clk);
        rst = 1'b0;

        @(posedge clk);
        #1;
        if (state_code !== 2'b00 ||
            actuator_enable !== 1'b0 ||
            pwm_duty !== 8'd0)
            $fatal(1, "FAIL: OFF state");

        control_request = 1'b1;

        @(posedge clk);
        #1;
        if (state_code !== 2'b01 ||
            actuator_enable !== 1'b1 ||
            pwm_duty !== 8'hFF)
            $fatal(1, "FAIL: STARTUP state");

        wait (state_code == 2'b10);
        #1;

        if (actuator_enable !== 1'b1 ||
            pwm_duty !== 8'd153)
            $fatal(1, "FAIL: RUN state");

        control_request = 1'b0;

        @(posedge clk);
        #1;
        if (state_code !== 2'b00 ||
            actuator_enable !== 1'b0 ||
            pwm_duty !== 8'd0)
            $fatal(1, "FAIL: return to OFF");

        $display("PASS: actuator control FSM verification complete");
        $finish;
    end

endmodule
