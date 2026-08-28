`timescale 1ns/1ps

module tb_soc_control_axi_peripheral;

    logic clk;
    logic aresetn;

    logic [31:0] awaddr;
    logic        awvalid;
    logic        awready;

    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;

    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    logic [31:0] araddr;
    logic        arvalid;
    logic        arready;

    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    logic        engine_enable;
    logic [11:0] threshold_high;
    logic [11:0] threshold_low;
    logic [7:0]  pwm_duty;

    logic        control_request;
    logic        actuator_enable;
    logic [1:0]  state_code;
    logic        overrun;
    logic [11:0] sensor_raw;
    logic [11:0] sensor_filtered;

    logic [31:0] read_value;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------

    soc_control_axi_peripheral dut (
        .s_axi_aclk(clk),
        .s_axi_aresetn(aresetn),

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
        .sensor_filtered(sensor_filtered)
    );

    // ------------------------------------------------------------
    // 100 MHz AXI simulation clock
    // ------------------------------------------------------------

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // ------------------------------------------------------------
    // Self-check helper
    // ------------------------------------------------------------

    task automatic check32(
        input string name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        begin
            if (actual !== expected) begin
                $display("FAIL: %s", name);
                $display("      expected = 0x%08h", expected);
                $display("      actual   = 0x%08h", actual);
                $fatal(1);
            end
            else begin
                $display("PASS: %-35s 0x%08h", name, actual);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Independent AXI write-address channel
    // ------------------------------------------------------------

    task automatic send_aw(input logic [31:0] address);
        begin
            @(negedge clk);
            awaddr  = address;
            awvalid = 1'b1;

            @(posedge clk);
            while (!awready)
                @(posedge clk);

            @(negedge clk);
            awvalid = 1'b0;
        end
    endtask

    // ------------------------------------------------------------
    // Independent AXI write-data channel
    // ------------------------------------------------------------

    task automatic send_w(
        input logic [31:0] data,
        input logic [3:0]  strb
    );
        begin
            @(negedge clk);
            wdata  = data;
            wstrb  = strb;
            wvalid = 1'b1;

            @(posedge clk);
            while (!wready)
                @(posedge clk);

            @(negedge clk);
            wvalid = 1'b0;
        end
    endtask

    // ------------------------------------------------------------
    // AXI write transaction
    //
    // mode 0 = address and data together
    // mode 1 = address first
    // mode 2 = data first
    // ------------------------------------------------------------

    task automatic axi_write(
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [3:0]  strb,
        input integer      mode
    );
        begin

            case (mode)

                0: begin
                    fork
                        send_aw(address);
                        send_w(data, strb);
                    join
                end

                1: begin
                    send_aw(address);
                    repeat (2) @(posedge clk);
                    send_w(data, strb);
                end

                2: begin
                    send_w(data, strb);
                    repeat (2) @(posedge clk);
                    send_aw(address);
                end

                default: begin
                    $fatal(1, "Invalid AXI write mode");
                end

            endcase

            wait (bvalid === 1'b1);

            if (bresp !== 2'b00)
                $fatal(1, "AXI write response was not OKAY");

            @(negedge clk);
            bready = 1'b1;

            @(posedge clk);

            @(negedge clk);
            bready = 1'b0;

        end
    endtask

    // ------------------------------------------------------------
    // AXI read transaction
    // ------------------------------------------------------------

    task automatic axi_read(
        input  logic [31:0] address,
        output logic [31:0] data
    );
        begin

            @(negedge clk);
            araddr  = address;
            arvalid = 1'b1;

            @(posedge clk);
            while (!arready)
                @(posedge clk);

            @(negedge clk);
            arvalid = 1'b0;

            wait (rvalid === 1'b1);

            if (rresp !== 2'b00)
                $fatal(1, "AXI read response was not OKAY");

            data = rdata;

            @(negedge clk);
            rready = 1'b1;

            @(posedge clk);

            @(negedge clk);
            rready = 1'b0;

        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------

    initial begin

        awaddr  = 32'd0;
        awvalid = 1'b0;

        wdata   = 32'd0;
        wstrb   = 4'd0;
        wvalid  = 1'b0;

        bready  = 1'b0;

        araddr  = 32'd0;
        arvalid = 1'b0;

        rready  = 1'b0;

        // Simulated live hardware inputs
        control_request = 1'b1;
        actuator_enable = 1'b1;
        state_code       = 2'b10;
        overrun          = 1'b1;

        sensor_raw      = 12'hA35;
        sensor_filtered = 12'hA10;

        // --------------------------------------------------------
        // RESET
        // --------------------------------------------------------

        aresetn = 1'b0;

        repeat (4)
            @(posedge clk);

        @(negedge clk);
        aresetn = 1'b1;

        repeat (2)
            @(posedge clk);

        $display("");
        $display("==============================================");
        $display(" AXI-LITE CONTROL PERIPHERAL VERIFICATION");
        $display("==============================================");
        $display("");

        // --------------------------------------------------------
        // RESET VALUES
        // --------------------------------------------------------

        check32(
            "CONTROL reset",
            {31'd0, engine_enable},
            32'h0000_0000
        );

        check32(
            "THRESHOLD_HIGH reset",
            {20'd0, threshold_high},
            32'h0000_0C00
        );

        check32(
            "THRESHOLD_LOW reset",
            {20'd0, threshold_low},
            32'h0000_0B80
        );

        check32(
            "PWM_DUTY reset",
            {24'd0, pwm_duty},
            32'h0000_0099
        );

        // --------------------------------------------------------
        // WRITE: AW and W arrive together
        // --------------------------------------------------------

        axi_write(
            32'h0000_0000,
            32'h0000_0001,
            4'b1111,
            0
        );

        check32(
            "CONTROL simultaneous write",
            {31'd0, engine_enable},
            32'h0000_0001
        );

        // --------------------------------------------------------
        // WRITE: address arrives before data
        // --------------------------------------------------------

        axi_write(
            32'h0000_0008,
            32'h0000_0ABC,
            4'b1111,
            1
        );

        check32(
            "THRESHOLD_HIGH AW first",
            {20'd0, threshold_high},
            32'h0000_0ABC
        );

        // --------------------------------------------------------
        // WRITE: data arrives before address
        // --------------------------------------------------------

        axi_write(
            32'h0000_000C,
            32'h0000_0456,
            4'b1111,
            2
        );

        check32(
            "THRESHOLD_LOW W first",
            {20'd0, threshold_low},
            32'h0000_0456
        );

        // --------------------------------------------------------
        // PWM configuration
        // --------------------------------------------------------

        axi_write(
            32'h0000_0010,
            32'h0000_0055,
            4'b1111,
            0
        );

        check32(
            "PWM_DUTY write",
            {24'd0, pwm_duty},
            32'h0000_0055
        );

        // --------------------------------------------------------
        // BYTE STROBE TEST
        //
        // ABC -> A34
        // only byte lane 0 is modified
        // --------------------------------------------------------

        axi_write(
            32'h0000_0008,
            32'h0000_0034,
            4'b0001,
            0
        );

        check32(
            "WSTRB partial write",
            {20'd0, threshold_high},
            32'h0000_0A34
        );

        // --------------------------------------------------------
        // READBACK OF RW REGISTERS
        // --------------------------------------------------------

        axi_read(32'h0000_0000, read_value);
        check32(
            "Read CONTROL",
            read_value,
            32'h0000_0001
        );

        axi_read(32'h0000_0008, read_value);
        check32(
            "Read THRESHOLD_HIGH",
            read_value,
            32'h0000_0A34
        );

        axi_read(32'h0000_000C, read_value);
        check32(
            "Read THRESHOLD_LOW",
            read_value,
            32'h0000_0456
        );

        axi_read(32'h0000_0010, read_value);
        check32(
            "Read PWM_DUTY",
            read_value,
            32'h0000_0055
        );

        // --------------------------------------------------------
        // LIVE STATUS REGISTER
        //
        // overrun          = bit 4 = 1
        // state_code       = bits 3:2 = 10
        // actuator_enable  = bit 1 = 1
        // control_request  = bit 0 = 1
        //
        // expected = 0x1B
        // --------------------------------------------------------

        axi_read(32'h0000_0004, read_value);
        check32(
            "Read live STATUS",
            read_value,
            32'h0000_001B
        );

        // --------------------------------------------------------
        // SENSOR READBACK
        // --------------------------------------------------------

        axi_read(32'h0000_0014, read_value);
        check32(
            "Read SENSOR_RAW",
            read_value,
            32'h0000_0A35
        );

        axi_read(32'h0000_0018, read_value);
        check32(
            "Read SENSOR_FILTERED",
            read_value,
            32'h0000_0A10
        );

        // --------------------------------------------------------
        // VERSION
        // --------------------------------------------------------

        axi_read(32'h0000_001C, read_value);
        check32(
            "Read VERSION",
            read_value,
            32'h0001_0000
        );

        // --------------------------------------------------------
        // PROVE READ-ONLY REGISTER CANNOT BE MODIFIED
        // --------------------------------------------------------

        axi_write(
            32'h0000_0014,
            32'hDEAD_BEEF,
            4'b1111,
            0
        );

        axi_read(32'h0000_0014, read_value);
        check32(
            "SENSOR_RAW remains read-only",
            read_value,
            32'h0000_0A35
        );

        // --------------------------------------------------------
        // FINAL RESULT
        // --------------------------------------------------------

        $display("");
        $display("==============================================");
        $display(" ALL AXI-LITE TESTS PASSED");
        $display("==============================================");
        $display("");

        #20;
        $finish;

    end

endmodule
