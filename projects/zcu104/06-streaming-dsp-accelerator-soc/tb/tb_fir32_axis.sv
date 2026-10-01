// Project 06 - Streaming DSP Accelerator SoC
// Self-checking FIR32 AXI4-Stream verification
//
// Author: Frank Ouma

`timescale 1ns/1ps

module tb_fir32_axis;

    localparam integer MAX_SAMPLES = 4096;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;

    logic [15:0] s_axis_tdata;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    logic [15:0] m_axis_tdata;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;

    logic [15:0] input_mem    [0:MAX_SAMPLES-1];
    logic [15:0] expected_mem [0:MAX_SAMPLES-1];

    integer output_count;
    integer expected_count;
    integer test_count;
    integer failure_count;

    logic case_running;

    logic [31:0] lfsr;

    logic        hold_active;
    logic [15:0] held_data;
    logic        held_last;

    string vector_root;
    string input_file;
    string expected_file;

    fir32_axis dut (
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

    // Deterministic pseudo-random output backpressure.
    always @(negedge aclk) begin
        if (!aresetn) begin
            lfsr <= 32'h06A62026;
            m_axis_tready <= 1'b0;
        end
        else begin
            lfsr <= {
                lfsr[30:0],
                lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]
            };

            // Roughly 75% ready.
            m_axis_tready <=
                lfsr[0] | lfsr[3];
        end
    end

    // Scoreboard and AXI stability checks.
    always @(posedge aclk) begin

        if (!aresetn) begin
            hold_active <= 1'b0;
            held_data   <= '0;
            held_last   <= 1'b0;
        end
        else begin

            // AXI invariant:
            // output data/TLAST must remain stable while VALID && !READY.
            if (hold_active) begin
                if (m_axis_tdata !== held_data) begin
                    $display(
                        "FAIL: TDATA changed while stalled. old=%h new=%h",
                        held_data,
                        m_axis_tdata
                    );
                    failure_count = failure_count + 1;
                end

                if (m_axis_tlast !== held_last) begin
                    $display(
                        "FAIL: TLAST changed while stalled."
                    );
                    failure_count = failure_count + 1;
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
                        "FAIL: unexpected extra output sample %0d",
                        output_count
                    );
                    failure_count = failure_count + 1;
                end

                if (
                    m_axis_tdata !==
                    expected_mem[output_count]
                ) begin
                    $display(
                        "FAIL sample=%0d expected=%h actual=%h",
                        output_count,
                        expected_mem[output_count],
                        m_axis_tdata
                    );
                    failure_count = failure_count + 1;
                end

                if (
                    m_axis_tlast !==
                    (output_count == expected_count-1)
                ) begin
                    $display(
                        "FAIL: TLAST mismatch sample=%0d",
                        output_count
                    );
                    failure_count = failure_count + 1;
                end

                output_count = output_count + 1;
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
        integer timeout_cycles;
        integer failures_before;
        integer accepted;

        begin

            input_file = {
                vector_root,
                "/",
                case_name,
                "_input.hex"
            };

            expected_file = {
                vector_root,
                "/",
                case_name,
                "_fir_expected.hex"
            };

            $display("");
            $display("========================================");
            $display("CASE: %s", case_name);
            $display("Samples: %0d", sample_count);
            $display("========================================");

            $readmemh(
                input_file,
                input_mem,
                0,
                sample_count-1
            );

            $readmemh(
                expected_file,
                expected_mem,
                0,
                sample_count-1
            );

            reset_dut();

            output_count   = 0;
            expected_count = sample_count;
            case_running   = 1'b1;
            failures_before = failure_count;

            for (n = 0; n < sample_count; n = n + 1) begin

                // Deliberate source-side bubble.
                if ((n % 13) == 7) begin
                    @(negedge aclk);
                    s_axis_tvalid = 1'b0;
                    s_axis_tlast  = 1'b0;

                    @(posedge aclk);
                end

                // Drive only on the falling edge so the values are
                // stable before the next rising-edge AXI transfer.
                @(negedge aclk);

                s_axis_tdata  = input_mem[n];
                s_axis_tvalid = 1'b1;
                s_axis_tlast  =
                    (n == sample_count-1);

                // An AXI transfer occurs ONLY on a rising edge where
                // TVALID && TREADY are simultaneously asserted.
                accepted = 0;

                while (!accepted) begin
                    @(posedge aclk);

                    if (s_axis_tvalid && s_axis_tready)
                        accepted = 1;
                end

                // Remove VALID only after the accepted rising edge.
                @(negedge aclk);

                s_axis_tvalid = 1'b0;
                s_axis_tlast  = 1'b0;
            end

            timeout_cycles = 0;

            while (
                (output_count < sample_count) &&
                (timeout_cycles < 100000)
            ) begin
                @(negedge aclk);
                timeout_cycles = timeout_cycles + 1;
            end

            // Keep the monitor alive briefly after the expected final
            // result. Any duplicated/spurious output is therefore caught.
            repeat (16)
                @(negedge aclk);

            if (output_count != sample_count) begin
                $display(
                    "FAIL: timeout. expected=%0d received=%0d",
                    sample_count,
                    output_count
                );
                failure_count = failure_count + 1;
            end

            case_running = 1'b0;

            if (
                (failure_count == failures_before) &&
                (output_count == sample_count)
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

            test_count = test_count + 1;

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

        run_case("impulse",               128);
        run_case("positive_step",         192);
        run_case("alternating_fullscale", 256);
        run_case("random",               4096);

        $display("");
        $display("========================================");
        $display("PROJECT06 FIR32 VERIFICATION SUMMARY");
        $display("========================================");
        $display("Golden-vector cases      : %0d", test_count);

        if (failure_count == 0) begin
            $display("Impulse response         : PASS");
            $display("Step response            : PASS");
            $display("Signed full-scale stream : PASS");
            $display("4096 random samples      : PASS");
            $display("Random AXIS backpressure : PASS");
            $display("Output stall stability   : PASS");
            $display("TLAST preservation       : PASS");
            $display("FIR32 RTL                : PASS");
            $display("TOTAL FAILURES           : 0");
            $display("========================================");
            $finish;
        end
        else begin
            $display("FIR32 RTL                : FAIL");
            $display("TOTAL FAILURES           : %0d", failure_count);
            $display("========================================");
            $fatal(1, "PROJECT06 FIR32 VERIFICATION FAILED");
        end
    end

endmodule
