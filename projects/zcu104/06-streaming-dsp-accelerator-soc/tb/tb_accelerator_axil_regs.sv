`timescale 1ns/1ps

module tb_accelerator_axil_regs;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;

    logic [5:0]  s_axi_awaddr;
    logic        s_axi_awvalid;
    logic        s_axi_awready;

    logic [31:0] s_axi_wdata;
    logic [3:0]  s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;

    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;

    logic [5:0]  s_axi_araddr;
    logic        s_axi_arvalid;
    logic        s_axi_arready;

    logic [31:0] s_axi_rdata;
    logic [1:0]  s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    logic status_idle;
    logic status_input_active;
    logic status_output_active;

    logic sample_accepted;
    logic result_accepted;
    logic event_accepted;
    logic input_stall_cycle;
    logic output_stall_cycle;

    logic        cfg_enable;
    logic [36:0] cfg_energy_threshold;

    logic cfg_state_clear_pulse;
    logic cfg_counter_clear_pulse;

    integer failures;
    integer tests;

    integer state_clear_pulses;
    integer counter_clear_pulses;

    accelerator_axil_regs dut (

        .aclk(aclk),
        .aresetn(aresetn),

        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),

        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),

        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),

        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),

        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),

        .status_idle(status_idle),
        .status_input_active(status_input_active),
        .status_output_active(status_output_active),

        .sample_accepted(sample_accepted),
        .result_accepted(result_accepted),
        .event_accepted(event_accepted),
        .input_stall_cycle(input_stall_cycle),
        .output_stall_cycle(output_stall_cycle),

        .cfg_enable(cfg_enable),
        .cfg_energy_threshold(cfg_energy_threshold),

        .cfg_state_clear_pulse(cfg_state_clear_pulse),
        .cfg_counter_clear_pulse(cfg_counter_clear_pulse)
    );

    always #5 aclk = ~aclk;

    // ------------------------------------------------------------------------
    // Pulse monitoring
    // ------------------------------------------------------------------------

    always @(posedge aclk) begin

        if (!aresetn) begin

            state_clear_pulses   <= 0;
            counter_clear_pulses <= 0;

        end
        else begin

            if (cfg_state_clear_pulse)
                state_clear_pulses <=
                    state_clear_pulses + 1;

            if (cfg_counter_clear_pulse)
                counter_clear_pulses <=
                    counter_clear_pulses + 1;

        end
    end

    // ------------------------------------------------------------------------
    // Basic check helper
    // ------------------------------------------------------------------------

    task automatic check32(
        input string name,
        input logic [31:0] actual,
        input logic [31:0] expected
    );

        begin

            tests = tests + 1;

            if (actual !== expected) begin

                $display(
                    "FAIL: %s expected=%08h actual=%08h",
                    name,
                    expected,
                    actual
                );

                failures = failures + 1;

            end
            else begin

                $display(
                    "PASS: %s = %08h",
                    name,
                    actual
                );

            end
        end

    endtask

    // ------------------------------------------------------------------------
    // Independent AW channel
    // ------------------------------------------------------------------------

    task automatic send_aw(
        input logic [5:0] addr
    );

        integer accepted;

        begin

            @(negedge aclk);

            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;

            accepted = 0;

            while (!accepted) begin

                @(posedge aclk);

                if (
                    s_axi_awvalid &&
                    s_axi_awready
                )
                    accepted = 1;

            end

            @(negedge aclk);
            s_axi_awvalid = 1'b0;

        end

    endtask

    // ------------------------------------------------------------------------
    // Independent W channel
    // ------------------------------------------------------------------------

    task automatic send_w(
        input logic [31:0] data,
        input logic [3:0]  strb
    );

        integer accepted;

        begin

            @(negedge aclk);

            s_axi_wdata  = data;
            s_axi_wstrb  = strb;
            s_axi_wvalid = 1'b1;

            accepted = 0;

            while (!accepted) begin

                @(posedge aclk);

                if (
                    s_axi_wvalid &&
                    s_axi_wready
                )
                    accepted = 1;

            end

            @(negedge aclk);
            s_axi_wvalid = 1'b0;

        end

    endtask

    // ------------------------------------------------------------------------
    // Wait for write response
    // ------------------------------------------------------------------------

    task automatic wait_b;

        begin

            while (!s_axi_bvalid)
                @(negedge aclk);

            if (s_axi_bresp !== 2'b00) begin

                $display(
                    "FAIL: BRESP expected OKAY actual=%b",
                    s_axi_bresp
                );

                failures = failures + 1;

            end

            s_axi_bready = 1'b1;

            @(posedge aclk);
            @(negedge aclk);

            s_axi_bready = 1'b0;

        end

    endtask

    // ------------------------------------------------------------------------
    // Write variants
    // ------------------------------------------------------------------------

    task automatic axi_write_aw_first(
        input logic [5:0]  addr,
        input logic [31:0] data,
        input logic [3:0]  strb
    );

        begin

            send_aw(addr);

            repeat (3)
                @(posedge aclk);

            send_w(data, strb);

            wait_b();

        end

    endtask

    task automatic axi_write_w_first(
        input logic [5:0]  addr,
        input logic [31:0] data,
        input logic [3:0]  strb
    );

        begin

            send_w(data, strb);

            repeat (3)
                @(posedge aclk);

            send_aw(addr);

            wait_b();

        end

    endtask

    task automatic axi_write_together(
        input logic [5:0]  addr,
        input logic [31:0] data,
        input logic [3:0]  strb
    );

        begin

            fork
                send_aw(addr);
                send_w(data, strb);
            join

            wait_b();

        end

    endtask

    // ------------------------------------------------------------------------
    // AXI read
    // ------------------------------------------------------------------------

    task automatic axi_read(
        input  logic [5:0]  addr,
        output logic [31:0] data
    );

        integer accepted;

        begin

            @(negedge aclk);

            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;

            accepted = 0;

            while (!accepted) begin

                @(posedge aclk);

                if (
                    s_axi_arvalid &&
                    s_axi_arready
                )
                    accepted = 1;

            end

            @(negedge aclk);

            s_axi_arvalid = 1'b0;

            while (!s_axi_rvalid)
                @(negedge aclk);

            data = s_axi_rdata;

            if (s_axi_rresp !== 2'b00) begin

                $display(
                    "FAIL: RRESP expected OKAY actual=%b",
                    s_axi_rresp
                );

                failures = failures + 1;

            end

            s_axi_rready = 1'b1;

            @(posedge aclk);
            @(negedge aclk);

            s_axi_rready = 1'b0;

        end

    endtask

    task automatic expect_read(
        input logic [5:0]  addr,
        input logic [31:0] expected,
        input string       name
    );

        logic [31:0] value;

        begin

            axi_read(addr, value);

            check32(
                name,
                value,
                expected
            );

        end

    endtask

    // ------------------------------------------------------------------------
    // One-cycle telemetry pulse helpers
    // ------------------------------------------------------------------------

    task automatic pulse_sample;

        begin

            @(negedge aclk);
            sample_accepted = 1'b1;

            @(posedge aclk);
            @(negedge aclk);

            sample_accepted = 1'b0;

        end

    endtask

    task automatic pulse_result;

        begin

            @(negedge aclk);
            result_accepted = 1'b1;

            @(posedge aclk);
            @(negedge aclk);

            result_accepted = 1'b0;

        end

    endtask

    task automatic pulse_event;

        begin

            @(negedge aclk);
            event_accepted = 1'b1;

            @(posedge aclk);
            @(negedge aclk);

            event_accepted = 1'b0;

        end

    endtask

    task automatic pulse_input_stall;

        begin

            @(negedge aclk);
            input_stall_cycle = 1'b1;

            @(posedge aclk);
            @(negedge aclk);

            input_stall_cycle = 1'b0;

        end

    endtask

    task automatic pulse_output_stall;

        begin

            @(negedge aclk);
            output_stall_cycle = 1'b1;

            @(posedge aclk);
            @(negedge aclk);

            output_stall_cycle = 1'b0;

        end

    endtask

    // ------------------------------------------------------------------------
    // Main verification
    // ------------------------------------------------------------------------

    initial begin

        logic [31:0] value;
        integer pulses_before;

        failures = 0;
        tests    = 0;

        s_axi_awaddr  = '0;
        s_axi_awvalid = 1'b0;

        s_axi_wdata   = '0;
        s_axi_wstrb   = '0;
        s_axi_wvalid  = 1'b0;

        s_axi_bready  = 1'b0;

        s_axi_araddr  = '0;
        s_axi_arvalid = 1'b0;

        s_axi_rready  = 1'b0;

        status_idle          = 1'b1;
        status_input_active  = 1'b0;
        status_output_active = 1'b0;

        sample_accepted   = 1'b0;
        result_accepted   = 1'b0;
        event_accepted    = 1'b0;
        input_stall_cycle = 1'b0;
        output_stall_cycle = 1'b0;

        // ---------------------------------------------------------------
        // Reset
        // ---------------------------------------------------------------

        repeat (5)
            @(posedge aclk);

        @(negedge aclk);
        aresetn = 1'b1;

        repeat (3)
            @(posedge aclk);

        $display("");
        $display("============================================");
        $display("PROJECT06 AXI4-LITE REGISTER VERIFICATION");
        $display("============================================");

        // ---------------------------------------------------------------
        // Reset values
        // ---------------------------------------------------------------

        expect_read(
            6'h00,
            32'h00000000,
            "CONTROL reset"
        );

        expect_read(
            6'h08,
            32'h40000000,
            "THRESHOLD_LO reset"
        );

        expect_read(
            6'h0C,
            32'h00000000,
            "THRESHOLD_HI reset"
        );

        // ---------------------------------------------------------------
        // AW before W
        // Enable accelerator.
        // ---------------------------------------------------------------

        axi_write_aw_first(
            6'h00,
            32'h00000001,
            4'b0001
        );

        expect_read(
            6'h00,
            32'h00000001,
            "AW-before-W ENABLE"
        );

        // ---------------------------------------------------------------
        // Threshold write while enabled must be ignored.
        // ---------------------------------------------------------------

        axi_write_together(
            6'h08,
            32'h12345678,
            4'b1111
        );

        expect_read(
            6'h08,
            32'h40000000,
            "threshold protected while enabled"
        );

        // ---------------------------------------------------------------
        // STATE_CLEAR while enabled must be rejected.
        // ---------------------------------------------------------------

        pulses_before =
            state_clear_pulses;

        axi_write_together(
            6'h00,
            32'h00000003,
            4'b0001
        );

        repeat (3)
            @(posedge aclk);

        if (
            state_clear_pulses !=
            pulses_before
        ) begin

            $display(
                "FAIL: STATE_CLEAR accepted while enabled"
            );

            failures = failures + 1;

        end
        else begin

            $display(
                "PASS: STATE_CLEAR rejected while enabled"
            );

            tests = tests + 1;

        end

        // ---------------------------------------------------------------
        // W before AW
        // Disable accelerator.
        // ---------------------------------------------------------------

        axi_write_w_first(
            6'h00,
            32'h00000000,
            4'b0001
        );

        expect_read(
            6'h00,
            32'h00000000,
            "W-before-AW disable"
        );

        // ---------------------------------------------------------------
        // STATE_CLEAR while disabled but NOT idle must be rejected.
        // ---------------------------------------------------------------

        status_idle = 1'b0;

        pulses_before =
            state_clear_pulses;

        axi_write_together(
            6'h00,
            32'h00000002,
            4'b0001
        );

        repeat (3)
            @(posedge aclk);

        if (
            state_clear_pulses !=
            pulses_before
        ) begin

            $display(
                "FAIL: STATE_CLEAR accepted while not idle"
            );

            failures = failures + 1;

        end
        else begin

            $display(
                "PASS: STATE_CLEAR rejected while not idle"
            );

            tests = tests + 1;

        end

        // ---------------------------------------------------------------
        // Threshold while not idle must also be ignored.
        // ---------------------------------------------------------------

        axi_write_together(
            6'h08,
            32'h89ABCDEF,
            4'b1111
        );

        expect_read(
            6'h08,
            32'h40000000,
            "threshold protected while not idle"
        );

        // ---------------------------------------------------------------
        // Valid STATE_CLEAR:
        // disabled + idle.
        // ---------------------------------------------------------------

        status_idle = 1'b1;

        pulses_before =
            state_clear_pulses;

        axi_write_together(
            6'h00,
            32'h00000002,
            4'b0001
        );

        repeat (3)
            @(posedge aclk);

        if (
            state_clear_pulses ==
            pulses_before + 1
        ) begin

            $display(
                "PASS: valid STATE_CLEAR produced one pulse"
            );

            tests = tests + 1;

        end
        else begin

            $display(
                "FAIL: valid STATE_CLEAR pulse count expected=%0d actual=%0d",
                pulses_before + 1,
                state_clear_pulses
            );

            failures = failures + 1;

        end

        // ---------------------------------------------------------------
        // WSTRB test.
        //
        // Reset threshold low:
        //     0x40000000
        //
        // Write only byte 0:
        //     -> 0x400000AA
        // ---------------------------------------------------------------

        axi_write_together(
            6'h08,
            32'h000000AA,
            4'b0001
        );

        expect_read(
            6'h08,
            32'h400000AA,
            "WSTRB byte-0 threshold write"
        );

        // Write only byte 2:
        // 0x400000AA -> 0x405500AA

        axi_write_aw_first(
            6'h08,
            32'h00550000,
            4'b0100
        );

        expect_read(
            6'h08,
            32'h405500AA,
            "WSTRB byte-2 threshold write"
        );

        // High five threshold bits.

        axi_write_w_first(
            6'h0C,
            32'h00000015,
            4'b0001
        );

        expect_read(
            6'h0C,
            32'h00000015,
            "threshold high bits"
        );

        // High register WSTRB rejection.

        axi_write_together(
            6'h0C,
            32'h00000003,
            4'b0010
        );

        expect_read(
            6'h0C,
            32'h00000015,
            "threshold HI wrong-WSTRB ignored"
        );

        // ---------------------------------------------------------------
        // STATUS register
        // enabled=0, idle=1, input-active=1, output-active=1
        //
        // bits = 1110 = 0xE
        // ---------------------------------------------------------------

        status_input_active  = 1'b1;
        status_output_active = 1'b1;

        expect_read(
            6'h04,
            32'h0000000E,
            "STATUS encoding"
        );

        status_input_active  = 1'b0;
        status_output_active = 1'b0;

        // ---------------------------------------------------------------
        // Counter increments
        // ---------------------------------------------------------------

        pulse_sample();
        pulse_sample();

        pulse_result();

        pulse_event();
        pulse_event();
        pulse_event();

        pulse_input_stall();
        pulse_input_stall();
        pulse_input_stall();
        pulse_input_stall();

        pulse_output_stall();
        pulse_output_stall();
        pulse_output_stall();
        pulse_output_stall();
        pulse_output_stall();

        expect_read(
            6'h10,
            32'd2,
            "SAMPLE_COUNT"
        );

        expect_read(
            6'h14,
            32'd1,
            "RESULT_COUNT"
        );

        expect_read(
            6'h18,
            32'd3,
            "EVENT_COUNT"
        );

        expect_read(
            6'h1C,
            32'd4,
            "INPUT_STALL_COUNT"
        );

        expect_read(
            6'h20,
            32'd5,
            "OUTPUT_STALL_COUNT"
        );

        // ---------------------------------------------------------------
        // RO writes must do nothing.
        // ---------------------------------------------------------------

        axi_write_together(
            6'h10,
            32'hFFFFFFFF,
            4'b1111
        );

        expect_read(
            6'h10,
            32'd2,
            "RO SAMPLE_COUNT write ignored"
        );

        // ---------------------------------------------------------------
        // COUNTER_CLEAR
        // ---------------------------------------------------------------

        pulses_before =
            counter_clear_pulses;

        axi_write_together(
            6'h00,
            32'h00000004,
            4'b0001
        );

        repeat (3)
            @(posedge aclk);

        if (
            counter_clear_pulses ==
            pulses_before + 1
        ) begin

            $display(
                "PASS: COUNTER_CLEAR pulse"
            );

            tests = tests + 1;

        end
        else begin

            $display(
                "FAIL: COUNTER_CLEAR pulse"
            );

            failures = failures + 1;

        end

        expect_read(
            6'h10,
            32'd0,
            "SAMPLE_COUNT cleared"
        );

        expect_read(
            6'h14,
            32'd0,
            "RESULT_COUNT cleared"
        );

        expect_read(
            6'h18,
            32'd0,
            "EVENT_COUNT cleared"
        );

        expect_read(
            6'h1C,
            32'd0,
            "INPUT_STALL_COUNT cleared"
        );

        expect_read(
            6'h20,
            32'd0,
            "OUTPUT_STALL_COUNT cleared"
        );

        // ---------------------------------------------------------------
        // Explicit COUNTER_CLEAR precedence test.
        //
        // First create sample_count = 1.
        // Then assert sample_accepted during the exact internal clear
        // transaction. Clear must win.
        // ---------------------------------------------------------------

        pulse_sample();

        expect_read(
            6'h10,
            32'd1,
            "precedence setup SAMPLE_COUNT"
        );

        fork

            begin

                axi_write_together(
                    6'h00,
                    32'h00000004,
                    4'b0001
                );

            end

            begin

                wait (
                    dut.write_fire ===
                    1'b1
                );

                sample_accepted = 1'b1;

                @(posedge aclk);
                @(negedge aclk);

                sample_accepted = 1'b0;

            end

        join

        expect_read(
            6'h10,
            32'd0,
            "COUNTER_CLEAR precedence"
        );

        // ---------------------------------------------------------------
        // Reserved / unmapped reads return zero.
        // ---------------------------------------------------------------

        expect_read(
            6'h24,
            32'd0,
            "unmapped register"
        );

        $display("");
        $display("============================================");

        if (failures == 0) begin

            $display("AW before W                 : PASS");
            $display("W before AW                 : PASS");
            $display("AW/W together               : PASS");
            $display("WSTRB handling              : PASS");
            $display("RO protection               : PASS");
            $display("Threshold protection        : PASS");
            $display("STATE_CLEAR semantics       : PASS");
            $display("Telemetry counters          : PASS");
            $display("COUNTER_CLEAR precedence    : PASS");
            $display("Register readback           : PASS");
            $display("AXI4-LITE REGISTER BANK     : PASS");
            $display("TOTAL FAILURES              : 0");

        end
        else begin

            $display("AXI4-LITE REGISTER BANK     : FAIL");
            $display(
                "TOTAL FAILURES              : %0d",
                failures
            );

        end

        $display("============================================");

        if (failures != 0)
            $fatal(
                1,
                "AXI4-Lite register verification failed"
            );

        $finish;

    end

endmodule
