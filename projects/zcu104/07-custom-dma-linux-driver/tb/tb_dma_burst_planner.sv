`timescale 1ns/1ps

module tb_dma_burst_planner;

    logic [39:0] current_addr;
    logic [31:0] bytes_remaining;
    logic [8:0]  max_burst_beats;

    logic        plan_valid;
    logic        plan_error;
    logic [39:0] burst_addr;
    logic [8:0]  burst_beats;
    logic [12:0] burst_bytes;
    logic [7:0]  axi_len;

    integer tests_run;
    integer offset;
    integer length_bytes;
    integer max_beats;

    dma_burst_planner dut (
        .current_addr     (current_addr),
        .bytes_remaining  (bytes_remaining),
        .max_burst_beats  (max_burst_beats),

        .plan_valid       (plan_valid),
        .plan_error       (plan_error),

        .burst_addr       (burst_addr),
        .burst_beats      (burst_beats),
        .burst_bytes      (burst_bytes),
        .axi_len          (axi_len)
    );

    task automatic check_case(
        input logic [39:0] addr,
        input logic [31:0] bytes,
        input logic [8:0]  max_burst
    );

        integer exp_beats;
        integer exp_boundary_bytes;
        integer exp_boundary_beats;
        integer exp_error;
        integer exp_valid;

        begin

            current_addr    = addr;
            bytes_remaining = bytes;
            max_burst_beats = max_burst;

            #1;

            tests_run = tests_run + 1;

            exp_error = 0;
            exp_valid = 0;
            exp_beats = 0;

            if (bytes == 0) begin
                exp_valid = 0;
            end
            else if ((addr & 40'h7) != 0) begin
                exp_error = 1;
            end
            else if ((bytes & 32'h7) != 0) begin
                exp_error = 1;
            end
            else if ((max_burst == 0) ||
                     (max_burst > 256)) begin
                exp_error = 1;
            end
            else begin

                exp_boundary_bytes =
                    4096 - (addr & 12'hFFF);

                exp_boundary_beats =
                    exp_boundary_bytes / 8;

                exp_beats =
                    bytes / 8;

                if (exp_beats > max_burst)
                    exp_beats = max_burst;

                if (exp_beats > exp_boundary_beats)
                    exp_beats = exp_boundary_beats;

                if (exp_beats == 0)
                    exp_error = 1;
                else
                    exp_valid = 1;
            end

            if (plan_error !== exp_error[0]) begin
                $display(
                    "FAIL error: addr=%h bytes=%0d max=%0d got=%b expected=%0d",
                    addr, bytes, max_burst,
                    plan_error, exp_error
                );
                $fatal;
            end

            if (plan_valid !== exp_valid[0]) begin
                $display(
                    "FAIL valid: addr=%h bytes=%0d max=%0d got=%b expected=%0d",
                    addr, bytes, max_burst,
                    plan_valid, exp_valid
                );
                $fatal;
            end

            if (exp_valid) begin

                if (burst_addr !== addr) begin
                    $display("FAIL burst address");
                    $fatal;
                end

                if (burst_beats !== exp_beats) begin
                    $display(
                        "FAIL beats: addr=%h bytes=%0d max=%0d got=%0d expected=%0d",
                        addr, bytes, max_burst,
                        burst_beats, exp_beats
                    );
                    $fatal;
                end

                if (burst_bytes !== (exp_beats * 8)) begin
                    $display("FAIL burst byte count");
                    $fatal;
                end

                if (axi_len !== (exp_beats - 1)) begin
                    $display("FAIL AXI LEN encoding");
                    $fatal;
                end

                /*
                 * Fundamental AXI 4-KiB boundary invariant.
                 */
                if ((addr[11:0] + burst_bytes) > 4096) begin
                    $display(
                        "FAIL: generated burst crosses 4-KiB boundary"
                    );
                    $fatal;
                end
            end
        end
    endtask


    initial begin

        tests_run = 0;

        current_addr     = 40'd0;
        bytes_remaining  = 32'd0;
        max_burst_beats  = 9'd0;

        #10;

        /* --------------------------------------------------
         * Directed basic tests
         * -------------------------------------------------- */

        check_case(40'h00001000, 32'd8,    9'd16);
        check_case(40'h00001000, 32'd64,   9'd16);
        check_case(40'h00001000, 32'd2048, 9'd256);

        $display("DIRECTED BASIC CASES: PASS");

        /* --------------------------------------------------
         * Maximum burst limiting
         * -------------------------------------------------- */

        check_case(40'h00002000, 32'd4096, 9'd1);
        check_case(40'h00002000, 32'd4096, 9'd4);
        check_case(40'h00002000, 32'd4096, 9'd16);
        check_case(40'h00002000, 32'd4096, 9'd64);
        check_case(40'h00002000, 32'd4096, 9'd256);

        $display("MAXIMUM BURST LIMITING: PASS");

        /* --------------------------------------------------
         * Explicit 4-KiB edge cases
         * -------------------------------------------------- */

        check_case(40'h00001FF8, 32'd64, 9'd16);
        check_case(40'h00001FF0, 32'd64, 9'd16);
        check_case(40'h00001FC0, 32'd512, 9'd256);

        $display("DIRECTED 4-KiB SPLITS: PASS");

        /* --------------------------------------------------
         * Exhaustively sweep every aligned position within
         * one 4-KiB page using multiple lengths/burst limits.
         * -------------------------------------------------- */

        for (offset = 0;
             offset < 4096;
             offset = offset + 8) begin

            check_case(
                40'h00010000 + offset,
                32'd8,
                9'd256
            );

            check_case(
                40'h00010000 + offset,
                32'd64,
                9'd16
            );

            check_case(
                40'h00010000 + offset,
                32'd2048,
                9'd256
            );

            check_case(
                40'h00010000 + offset,
                32'd8192,
                9'd256
            );

        end

        $display("4-KiB BOUNDARY SWEEP: PASS");

        /* --------------------------------------------------
         * Sweep different burst limits and transfer sizes.
         * -------------------------------------------------- */

        for (max_beats = 1;
             max_beats <= 256;
             max_beats = max_beats * 2) begin

            for (length_bytes = 8;
                 length_bytes <= 4096;
                 length_bytes = length_bytes * 2) begin

                check_case(
                    40'h00020000,
                    length_bytes,
                    max_beats
                );

            end
        end

        $display("BURST/LENGTH SWEEP: PASS");

        /* --------------------------------------------------
         * Invalid inputs
         * -------------------------------------------------- */

        check_case(40'h00001001, 32'd64, 9'd16);
        check_case(40'h00001000, 32'd15, 9'd16);
        check_case(40'h00001000, 32'd64, 9'd0);
        check_case(40'h00001000, 32'd64, 9'd257);

        /* zero remaining bytes = idle, not error */
        check_case(40'h00001000, 32'd0, 9'd16);

        $display("INVALID/IDLE CASES: PASS");

        $display("");
        $display("============================================");
        $display(" DMA BURST PLANNER: PASS");
        $display(" Tests executed: %0d", tests_run);
        $display(" 64-bit beat alignment      : PASS");
        $display(" AXI burst-length limiting  : PASS");
        $display(" 4-KiB boundary enforcement : PASS");
        $display(" AXI LEN encoding           : PASS");
        $display(" Invalid-input detection    : PASS");
        $display("============================================");

        $finish;
    end

endmodule
