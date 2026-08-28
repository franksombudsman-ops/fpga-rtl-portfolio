`timescale 1ns/1ps

module tb_soc_control_axi_irq;

    logic clk = 0;
    logic rst_n = 0;

    // AXI write address
    logic [31:0] awaddr = 0;
    logic        awvalid = 0;
    logic        awready;

    // AXI write data
    logic [31:0] wdata = 0;
    logic [3:0]  wstrb = 4'hF;
    logic        wvalid = 0;
    logic        wready;

    // AXI write response
    logic [1:0] bresp;
    logic       bvalid;
    logic       bready = 0;

    // AXI read address
    logic [31:0] araddr = 0;
    logic        arvalid = 0;
    logic        arready;

    // AXI read data
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready = 0;

    // Existing peripheral I/O
    logic        engine_enable;
    logic [11:0] threshold_high;
    logic [11:0] threshold_low;
    logic [7:0]  pwm_duty;

    logic        control_request = 0;
    logic        actuator_enable = 0;
    logic [1:0]  state_code = 0;
    logic        overrun = 0;
    logic [11:0] sensor_raw = 12'hA35;
    logic [11:0] sensor_filtered = 12'hA10;

    // Interrupt interface
    logic event_pulse = 0;
    logic irq_out;

    localparam [31:0] IRQ_ENABLE  = 32'h20;
    localparam [31:0] IRQ_STATUS  = 32'h24;
    localparam [31:0] IRQ_CLEAR   = 32'h28;
    localparam [31:0] EVENT_COUNT = 32'h2C;

    soc_control_axi_peripheral dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(rst_n),

        .s_axi_awaddr(awaddr),
        .s_axi_awvalid(awvalid),
        .s_axi_awready(awready),

        .s_axi_wdata(wdata),
        .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid),
        .s_axi_wready(wready),

        .s_axi_bresp(bresp),
        .s_axi_bvalid(bvalid),
        .s_axi_bready(bready),

        .s_axi_araddr(araddr),
        .s_axi_arvalid(arvalid),
        .s_axi_arready(arready),

        .s_axi_rdata(rdata),
        .s_axi_rresp(rresp),
        .s_axi_rvalid(rvalid),
        .s_axi_rready(rready),

        .engine_enable(engine_enable),
        .threshold_high(threshold_high),
        .threshold_low(threshold_low),
        .pwm_duty(pwm_duty),

        .control_request(control_request),
        .actuator_enable(actuator_enable),
        .state_code(state_code),
        .overrun(overrun),
        .sensor_raw(sensor_raw),
        .sensor_filtered(sensor_filtered),

        .event_pulse(event_pulse),
        .irq_out(irq_out)
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

            // Address/data accepted
            do @(posedge clk);
            while (!(awready && wready));

            @(negedge clk);
            awvalid = 1'b0;
            wvalid  = 1'b0;

            // Wait for response
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
                    "FAIL: %-35s actual=0x%08x expected=0x%08x",
                    name, actual, expected
                );
                $fatal;
            end
            else begin
                $display(
                    "PASS: %-35s 0x%08x",
                    name, actual
                );
            end
        end
    endtask


    logic [31:0] value;

    initial begin

        $display("");
        $display("==============================================");
        $display(" AXI-LITE INTERRUPT INTEGRATION VERIFICATION");
        $display("==============================================");
        $display("");

        // Reset
        repeat (4) @(posedge clk);

        @(negedge clk);
        rst_n = 1'b1;

        repeat (2) @(posedge clk);

        // --------------------------------------------------------
        // Reset-state register checks
        // --------------------------------------------------------

        axi_read(IRQ_ENABLE, value);
        check32("IRQ_ENABLE reset", value, 32'h0);

        axi_read(IRQ_STATUS, value);
        check32("IRQ_STATUS reset", value, 32'h0);

        axi_read(EVENT_COUNT, value);
        check32("EVENT_COUNT reset", value, 32'h0);


        // --------------------------------------------------------
        // Enable interrupt through AXI
        // --------------------------------------------------------

        axi_write(IRQ_ENABLE, 32'h1);

        axi_read(IRQ_ENABLE, value);
        check32("AXI enables interrupt", value, 32'h1);


        // --------------------------------------------------------
        // Generate FPGA event
        // --------------------------------------------------------

        @(negedge clk);
        event_pulse = 1'b1;

        @(negedge clk);
        event_pulse = 1'b0;

        repeat (2) @(posedge clk);

        axi_read(IRQ_STATUS, value);
        check32("Event sets IRQ_STATUS", value, 32'h1);

        check32(
            "irq_out asserted",
            {31'd0, irq_out},
            32'h1
        );

        axi_read(EVENT_COUNT, value);
        check32("EVENT_COUNT increments", value, 32'h1);


        // --------------------------------------------------------
        // Software acknowledges interrupt through AXI
        // --------------------------------------------------------

        axi_write(IRQ_CLEAR, 32'h1);

        // Allow W1C pulse to propagate into irq_controller.
        repeat (2) @(posedge clk);

        axi_read(IRQ_STATUS, value);
        check32("AXI IRQ_CLEAR clears pending", value, 32'h0);

        check32(
            "irq_out cleared",
            {31'd0, irq_out},
            32'h0
        );

        axi_read(IRQ_CLEAR, value);
        check32("IRQ_CLEAR reads zero", value, 32'h0);


        // --------------------------------------------------------
        // Masked-event retention
        // --------------------------------------------------------

        axi_write(IRQ_ENABLE, 32'h0);

        @(negedge clk);
        event_pulse = 1'b1;

        @(negedge clk);
        event_pulse = 1'b0;

        repeat (2) @(posedge clk);

        axi_read(IRQ_STATUS, value);
        check32("Masked event still pending", value, 32'h1);

        check32(
            "Masked event keeps irq_out low",
            {31'd0, irq_out},
            32'h0
        );

        axi_read(EVENT_COUNT, value);
        check32("Second event counted", value, 32'h2);


        // --------------------------------------------------------
        // Re-enable a pending interrupt
        // --------------------------------------------------------

        axi_write(IRQ_ENABLE, 32'h1);

        repeat (2) @(posedge clk);

        check32(
            "Re-enable exposes pending IRQ",
            {31'd0, irq_out},
            32'h1
        );

        axi_write(IRQ_CLEAR, 32'h1);

        repeat (2) @(posedge clk);

        axi_read(IRQ_STATUS, value);
        check32("Final IRQ clear", value, 32'h0);


        $display("");
        $display("==============================================");
        $display(" ALL AXI + INTERRUPT TESTS PASSED");
        $display("==============================================");
        $display("");

        $finish;
    end

endmodule
