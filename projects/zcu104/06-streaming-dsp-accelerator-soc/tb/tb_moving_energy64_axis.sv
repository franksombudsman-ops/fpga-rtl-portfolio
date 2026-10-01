`timescale 1ns/1ps

// ============================================================================
// Project 06 - Streaming DSP Accelerator SoC
// Self-checking verification for moving_energy64_axis
//
// Author: Frank Ouma
// ============================================================================

module tb_moving_energy64_axis;

    localparam integer MAX_SAMPLES = 4096;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;

    logic [15:0] s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    logic [63:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;

    logic [15:0] filtered_mem [0:MAX_SAMPLES-1];
    logic [36:0] energy_mem   [0:MAX_SAMPLES-1];

    integer output_count;
    integer expected_count;
    integer test_count;
    integer failure_count;

    logic case_running;

    logic [31:0] lfsr;

    logic        hold_active;
    logic [63:0] held_data;
    logic        held_last;

    string vector_root;
    string filtered_file;
    string energy_file;

    moving_energy64_axis dut (

        .aclk          (aclk),
        .aresetn       (aresetn),

        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),

        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast)
    );

    always #5 aclk = ~aclk;

    // ------------------------------------------------------------------------
    // Deterministic downstream backpressure.
    // ------------------------------------------------------------------------

    always @(negedge aclk) begin

        if (!aresetn) begin

            lfsr <= 32'hE6402026;
            m_axis_tready <= 1'b0;

        end
        else begin

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
    end

    // ------------------------------------------------------------------------
    // Scoreboard
    // ------------------------------------------------------------------------

    always @(posedge aclk) begin

        if (!aresetn) begin

            hold_active <= 1'b0;
            held_data   <= '0;
            held_last   <= 1'b0;

        end
        else begin

            // AXI stability under backpressure.
            if (hold_active) begin

                if (m_axis_tdata !== held_data) begin
                    $display(
                        "FAIL: output TDATA changed while stalled"
                    );

                    failure_count =
                        failure_count + 1;
                end

                if (m_axis_tlast !== held_last) begin
                    $display(
                        "FAIL: output TLAST changed while stalled"
                    );

                    failure_count =
                        failure_count + 1;
                end
            end

            if (m_axis_tvalid && !m_axis_tready) begin

                hold_active <= 1'b1;
                held_data   <= m_axis_tdata;
                held_last   <= m_axis_tlast;

            end
            else begin

                hold_active <= 1'b0;
            end

            if (
                case_running &&
                m_axis_tvalid &&
                m_axis_tready
            ) begin

                if (output_count >= expected_count) begin

                    $display(
                        "FAIL: unexpected output sample %0d",
                        output_count
                    );

                    failure_count =
                        failure_count + 1;

                end
                else begin

                    // Filtered sample must pass through unchanged.
                    if (
                        m_axis_tdata[15:0] !==
                        filtered_mem[output_count]
                    ) begin

                        $display(
                            "FAIL sample=%0d FILTER expected=%h actual=%h",
                            output_count,
                            filtered_mem[output_count],
                            m_axis_tdata[15:0]
                        );

                        failure_count =
                            failure_count + 1;
                    end

                    // Moving energy must match Python model bit-for-bit.
                    if (
                        m_axis_tdata[52:16] !==
                        energy_mem[output_count]
                    ) begin

                        $display(
                            "FAIL sample=%0d ENERGY expected=%h actual=%h",
                            output_count,
                            energy_mem[output_count],
                            m_axis_tdata[52:16]
                        );

                        failure_count =
                            failure_count + 1;
                    end

                    if (
                        m_axis_tlast !==
                        (output_count == expected_count-1)
                    ) begin

                        $display(
                            "FAIL: TLAST mismatch sample=%0d",
                            output_count
                        );

                        failure_count =
                            failure_count + 1;
                    end
                end

                output_count =
                    output_count + 1;
            end
        end
    end

    task automatic reset_dut;

        begin

            @(negedge aclk);

            aresetn       = 1'b0;
            s_axis_tvalid = 1'b0;
            s_axis_tdata  = '0;
            s_axis_tlast  = 1'b0;
            case_running  = 1'b0;

            repeat (6)
                @(posedge aclk);

            @(negedge aclk);
            aresetn = 1'b1;

            repeat (2)
                @(posedge aclk);
        end

    endtask

    task automatic run_case(
        input string case_name,
        input integer sample_count
    );

        integer n;
        integer accepted;
        integer timeout_cycles;
        integer failures_before;

        begin

            filtered_file = {
                vector_root,
                "/",
                case_name,
                "_fir_expected.hex"
            };

            energy_file = {
                vector_root,
                "/",
                case_name,
                "_energy_expected.hex"
            };

            $display("");
            $display("========================================");
            $display("CASE: %s", case_name);
            $display("Samples: %0d", sample_count);
            $display("========================================");

            $readmemh(
                filtered_file,
                filtered_mem,
                0,
                sample_count-1
            );

            $readmemh(
                energy_file,
                energy_mem,
                0,
                sample_count-1
            );

            reset_dut();

            output_count    = 0;
            expected_count  = sample_count;
            failures_before = failure_count;
            case_running    = 1'b1;

            for (
                n = 0;
                n < sample_count;
                n = n + 1
            ) begin

                // Deliberate source bubble.
                if ((n % 17) == 9) begin

                    @(negedge aclk);

                    s_axis_tvalid = 1'b0;
                    s_axis_tlast  = 1'b0;

                    @(posedge aclk);
                end

                @(negedge aclk);

                s_axis_tdata =
                    filtered_mem[n];

                s_axis_tvalid =
                    1'b1;

                s_axis_tlast =
                    (n == sample_count-1);

                accepted = 0;

                // AXI acceptance happens at rising clock edge.
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

            timeout_cycles = 0;

            while (
                output_count < sample_count &&
                timeout_cycles < 100000
            ) begin

                @(negedge aclk);

                timeout_cycles =
                    timeout_cycles + 1;
            end

            // Leave monitor active briefly to catch duplicate outputs.
            repeat (16)
                @(negedge aclk);

            if (output_count != sample_count) begin

                $display(
                    "FAIL: output count expected=%0d received=%0d",
                    sample_count,
                    output_count
                );

                failure_count =
                    failure_count + 1;
            end

            case_running = 1'b0;

            if (
                failure_count == failures_before &&
                output_count == sample_count
            ) begin

                $display(
                    "PASS: %s - %0d/%0d samples matched",
                    case_name,
                    output_count,
                    sample_count
                );

            end
            else begin

                $display(
                    "FAIL: %s - received=%0d expected=%0d new_errors=%0d",
                    case_name,
                    output_count,
                    sample_count,
                    failure_count - failures_before
                );
            end

            test_count =
                test_count + 1;

            repeat (5)
                @(posedge aclk);
        end

    endtask

    initial begin

        s_axis_tdata  = '0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;
        m_axis_tready = 1'b0;

        output_count   = 0;
        expected_count = 0;
        test_count     = 0;
        failure_count  = 0;
        case_running   = 1'b0;
        hold_active    = 1'b0;

        if (!$value$plusargs(
                "VECTOR_ROOT=%s",
                vector_root
            )) begin

            vector_root =
                "projects/zcu104/06-streaming-dsp-accelerator-soc/tb/vectors";
        end

        run_case(
            "impulse",
            128
        );

        run_case(
            "positive_step",
            192
        );

        run_case(
            "alternating_fullscale",
            256
        );

        run_case(
            "random",
            4096
        );

        $display("");
        $display("========================================");
        $display("PROJECT06 ENERGY64 VERIFICATION SUMMARY");
        $display("========================================");
        $display(
            "Golden-vector cases      : %0d",
            test_count
        );

        if (failure_count == 0) begin

            $display("Sample passthrough        : PASS");
            $display("64-sample moving energy   : PASS");
            $display("Startup zero history      : PASS");
            $display("4096 random samples       : PASS");
            $display("Random AXIS backpressure  : PASS");
            $display("Output stall stability    : PASS");
            $display("TLAST preservation        : PASS");
            $display("ENERGY64 RTL              : PASS");
            $display("TOTAL FAILURES            : 0");
            $display("========================================");

            $finish;

        end
        else begin

            $display("ENERGY64 RTL              : FAIL");

            $display(
                "TOTAL FAILURES            : %0d",
                failure_count
            );

            $display("========================================");

            $fatal(
                1,
                "PROJECT06 ENERGY64 VERIFICATION FAILED"
            );
        end
    end

endmodule
