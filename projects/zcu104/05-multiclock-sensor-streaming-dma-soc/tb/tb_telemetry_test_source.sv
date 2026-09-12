/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - AXI4-Stream telemetry source verification
 */

`timescale 1ns/1ps

module tb_telemetry_test_source;

    logic clk = 1'b0;
    logic resetn = 1'b0;
    logic enable = 1'b0;

    logic [31:0] tdata;
    logic [3:0]  tkeep;
    logic        tvalid;
    logic        tready;
    logic        tlast;

    int transfer_count = 0;
    int packet_count   = 0;
    int word_in_packet = 0;

    logic [31:0] previous_data;
    logic        previous_last;
    logic        previous_stalled;

    telemetry_test_source dut (
        .aclk          (clk),
        .aresetn       (resetn),
        .enable        (enable),
        .m_axis_tdata  (tdata),
        .m_axis_tkeep  (tkeep),
        .m_axis_tvalid (tvalid),
        .m_axis_tready (tready),
        .m_axis_tlast  (tlast)
    );

    always #5 clk = ~clk;

    always @(posedge clk) begin
        if (resetn) begin

            /* AXI rule: payload must remain stable during backpressure. */
            if (previous_stalled) begin
                if (tdata !== previous_data)
                    $fatal(1, "FAIL: TDATA changed while stalled");

                if (tlast !== previous_last)
                    $fatal(1, "FAIL: TLAST changed while stalled");
            end

            previous_stalled <= tvalid && !tready;
            previous_data    <= tdata;
            previous_last    <= tlast;

            if (tvalid && tready) begin

                transfer_count++;

                if (tkeep !== 4'hF)
                    $fatal(1, "FAIL: TKEEP != 0xF");

                case (word_in_packet)

                    0: begin
                        if (tdata !== 32'hA500_0001)
                            $fatal(1, "FAIL: bad packet header");

                        if (tlast)
                            $fatal(1, "FAIL: early TLAST");
                    end

                    1: begin
                        if (tdata !== packet_count)
                            $fatal(1, "FAIL: sequence mismatch");

                        if (tlast)
                            $fatal(1, "FAIL: early TLAST");
                    end

                    2: begin
                        if (tlast)
                            $fatal(1, "FAIL: early TLAST");
                    end

                    3: begin
                        if (tdata !==
                           (32'h5A00_0000 |
                            {8'h00, packet_count[23:0]}))
                            $fatal(1, "FAIL: payload mismatch");

                        if (!tlast)
                            $fatal(1, "FAIL: TLAST missing");

                        packet_count++;
                    end
                endcase

                $display(
                    "TRANSFER %0d : packet=%0d word=%0d data=%08X last=%b",
                    transfer_count,
                    packet_count,
                    word_in_packet,
                    tdata,
                    tlast
                );

                if (word_in_packet == 3)
                    word_in_packet = 0;
                else
                    word_in_packet++;

            end
        end
    end

    initial begin

    tready = 1'b0;

    repeat (5) @(posedge clk);

    @(negedge clk);
    resetn = 1'b1;

    repeat (3) @(posedge clk);

    @(negedge clk);
    enable = 1'b1;
    tready = 1'b1;

    /* Allow normal transfers. */
    repeat (7) @(posedge clk);

    /* Apply backpressure BETWEEN active clock edges. */
    @(negedge clk);
    $display("---- APPLYING BACKPRESSURE ----");
    tready = 1'b0;

    repeat (6) @(posedge clk);

    /* Release backpressure BETWEEN active clock edges. */
    @(negedge clk);
    $display("---- RELEASING BACKPRESSURE ----");
    tready = 1'b1;

    wait (packet_count >= 3);

    @(negedge clk);
    enable = 1'b0;

    repeat (10) @(posedge clk);

    $display("");
    $display("======================================");
    $display("AXI4-STREAM TELEMETRY TEST: PASS");
    $display("Packets verified  : %0d", packet_count);
    $display("Transfers verified: %0d", transfer_count);
    $display("Backpressure test : PASS");
    $display("======================================");

    $finish;
end



endmodule
