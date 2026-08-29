// ============================================================================
// Project: Project 04 - Interrupt-Driven Sensor Control SoC
// Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
// Author: Frank Ouma
// Engineering: FPGA / SoC / Digital Hardware Engineering
// Email: frankotieno254@gmail.com
// Contact: +254725582132
// Copyright (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

`timescale 1ns/1ps

module tb_soc_sensor_control_top;

    logic clk = 0;
    logic rst_n = 0;

    // AXI
    logic [31:0] awaddr = 0;
    logic        awvalid = 0;
    logic        awready;

    logic [31:0] wdata = 0;
    logic [3:0]  wstrb = 4'hF;
    logic        wvalid = 0;
    logic        wready;

    logic [1:0] bresp;
    logic       bvalid;
    logic       bready = 0;

    logic [31:0] araddr = 0;
    logic        arvalid = 0;
    logic        arready;

    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready = 0;

    // AD1 physical interface
    logic ad1_cs_n;
    logic ad1_sclk;
    logic ad1_sdata_a;
    logic ad1_sdata_b;

    logic [11:0] model_adc_a = 12'h400;
    logic [11:0] model_adc_b = 12'h200;

    logic actuator_pwm_out;
    logic irq_out;

    localparam CONTROL         = 32'h00;
    localparam STATUS          = 32'h04;
    localparam THRESHOLD_HIGH  = 32'h08;
    localparam THRESHOLD_LOW   = 32'h0C;
    localparam PWM_DUTY        = 32'h10;
    localparam SENSOR_RAW      = 32'h14;
    localparam SENSOR_FILTERED = 32'h18;
    localparam IRQ_ENABLE      = 32'h20;
    localparam IRQ_STATUS      = 32'h24;
    localparam IRQ_CLEAR       = 32'h28;
    localparam EVENT_COUNT     = 32'h2C;


    soc_sensor_control_top #(
        .CLK_FREQ_HZ    (100_000_000),
        .SAMPLE_RATE_HZ (100_000),
        .SCLK_FREQ_HZ   (10_000_000),

        // Accelerated only for simulation.
        .STARTUP_CYCLES (50),
        .PWM_DIVIDER    (2)
    ) dut (
        .s_axi_aclk          (clk),
        .s_axi_aresetn       (rst_n),

        .s_axi_awaddr        (awaddr),
        .s_axi_awvalid       (awvalid),
        .s_axi_awready       (awready),

        .s_axi_wdata         (wdata),
        .s_axi_wstrb         (wstrb),
        .s_axi_wvalid        (wvalid),
        .s_axi_wready        (wready),

        .s_axi_bresp         (bresp),
        .s_axi_bvalid        (bvalid),
        .s_axi_bready        (bready),

        .s_axi_araddr        (araddr),
        .s_axi_arvalid       (arvalid),
        .s_axi_arready       (arready),

        .s_axi_rdata         (rdata),
        .s_axi_rresp         (rresp),
        .s_axi_rvalid        (rvalid),
        .s_axi_rready        (rready),

        .ad1_cs_n            (ad1_cs_n),
        .ad1_sclk            (ad1_sclk),
        .ad1_sdata_a         (ad1_sdata_a),
        .ad1_sdata_b         (ad1_sdata_b),

        .actuator_pwm_out    (actuator_pwm_out),
        .irq_out             (irq_out)
    );


    pmod_ad1_model adc_model (
        .cs_n    (ad1_cs_n),
        .sclk    (ad1_sclk),

        .adc_a   (model_adc_a),
        .adc_b   (model_adc_b),

        .sdata_a (ad1_sdata_a),
        .sdata_b (ad1_sdata_b)
    );


    always #5 clk = ~clk; // 100 MHz


    task automatic axi_write(
        input logic [31:0] addr,
        input logic [31:0] data
    );
        begin
            @(negedge clk);

            awaddr  = addr;
            awvalid = 1'b1;

            wdata   = data;
            wstrb   = 4'hF;
            wvalid  = 1'b1;

            bready  = 1'b1;

            do @(posedge clk);
            while (!(awready && wready));

            @(negedge clk);
            awvalid = 1'b0;
            wvalid  = 1'b0;

            wait (bvalid === 1'b1);

            @(posedge clk);
            @(negedge clk);

            bready = 1'b0;
        end
    endtask


    task automatic axi_read(
        input  logic [31:0] addr,
        output logic [31:0] data
    );
        begin
            @(negedge clk);

            araddr  = addr;
            arvalid = 1'b1;
            rready  = 1'b1;

            do @(posedge clk);
            while (!arready);

            @(negedge clk);
            arvalid = 1'b0;

            wait (rvalid === 1'b1);
            #1 data = rdata;

            @(posedge clk);
            @(negedge clk);

            rready = 1'b0;
        end
    endtask


    task automatic check32(
        input string name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        begin
            if (actual !== expected) begin
                $display(
                    "FAIL: %-38s actual=0x%08x expected=0x%08x",
                    name, actual, expected
                );
                $fatal;
            end
            else
                $display(
                    "PASS: %-38s 0x%08x",
                    name, actual
                );
        end
    endtask


    logic [31:0] value;

    initial begin

        $display("");
        $display("================================================");
        $display(" LIVE SENSOR -> AXI -> IRQ -> ACTUATOR TEST");
        $display("================================================");
        $display("");

        // Reset
        repeat (5) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        // Software configuration
        axi_write(THRESHOLD_HIGH, 32'h0000_0900);
        axi_write(THRESHOLD_LOW,  32'h0000_0700);
        axi_write(PWM_DUTY,       32'h0000_0055);
        axi_write(IRQ_ENABLE,     32'h0000_0001);
        axi_write(CONTROL,        32'h0000_0001);

        $display("PASS: ARM-style AXI configuration complete");

        // Allow low ADC values to populate moving-average filter.
        repeat (8) @(posedge dut.filtered_valid);

        axi_read(SENSOR_RAW, value);
        check32("Low live SENSOR_RAW", value, 32'h0000_0400);

        axi_read(IRQ_STATUS, value);
        check32("No IRQ below threshold", value, 32'h0);


        // --------------------------------------------------------
        // Physical-equivalent ADC rises above HIGH threshold.
        // --------------------------------------------------------

        $display("");
        $display("ADC stimulus -> ABOVE HIGH threshold");
        model_adc_a = 12'hA00;

        wait (irq_out === 1'b1);

        axi_read(IRQ_STATUS, value);
        check32("High crossing raises IRQ_STATUS", value, 32'h1);

        axi_read(EVENT_COUNT, value);
        check32("High crossing event count", value, 32'h1);

        // Wait until actuator reaches RUN.
        wait (dut.state_code == 2'b10);

        axi_read(STATUS, value);
        check32("RUN status after high crossing", value, 32'h0000_000B);

        if (dut.pwm_duty_actual !== 8'h55) begin
            $display("FAIL: AXI PWM duty not applied to FSM");
            $fatal;
        end

        $display("PASS: AXI PWM command applied to actuator 0x55");

        // Prove PWM physically toggles.
        @(posedge actuator_pwm_out);
        @(negedge actuator_pwm_out);

        $display("PASS: actuator PWM is switching");

        // Software acknowledges first interrupt.
        axi_write(IRQ_CLEAR, 32'h1);
        wait (irq_out === 1'b0);

        $display("PASS: software cleared first interrupt");


        // --------------------------------------------------------
        // ADC falls below LOW threshold.
        // --------------------------------------------------------

        $display("");
        $display("ADC stimulus -> BELOW LOW threshold");
        model_adc_a = 12'h600;

        wait (irq_out === 1'b1);

        axi_read(EVENT_COUNT, value);
        check32("Low crossing event count", value, 32'h2);

        // Allow FSM to return OFF.
        wait (dut.state_code == 2'b00);
        repeat (2) @(posedge clk);

        axi_read(STATUS, value);
        check32("OFF status after low crossing", value, 32'h0);

        if (actuator_pwm_out !== 1'b0) begin
            $display("FAIL: PWM should be LOW when actuator is OFF");
            $fatal;
        end

        $display("PASS: physical actuator output disabled");

        axi_write(IRQ_CLEAR, 32'h1);
        wait (irq_out === 1'b0);

        $display("");
        $display("================================================");
        $display(" ALL LIVE SENSOR SOC TESTS PASSED");
        $display("================================================");
        $display("");

        $finish;
    end

endmodule
