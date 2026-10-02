`timescale 1ns/1ps

module tb_dsp_accelerator_controlled;

    localparam integer NSAMPLES = 64;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;

    // AXI4-Lite
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

    // AXIS input
    logic [15:0] s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    // AXIS output
    logic [63:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;

    logic [15:0] input_mem  [0:127];
    logic [15:0] fir_mem    [0:127];
    logic [36:0] energy_mem [0:127];

    logic [36:0] expected_threshold;
    logic [36:0] expected_prev_energy;

    logic [31:0] rd_data;

    integer output_index;
    integer expected_outputs;
    integer expected_event_count;

    integer failures;
    integer tests;

    integer ready_mode;
    logic [31:0] lfsr;

    logic monitor_active;

    logic hold_active;
    logic [63:0] held_data;
    logic held_last;

    string vector_root;

    dsp_accelerator_controlled dut (

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

        .s_axis_tdata(s_axis_tdata),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),

        .m_axis_tdata(m_axis_tdata),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    always #5 aclk = ~aclk;

    // ------------------------------------------------------------------------
    // Output READY control
    //
    // 0 = blocked
    // 1 = always ready
    // 2 = deterministic randomized backpressure
    // ------------------------------------------------------------------------

    always @(negedge aclk) begin

        if (!aresetn) begin

            m_axis_tready <= 1'b0;
            lfsr <= 32'hC06A2026;

        end
        else begin

            case (ready_mode)

                0:
                    m_axis_tready <= 1'b0;

                1:
                    m_axis_tready <= 1'b1;

                default: begin

                    lfsr <= {
                        lfsr[30:0],
                        lfsr[31] ^
                        lfsr[21] ^
                        lfsr[1]  ^
                        lfsr[0]
                    };

                    m_axis_tready <=
                        lfsr[0] | lfsr[3];

                end
            endcase
        end
    end

    // ------------------------------------------------------------------------
    // Scoreboard
    // ------------------------------------------------------------------------

    always @(posedge aclk) begin

        if (!aresetn) begin

            hold_active = 1'b0;
            held_data   = 64'd0;
            held_last   = 1'b0;

        end
        else begin

            // AXI output must remain stable while stalled.

            if (hold_active) begin

                if (m_axis_tdata !== held_data) begin
                    $display("FAIL: output data changed while stalled");
                    failures = failures + 1;
                end

                if (m_axis_tlast !== held_last) begin
                    $display("FAIL: output TLAST changed while stalled");
                    failures = failures + 1;
                end
            end

            if (m_axis_tvalid && !m_axis_tready) begin

                hold_active = 1'b1;
                held_data   = m_axis_tdata;
                held_last   = m_axis_tlast;

            end
            else begin

                hold_active = 1'b0;

            end

            if (
                monitor_active &&
                m_axis_tvalid &&
                m_axis_tready
            ) begin

                if (output_index >= expected_outputs) begin

                    $display(
                        "FAIL: unexpected output index=%0d",
                        output_index
                    );

                    failures = failures + 1;

                end
                else begin

                    if (
                        m_axis_tdata[15:0] !==
                        fir_mem[output_index]
                    ) begin

                        $display(
                            "FAIL[%0d] FIR expected=%h actual=%h",
                            output_index,
                            fir_mem[output_index],
                            m_axis_tdata[15:0]
                        );

                        failures = failures + 1;

                    end

                    if (
                        m_axis_tdata[52:16] !==
                        energy_mem[output_index]
                    ) begin

                        $display(
                            "FAIL[%0d] ENERGY expected=%h actual=%h",
                            output_index,
                            energy_mem[output_index],
                            m_axis_tdata[52:16]
                        );

                        failures = failures + 1;

                    end

                    if (
                        m_axis_tdata[53] !==
                        (
                            (expected_prev_energy < expected_threshold) &&
                            (energy_mem[output_index] >= expected_threshold)
                        )
                    ) begin

                        $display(
                            "FAIL[%0d] EVENT expected=%0b actual=%0b",
                            output_index,
                            (
                                (expected_prev_energy < expected_threshold) &&
                                (energy_mem[output_index] >= expected_threshold)
                            ),
                            m_axis_tdata[53]
                        );

                        failures = failures + 1;

                    end

                    if (
                        (expected_prev_energy < expected_threshold) &&
                        (energy_mem[output_index] >= expected_threshold)
                    )
                        expected_event_count =
                            expected_event_count + 1;

                    expected_prev_energy =
                        energy_mem[output_index];

                    if (
                        m_axis_tlast !==
                        (output_index == expected_outputs - 1)
                    ) begin

                        $display(
                            "FAIL[%0d] TLAST mismatch",
                            output_index
                        );

                        failures = failures + 1;

                    end

                end

                output_index =
                    output_index + 1;

            end
        end
    end

    // ------------------------------------------------------------------------
    // Check helper
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
    // AXI4-Lite write
    // ------------------------------------------------------------------------

    task automatic axi_write(
        input logic [5:0]  addr,
        input logic [31:0] data
    );

        integer aw_done;
        integer w_done;

        begin

            @(negedge aclk);

            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;

            s_axi_wdata   = data;
            s_axi_wstrb   = 4'b1111;
            s_axi_wvalid  = 1'b1;

            aw_done = 0;
            w_done  = 0;

            while (!(aw_done && w_done)) begin

                @(posedge aclk);

                if (
                    !aw_done &&
                    s_axi_awvalid &&
                    s_axi_awready
                )
                    aw_done = 1;

                if (
                    !w_done &&
                    s_axi_wvalid &&
                    s_axi_wready
                )
                    w_done = 1;

                @(negedge aclk);

                if (aw_done)
                    s_axi_awvalid = 1'b0;

                if (w_done)
                    s_axi_wvalid = 1'b0;

            end

            while (!s_axi_bvalid)
                @(negedge aclk);

            if (s_axi_bresp !== 2'b00) begin
                $display("FAIL: BRESP=%b", s_axi_bresp);
                failures = failures + 1;
            end

            s_axi_bready = 1'b1;

            @(posedge aclk);
            @(negedge aclk);

            s_axi_bready = 1'b0;

        end

    endtask

    // ------------------------------------------------------------------------
    // AXI4-Lite read
    // ------------------------------------------------------------------------

    task automatic axi_read(
        input logic [5:0] addr,
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
                $display("FAIL: RRESP=%b", s_axi_rresp);
                failures = failures + 1;
            end

            s_axi_rready = 1'b1;

            @(posedge aclk);
            @(negedge aclk);

            s_axi_rready = 1'b0;

        end

    endtask

    // ------------------------------------------------------------------------
    // Program 37-bit threshold
    // ------------------------------------------------------------------------

    task automatic program_threshold(
        input logic [36:0] threshold
    );

        begin

            axi_write(
                6'h08,
                threshold[31:0]
            );

            axi_write(
                6'h0C,
                {
                    27'd0,
                    threshold[36:32]
                }
            );

            axi_read(6'h08, rd_data);

            check32(
                "threshold low readback",
                rd_data,
                threshold[31:0]
            );

            axi_read(6'h0C, rd_data);

            check32(
                "threshold high readback",
                rd_data,
                {
                    27'd0,
                    threshold[36:32]
                }
            );

        end

    endtask

    // ------------------------------------------------------------------------
    // Send samples 0 .. count-1
    // ------------------------------------------------------------------------

    task automatic send_samples(
        input integer count
    );

        integer n;
        integer accepted;

        begin

            for (n = 0; n < count; n = n + 1) begin

                @(negedge aclk);

                s_axis_tdata  = input_mem[n];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  = (n == count - 1);

                accepted = 0;

                while (!accepted) begin

                    @(posedge aclk);

                    if (
                        s_axis_tvalid &&
                        s_axis_tready
                    )
                        accepted = 1;

                end

                @(negedge aclk);

                s_axis_tvalid = 1'b0;
                s_axis_tlast  = 1'b0;

            end

        end

    endtask

    // ------------------------------------------------------------------------
    // Wait for all expected results
    // ------------------------------------------------------------------------

    task automatic wait_for_outputs;

        integer timeout;

        begin

            timeout = 0;

            while (
                output_index < expected_outputs &&
                timeout < 50000
            ) begin

                @(negedge aclk);
                timeout = timeout + 1;

            end

            if (output_index != expected_outputs) begin

                $display(
                    "FAIL: expected %0d outputs, received %0d",
                    expected_outputs,
                    output_index
                );

                failures = failures + 1;

            end
            else begin

                $display(
                    "PASS: %0d/%0d results verified",
                    output_index,
                    expected_outputs
                );

                tests = tests + 1;

            end

        end

    endtask

    // ------------------------------------------------------------------------
    // Poll STATUS.IDLE
    // ------------------------------------------------------------------------

    task automatic wait_for_idle;

        integer timeout;
        integer done;

        begin

            timeout = 0;
            done = 0;

            while (!done && timeout < 1000) begin

                axi_read(
                    6'h04,
                    rd_data
                );

                if (rd_data[1])
                    done = 1;

                timeout = timeout + 1;

            end

            if (!done) begin

                $display("FAIL: accelerator never reached IDLE");
                failures = failures + 1;

            end
            else begin

                $display("PASS: accelerator drained to IDLE");
                tests = tests + 1;

            end

        end

    endtask

    // ------------------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------------------

    initial begin

        integer i;

        failures = 0;
        tests = 0;

        ready_mode = 1;

        monitor_active = 1'b0;

        output_index = 0;
        expected_outputs = 0;
        expected_event_count = 0;

        expected_threshold = 37'd0;
        expected_prev_energy = 37'd0;

        s_axi_awaddr  = '0;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = '0;
        s_axi_wstrb   = '0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;

        s_axi_araddr  = '0;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;

        s_axis_tdata  = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        if (!$value$plusargs(
            "VECTOR_ROOT=%s",
            vector_root
        )) begin

            vector_root =
                "projects/zcu104/06-streaming-dsp-accelerator-soc/tb/vectors";

        end

        $readmemh(
            {vector_root, "/impulse_input.hex"},
            input_mem,
            0,
            127
        );

        $readmemh(
            {vector_root, "/impulse_fir_expected.hex"},
            fir_mem,
            0,
            127
        );

        $readmemh(
            {vector_root, "/impulse_energy_expected.hex"},
            energy_mem,
            0,
            127
        );

        // ---------------------------------------------------------------
        // Reset
        // ---------------------------------------------------------------

        repeat (6)
            @(posedge aclk);

        @(negedge aclk);
        aresetn = 1'b1;

        repeat (4)
            @(posedge aclk);

        $display("");
        $display("================================================");
        $display("PROJECT06 CONTROLLED ACCELERATOR VERIFICATION");
        $display("================================================");

        // Disabled + idle after reset.

        axi_read(6'h04, rd_data);

        if (
            rd_data[0] == 1'b0 &&
            rd_data[1] == 1'b1
        ) begin

            $display("PASS: reset state disabled + idle");
            tests = tests + 1;

        end
        else begin

            $display(
                "FAIL: reset STATUS=%08h",
                rd_data
            );

            failures = failures + 1;

        end

        // ---------------------------------------------------------------
        // Select a real non-zero threshold from the golden energy stream.
        // ---------------------------------------------------------------

        expected_threshold = 37'd0;

        for (i = 0; i < 128; i = i + 1) begin

            if (
                expected_threshold == 37'd0 &&
                energy_mem[i] != 37'd0
            )
                expected_threshold = energy_mem[i];

        end

        if (expected_threshold == 37'd0)
            $fatal(1, "No non-zero golden energy found");

        $display(
            "Selected programmable threshold = %0d",
            expected_threshold
        );

        program_threshold(expected_threshold);

        // Clean datapath and counters.

        axi_write(
            6'h00,
            32'h00000006
        );

        repeat (3)
            @(posedge aclk);

        // Enable.

        axi_write(
            6'h00,
            32'h00000001
        );

        // ---------------------------------------------------------------
        // CAMPAIGN A:
        // programmable threshold + drain-to-idle
        // ---------------------------------------------------------------

        output_index = 0;
        expected_outputs = NSAMPLES;
        expected_prev_energy = 37'd0;
        expected_event_count = 0;

        monitor_active = 1'b1;

        ready_mode = 1;

        send_samples(NSAMPLES);

        // Block output immediately after final accepted input so samples
        // remain in flight while software disables the accelerator.

        ready_mode = 0;

        repeat (3)
            @(posedge aclk);

        axi_write(
            6'h00,
            32'h00000000
        );

        // Disabled must reject new input.

        @(negedge aclk);
        s_axis_tdata  = 16'h1234;
        s_axis_tvalid = 1'b1;
        s_axis_tlast  = 1'b0;

        repeat (3)
            @(posedge aclk);

        if (!s_axis_tready) begin
            $display("PASS: disabled accelerator rejects new samples");
            tests = tests + 1;
        end
        else begin
            $display("FAIL: disabled accelerator asserted input READY");
            failures = failures + 1;
        end

        @(negedge aclk);
        s_axis_tvalid = 1'b0;

        // It should NOT yet be idle because results are intentionally blocked.

        axi_read(
            6'h04,
            rd_data
        );

        if (!rd_data[1]) begin
            $display("PASS: disabled accelerator reports draining");
            tests = tests + 1;
        end
        else begin
            $display("FAIL: IDLE asserted before pipeline drained");
            failures = failures + 1;
        end

        // Release output and allow all already-accepted samples to drain.

        ready_mode = 1;

        wait_for_idle();
        wait_for_outputs();

        monitor_active = 1'b0;

        // ---------------------------------------------------------------
        // Verify telemetry
        // ---------------------------------------------------------------

        axi_read(6'h10, rd_data);
        check32(
            "campaign-A SAMPLE_COUNT",
            rd_data,
            NSAMPLES
        );

        axi_read(6'h14, rd_data);
        check32(
            "campaign-A RESULT_COUNT",
            rd_data,
            NSAMPLES
        );

        axi_read(6'h18, rd_data);
        check32(
            "campaign-A EVENT_COUNT",
            rd_data,
            expected_event_count
        );

        axi_read(6'h1C, rd_data);

        if (rd_data >= 32'd3) begin

            $display(
                "PASS: INPUT_STALL_COUNT captured disabled-valid cycles (%0d)",
                rd_data
            );

            tests = tests + 1;

        end
        else begin

            $display(
                "FAIL: INPUT_STALL_COUNT expected >=3 actual=%0d",
                rd_data
            );

            failures = failures + 1;

        end

        axi_read(6'h20, rd_data);

        if (rd_data != 32'd0) begin

            $display(
                "PASS: OUTPUT_STALL_COUNT captured backpressure (%0d)",
                rd_data
            );

            tests = tests + 1;

        end
        else begin

            $display("FAIL: OUTPUT_STALL_COUNT remained zero");
            failures = failures + 1;

        end

        // ---------------------------------------------------------------
        // CAMPAIGN B:
        //
        // Clear DSP state + counters, program threshold=0, then rerun from
        // sample zero under randomized output backpressure.
        //
        // Exact crossing semantics require ZERO events at threshold=0:
        //
        // previous_energy < 0 is impossible for unsigned energy.
        // ---------------------------------------------------------------

        axi_write(
            6'h00,
            32'h00000006
        );

        repeat (3)
            @(posedge aclk);

        expected_threshold = 37'd0;

        program_threshold(
            expected_threshold
        );

        axi_write(
            6'h00,
            32'h00000001
        );

        output_index = 0;
        expected_outputs = NSAMPLES;
        expected_prev_energy = 37'd0;
        expected_event_count = 0;

        monitor_active = 1'b1;

        ready_mode = 2;

        send_samples(NSAMPLES);

        // Stop new work and drain.

        ready_mode = 0;

        axi_write(
            6'h00,
            32'h00000000
        );

        ready_mode = 1;

        wait_for_idle();
        wait_for_outputs();

        monitor_active = 1'b0;

        axi_read(6'h10, rd_data);
        check32(
            "campaign-B SAMPLE_COUNT",
            rd_data,
            NSAMPLES
        );

        axi_read(6'h14, rd_data);
        check32(
            "campaign-B RESULT_COUNT",
            rd_data,
            NSAMPLES
        );

        axi_read(6'h18, rd_data);
        check32(
            "threshold-zero EVENT_COUNT",
            rd_data,
            32'd0
        );

        // ---------------------------------------------------------------
        // Final result
        // ---------------------------------------------------------------

        $display("");
        $display("================================================");

        if (failures == 0) begin

            $display("AXI4-Lite configuration       : PASS");
            $display("Programmable threshold        : PASS");
            $display("FIR numerical equivalence     : PASS");
            $display("Energy numerical equivalence  : PASS");
            $display("Event crossing semantics      : PASS");
            $display("ENABLE gating                 : PASS");
            $display("Drain-to-IDLE                 : PASS");
            $display("STATE_CLEAR                   : PASS");
            $display("COUNTER_CLEAR                 : PASS");
            $display("Telemetry counters            : PASS");
            $display("Random output backpressure    : PASS");
            $display("CONTROLLED ACCELERATOR        : PASS");
            $display("TOTAL FAILURES                : 0");

        end
        else begin

            $display("CONTROLLED ACCELERATOR        : FAIL");
            $display(
                "TOTAL FAILURES                : %0d",
                failures
            );

        end

        $display("================================================");

        if (failures != 0)
            $fatal(
                1,
                "Controlled accelerator verification failed"
            );

        $finish;

    end

endmodule
