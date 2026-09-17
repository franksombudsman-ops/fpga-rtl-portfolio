`timescale 1ns/1ps

/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 * AD1 AXI4-Stream packetizer regression test.
 *
 * Validates:
 *   - ADC sample packing
 *   - AXI4-Stream framing
 *   - TVALID/TREADY backpressure behavior
 *   - dropped-sample accounting
 *   - sticky overflow indication
 *   - recovery after backpressure
 */

module tb_ad1_axis_packetizer;

    reg         aclk = 0;
    reg         aresetn = 0;

    reg [11:0]  sample_a = 0;
    reg [11:0]  sample_b = 0;
    reg         sample_valid = 0;

    wire [31:0] m_axis_tdata;
    wire [3:0]  m_axis_tkeep;
    wire        m_axis_tvalid;
    reg         m_axis_tready = 0;
    wire        m_axis_tlast;

    wire [31:0] sample_drop_count;
    wire        overflow_sticky;

    always #20 aclk = ~aclk;   // 25 MHz

    ad1_axis_packetizer dut (
        .aclk               (aclk),
        .aresetn            (aresetn),

        .sample_a            (sample_a),
        .sample_b            (sample_b),
        .sample_valid        (sample_valid),

        .m_axis_tdata        (m_axis_tdata),
        .m_axis_tkeep        (m_axis_tkeep),
        .m_axis_tvalid       (m_axis_tvalid),
        .m_axis_tready       (m_axis_tready),
        .m_axis_tlast        (m_axis_tlast),

        .sample_drop_count   (sample_drop_count),
        .overflow_sticky     (overflow_sticky)
    );


    task pulse_sample(
        input [11:0] a,
        input [11:0] b
    );
    begin
        @(negedge aclk);

        sample_a     = a;
        sample_b     = b;
        sample_valid = 1'b1;

        @(negedge aclk);

        sample_valid = 1'b0;
    end
    endtask


    task expect_transfer(
        input [31:0] expected_data,
        input        expected_last
    );
    begin

        @(posedge aclk);

        while (!(m_axis_tvalid && m_axis_tready))
            @(posedge aclk);

        if (m_axis_tdata !== expected_data) begin
            $display(
                "FAIL: expected %08h, received %08h",
                expected_data,
                m_axis_tdata
            );
            $fatal;
        end

        if (m_axis_tlast !== expected_last) begin
            $display("FAIL: TLAST mismatch");
            $fatal;
        end

        if (m_axis_tkeep !== 4'hF) begin
            $display("FAIL: TKEEP mismatch");
            $fatal;
        end

        /*
         * Allow DUT nonblocking assignments to settle before
         * the caller evaluates the next AXI state.
         */
        #1;

    end
    endtask


    initial begin

        // -------------------------------------------------
        // RESET
        // -------------------------------------------------

        repeat (5)
            @(posedge aclk);

        aresetn = 1'b1;

        repeat (2)
            @(posedge aclk);

        if (sample_drop_count !== 32'd0 ||
            overflow_sticky   !== 1'b0) begin

            $display("FAIL: drop status incorrect after reset");
            $fatal;

        end


        // -------------------------------------------------
        // TEST 1
        // Normal packet transmission
        // -------------------------------------------------

        m_axis_tready = 1'b1;

        pulse_sample(12'hA04, 12'h810);

        expect_transfer(32'hAD10_0001, 1'b0);
        expect_transfer(32'h00A0_4810, 1'b0);
        expect_transfer(32'h0000_0000, 1'b0);
        expect_transfer(32'h5A00_0000, 1'b1);

        if (sample_drop_count !== 32'd0 ||
            overflow_sticky   !== 1'b0) begin

            $display("FAIL: false drop detected during normal transfer");
            $fatal;

        end


        // -------------------------------------------------
        // TEST 2
        // Backpressure + deliberate sample loss
        //
        // Accept ABC/123, transmit its header, then stop
        // TREADY before the ADC payload word.
        //
        // Two additional samples arrive while the original
        // packet remains active. They must be counted as
        // dropped and must NOT overwrite the accepted sample.
        // -------------------------------------------------

        pulse_sample(12'hABC, 12'h123);

        expect_transfer(32'hAD10_0001, 1'b0);

        @(negedge aclk);
        m_axis_tready = 1'b0;

        // Payload must now remain stable under backpressure.
        repeat (4) begin

            @(posedge aclk);
            #1;

            if (!m_axis_tvalid) begin
                $display("FAIL: TVALID dropped during backpressure");
                $fatal;
            end

            if (m_axis_tdata !== 32'h00AB_C123) begin
                $display("FAIL: TDATA changed during backpressure");
                $fatal;
            end

            if (m_axis_tlast !== 1'b0) begin
                $display("FAIL: unexpected TLAST during payload stall");
                $fatal;
            end

        end


        // First intentionally dropped ADC sample.
        pulse_sample(12'h111, 12'h222);

        // Second intentionally dropped ADC sample.
        pulse_sample(12'h333, 12'h444);

        @(posedge aclk);
        #1;

        if (sample_drop_count !== 32'd2) begin

            $display(
                "FAIL: expected drop count 2, received %0d",
                sample_drop_count
            );
            $fatal;

        end

        if (overflow_sticky !== 1'b1) begin
            $display("FAIL: overflow_sticky did not assert");
            $fatal;
        end

        /*
         * The two rejected samples must not modify the
         * accepted ABC/123 packet currently being stalled.
         */
        if (m_axis_tdata !== 32'h00AB_C123) begin
            $display("FAIL: accepted sample corrupted by dropped samples");
            $fatal;
        end


        // -------------------------------------------------
        // RELEASE BACKPRESSURE
        // Original packet must resume cleanly.
        // -------------------------------------------------

        @(negedge aclk);
        m_axis_tready = 1'b1;

        expect_transfer(32'h00AB_C123, 1'b0);
        expect_transfer(32'h0000_0001, 1'b0);
        expect_transfer(32'h5A00_0001, 1'b1);


        // -------------------------------------------------
        // TEST 3
        // Recovery after overflow
        //
        // Packetizer must accept another real sample after
        // the stalled packet has completed.
        // -------------------------------------------------

        pulse_sample(12'h555, 12'hAAA);

        expect_transfer(32'hAD10_0001, 1'b0);
        expect_transfer(32'h0055_5AAA, 1'b0);
        expect_transfer(32'h0000_0002, 1'b0);
        expect_transfer(32'h5A00_0002, 1'b1);

        if (sample_drop_count !== 32'd2) begin
            $display("FAIL: drop count changed during recovery");
            $fatal;
        end

        if (overflow_sticky !== 1'b1) begin
            $display("FAIL: sticky overflow flag unexpectedly cleared");
            $fatal;
        end


        // -------------------------------------------------
        // FINAL RESULT
        // -------------------------------------------------

        $display("");
        $display("================================================");
        $display("AD1 AXI PACKETIZER HARDENING TEST: PASS");
        $display("Normal packet transmission:      PASS");
        $display("AXI backpressure stability:      PASS");
        $display("Dropped-sample accounting:       PASS");
        $display("Sticky overflow indication:      PASS");
        $display("Accepted-sample preservation:    PASS");
        $display("Post-backpressure recovery:      PASS");
        $display("TKEEP/TLAST framing:             PASS");
        $display("================================================");
        $display("Final drop count: %0d", sample_drop_count);
        $display("");

        $finish;

    end

endmodule
