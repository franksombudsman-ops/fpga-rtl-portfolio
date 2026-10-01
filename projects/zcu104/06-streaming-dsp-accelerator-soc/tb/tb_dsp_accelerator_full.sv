`timescale 1ns/1ps

module tb_dsp_accelerator_full;

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

    logic [15:0] input_mem  [0:MAX_SAMPLES-1];
    logic [15:0] fir_mem    [0:MAX_SAMPLES-1];
    logic [36:0] energy_mem [0:MAX_SAMPLES-1];
    logic        event_mem  [0:MAX_SAMPLES-1];

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
    string input_file;
    string fir_file;
    string energy_file;
    string event_file;

    dsp_accelerator_full dut (

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

    function automatic logic expected_tlast(
        input integer index,
        input integer count
    );

        integer b1;
        integer b2;

        begin

            b1 = (count / 3) - 1;
            b2 = ((2 * count) / 3) - 1;

            expected_tlast =
                (index == b1) ||
                (index == b2) ||
                (index == count - 1);

        end

    endfunction

    always @(negedge aclk) begin

        if (!aresetn) begin

            lfsr <= 32'hE6E62026;
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

    always @(posedge aclk) begin

        if (!aresetn) begin

            hold_active <= 1'b0;
            held_data   <= '0;
            held_last   <= 1'b0;

        end
        else begin

            if (hold_active) begin

                if (m_axis_tdata !== held_data) begin
                    $display(
                        "FAIL: output changed while stalled"
                    );
                    failure_count =
                        failure_count + 1;
                end

                if (m_axis_tlast !== held_last) begin
                    $display(
                        "FAIL: TLAST changed while stalled"
                    );
                    failure_count =
                        failure_count + 1;
                end
            end

            if (
                m_axis_tvalid &&
                !m_axis_tready
            ) begin

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

                if (
                    output_count >=
                    expected_count
                ) begin

                    $display(
                        "FAIL: unexpected output %0d",
                        output_count
                    );

                    failure_count =
                        failure_count + 1;

                end
                else begin

                    if (
                        m_axis_tdata[15:0] !==
                        fir_mem[output_count]
                    ) begin

                        $display(
                            "FAIL sample=%0d FIR expected=%h actual=%h",
                            output_count,
                            fir_mem[output_count],
                            m_axis_tdata[15:0]
                        );

                        failure_count =
                            failure_count + 1;
                    end

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
                        m_axis_tdata[53] !==
                        event_mem[output_count]
                    ) begin

                        $display(
                            "FAIL sample=%0d EVENT expected=%0b actual=%0b",
                            output_count,
                            event_mem[output_count],
                            m_axis_tdata[53]
                        );

                        failure_count =
                            failure_count + 1;
                    end

                    if (
                        m_axis_tlast !==
                        expected_tlast(
                            output_count,
                            expected_count
                        )
                    ) begin

                        $display(
                            "FAIL sample=%0d TLAST mismatch",
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

            repeat (8)
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

            input_file = {
                vector_root,
                "/",
                case_name,
                "_input.hex"
            };

            fir_file = {
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

            event_file = {
                vector_root,
                "/",
                case_name,
                "_event_expected.hex"
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
                fir_file,
                fir_mem,
                0,
                sample_count-1
            );

            $readmemh(
                energy_file,
                energy_mem,
                0,
                sample_count-1
            );

            $readmemh(
                event_file,
                event_mem,
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

                if ((n % 19) == 11) begin

                    @(negedge aclk);

                    s_axis_tvalid = 1'b0;
                    s_axis_tlast  = 1'b0;

                    @(posedge aclk);

                end

                @(negedge aclk);

                s_axis_tdata =
                    input_mem[n];

                s_axis_tvalid =
                    1'b1;

                s_axis_tlast =
                    expected_tlast(
                        n,
                        sample_count
                    );

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

            timeout_cycles = 0;

            while (
                output_count < sample_count &&
                timeout_cycles < 150000
            ) begin

                @(negedge aclk);

                timeout_cycles =
                    timeout_cycles + 1;

            end

            repeat (24)
                @(negedge aclk);

            if (
                output_count !=
                sample_count
            ) begin

                $display(
                    "FAIL: count expected=%0d received=%0d",
                    sample_count,
                    output_count
                );

                failure_count =
                    failure_count + 1;

            end

            case_running = 1'b0;

            if (
                failure_count ==
                    failures_before &&
                output_count ==
                    sample_count
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
                    "FAIL: %s - received=%0d expected=%0d errors=%0d",
                    case_name,
                    output_count,
                    sample_count,
                    failure_count -
                        failures_before
                );

            end

            test_count =
                test_count + 1;

            repeat (6)
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

        case_running = 1'b0;
        hold_active  = 1'b0;

        if (!$value$plusargs(
                "VECTOR_ROOT=%s",
                vector_root
            )) begin

            vector_root =
                "projects/zcu104/06-streaming-dsp-accelerator-soc/tb/vectors";

        end

        run_case("impulse", 128);
        run_case("positive_step", 192);
        run_case("alternating_fullscale", 256);
        run_case("random", 4096);

        $display("");
        $display("================================================");
        $display("PROJECT06 FULL ACCELERATOR VERIFICATION");
        $display("================================================");

        if (failure_count == 0) begin

            $display("FIR32                    : PASS");
            $display("Moving energy            : PASS");
            $display("Threshold event          : PASS");
            $display("End-to-end numerical     : PASS");
            $display("Random backpressure      : PASS");
            $display("Multiple TLAST           : PASS");
            $display("Continuous DSP state     : PASS");
            $display("FULL ACCELERATOR         : PASS");
            $display("TOTAL FAILURES           : 0");
            $display("================================================");

            $finish;

        end
        else begin

            $display("FULL ACCELERATOR         : FAIL");

            $display(
                "TOTAL FAILURES           : %0d",
                failure_count
            );

            $display("================================================");

            $fatal(
                1,
                "PROJECT06 FULL ACCELERATOR FAILED"
            );

        end
    end

endmodule
