`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Verification:
 *   Dual-Bank Packet Buffer + Match/Action Synchronization
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module tb_p08_packet_action_buffer;

    localparam logic [2:0] ACTION_FORWARD  = 3'd0;
    localparam logic [2:0] ACTION_DROP     = 3'd1;
    localparam logic [2:0] ACTION_REDIRECT = 3'd2;
    localparam logic [2:0] ACTION_MODIFY   = 3'd3;
    localparam logic [2:0] ACTION_COUNT    = 3'd4;

    logic clk = 1'b0;

    always #4 clk = ~clk;     // 125 MHz

    logic aresetn = 1'b0;

    logic [63:0] s_axis_tdata;
    logic [7:0]  s_axis_tkeep;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    logic        decision_valid;
    logic [2:0]  decision_action;
    logic [1:0]  decision_queue;

    logic [63:0] m_axis_tdata;
    logic [7:0]  m_axis_tkeep;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;

    logic [2:0]  m_packet_action;
    logic [1:0]  m_packet_queue;

    logic forward_event;
    logic drop_event;
    logic redirect_event;
    logic modify_event;
    logic count_event;

    logic [31:0] packets_accepted;
    logic [31:0] packets_forwarded;
    logic [31:0] packets_dropped;

    p08_packet_action_buffer dut (

        .clk                (clk),
        .aresetn            (aresetn),

        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tkeep       (s_axis_tkeep),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),
        .s_axis_tlast       (s_axis_tlast),

        .decision_valid     (decision_valid),
        .decision_action    (decision_action),
        .decision_queue     (decision_queue),

        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tkeep       (m_axis_tkeep),
        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tready      (m_axis_tready),
        .m_axis_tlast       (m_axis_tlast),

        .m_packet_action    (m_packet_action),
        .m_packet_queue     (m_packet_queue),

        .forward_event      (forward_event),
        .drop_event         (drop_event),
        .redirect_event     (redirect_event),
        .modify_event       (modify_event),
        .count_event        (count_event),

        .packets_accepted   (packets_accepted),
        .packets_forwarded  (packets_forwarded),
        .packets_dropped    (packets_dropped)
    );

    /*
     * Deterministic output backpressure.
     */
    integer cycle_count = 0;
    integer output_stalls = 0;

    always @(posedge clk) begin

        if (!aresetn)
            cycle_count <= 0;
        else
            cycle_count <=
                cycle_count + 1;

    end

    always_comb begin

        if (!aresetn)
            m_axis_tready = 1'b0;
        else
            m_axis_tready =
                ((cycle_count % 4) != 0);

    end

    always @(posedge clk) begin

        if (aresetn &&
            m_axis_tvalid &&
            !m_axis_tready)
            output_stalls =
                output_stalls + 1;

    end

    function automatic [7:0] pattern_byte(
        input integer packet_id,
        input integer offset
    );

        integer value;

        begin

            value =
                packet_id * 41 +
                offset * 17 +
                8'h31;

            pattern_byte =
                value[7:0];

        end

    endfunction

    logic [7:0] expected_bytes[$];
    integer expected_lengths[$];
    logic [2:0] expected_actions[$];
    logic [1:0] expected_queues[$];

    task automatic enqueue_expected(
        input integer packet_id,
        input integer packet_length,
        input logic [2:0] packet_action,
        input logic [1:0] packet_queue
    );

        integer n;

        begin

            expected_lengths.push_back(
                packet_length
            );

            expected_actions.push_back(
                packet_action
            );

            expected_queues.push_back(
                packet_queue
            );

            for (n = 0;
                 n < packet_length;
                 n = n + 1)
                expected_bytes.push_back(
                    pattern_byte(
                        packet_id,
                        n
                    )
                );

        end

    endtask

    task automatic send_packet(
        input integer packet_id,
        input integer packet_length
    );

        integer offset;
        integer lane;
        integer beat_length;

        logic [63:0] data;
        logic [7:0] keep;

        begin

            offset = 0;

            while (offset <
                   packet_length) begin

                if ((packet_length - offset) > 8)
                    beat_length = 8;
                else
                    beat_length =
                        packet_length -
                        offset;

                data = 64'd0;
                keep = 8'd0;

                for (lane = 0;
                     lane < beat_length;
                     lane = lane + 1) begin

                    data[
                        lane*8 +: 8
                    ] =
                        pattern_byte(
                            packet_id,
                            offset + lane
                        );

                    keep[lane] =
                        1'b1;

                end

                @(negedge clk);

                s_axis_tdata  = data;
                s_axis_tkeep  = keep;
                s_axis_tvalid = 1'b1;

                s_axis_tlast =
                    ((offset +
                      beat_length) ==
                     packet_length);

                @(posedge clk);

                while (!s_axis_tready)
                    @(posedge clk);

                offset =
                    offset +
                    beat_length;

            end

            @(negedge clk);

            s_axis_tvalid = 1'b0;
            s_axis_tlast  = 1'b0;
            s_axis_tkeep  = 8'd0;
            s_axis_tdata  = 64'd0;

        end

    endtask

    task automatic send_decision(
        input logic [2:0] packet_action,
        input logic [1:0] packet_queue
    );

        begin

            @(negedge clk);

            decision_action =
                packet_action;

            decision_queue =
                packet_queue;

            decision_valid =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            decision_valid =
                1'b0;

            decision_action =
                ACTION_DROP;

            decision_queue =
                2'd0;

        end

    endtask

    /*
     * Output scoreboard.
     */
    integer rx_packet_bytes = 0;
    integer rx_packets = 0;
    integer lane_index;

    logic [7:0] expected_byte;

    always @(posedge clk) begin

        if (aresetn &&
            m_axis_tvalid &&
            m_axis_tready) begin

            if (expected_lengths.size() == 0 ||
                expected_actions.size() == 0 ||
                expected_queues.size() == 0) begin

                $display(
                    "FAIL: unexpected output packet"
                );

                $fatal;

            end

            if (m_packet_action !==
                expected_actions[0]) begin

                $display(
                    "FAIL: output action mismatch got=%0d expected=%0d",
                    m_packet_action,
                    expected_actions[0]
                );

                $fatal;

            end

            if (m_packet_queue !==
                expected_queues[0]) begin

                $display(
                    "FAIL: output queue mismatch got=%0d expected=%0d",
                    m_packet_queue,
                    expected_queues[0]
                );

                $fatal;

            end

            for (lane_index = 0;
                 lane_index < 8;
                 lane_index = lane_index + 1) begin

                if (m_axis_tkeep[
                        lane_index
                    ]) begin

                    if (expected_bytes.size()
                        == 0) begin

                        $display(
                            "FAIL: unexpected output byte"
                        );

                        $fatal;

                    end

                    expected_byte =
                        expected_bytes.pop_front();

                    if (m_axis_tdata[
                            lane_index*8 +: 8
                        ] !== expected_byte) begin

                        $display(
                            "FAIL: output byte mismatch"
                        );

                        $fatal;

                    end

                    rx_packet_bytes =
                        rx_packet_bytes + 1;

                end

            end

            if (m_axis_tlast) begin

                if (rx_packet_bytes !=
                    expected_lengths[0]) begin

                    $display(
                        "FAIL: output packet length got=%0d expected=%0d",
                        rx_packet_bytes,
                        expected_lengths[0]
                    );

                    $fatal;

                end

                expected_lengths.pop_front();
                expected_actions.pop_front();
                expected_queues.pop_front();

                rx_packet_bytes = 0;
                rx_packets =
                    rx_packets + 1;

            end

        end

    end

    integer forward_events  = 0;
    integer drop_events     = 0;
    integer redirect_events = 0;
    integer modify_events   = 0;
    integer count_events    = 0;

    always @(posedge clk) begin

        if (forward_event)
            forward_events =
                forward_events + 1;

        if (drop_event)
            drop_events =
                drop_events + 1;

        if (redirect_event)
            redirect_events =
                redirect_events + 1;

        if (modify_event)
            modify_events =
                modify_events + 1;

        if (count_event)
            count_events =
                count_events + 1;

    end

    initial begin

        s_axis_tdata  = 64'd0;
        s_axis_tkeep  = 8'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        decision_valid  = 1'b0;
        decision_action = ACTION_DROP;
        decision_queue  = 2'd0;

        repeat (10)
            @(posedge clk);

        aresetn = 1'b1;

        repeat (4)
            @(posedge clk);

        $display("");
        $display(
            "===== 08E DUAL-BANK CAPTURE ====="
        );

        /*
         * Fill both packet banks before issuing decisions.
         */
        send_packet(
            1,
            64
        );

        send_packet(
            2,
            13
        );

        /*
         * Both banks are occupied. Ingress must backpressure.
         */
        repeat (2)
            @(posedge clk);

        if (s_axis_tready !== 1'b0) begin

            $display(
                "FAIL: ingress remained ready with both banks occupied"
            );

            $fatal;

        end

        $display(
            "DUAL-BANK FULL BACKPRESSURE: PASS"
        );

        /*
         * Packet 1 -> FORWARD.
         */
        enqueue_expected(
            1,
            64,
            ACTION_FORWARD,
            2'd0
        );

        send_decision(
            ACTION_FORWARD,
            2'd0
        );

        /*
         * Packet 2 -> DROP.
         *
         * No expected output is queued.
         */
        send_decision(
            ACTION_DROP,
            2'd0
        );

        /*
         * Allow output replay/freeing.
         */
        wait (
            packets_forwarded == 1 &&
            packets_dropped == 1
        );

        /*
         * -----------------------------------------------------
         * Packet 3 -> REDIRECT queue 2.
         * -----------------------------------------------------
         */
        send_packet(
            3,
            151
        );

        enqueue_expected(
            3,
            151,
            ACTION_REDIRECT,
            2'd2
        );

        send_decision(
            ACTION_REDIRECT,
            2'd2
        );

        /*
         * -----------------------------------------------------
         * Packet 4 -> MODIFY queue 1.
         *
         * 08E carries MODIFY disposition with the packet.
         * Actual byte rewriting is performed by the later editor.
         * -----------------------------------------------------
         */
        send_packet(
            4,
            9
        );

        enqueue_expected(
            4,
            9,
            ACTION_MODIFY,
            2'd1
        );

        send_decision(
            ACTION_MODIFY,
            2'd1
        );

        /*
         * -----------------------------------------------------
         * Packet 5 -> COUNT and forward.
         * -----------------------------------------------------
         */
        send_packet(
            5,
            257
        );

        enqueue_expected(
            5,
            257,
            ACTION_COUNT,
            2'd0
        );

        send_decision(
            ACTION_COUNT,
            2'd0
        );

        /*
         * Wait for all non-drop packets.
         */
        wait (
            packets_forwarded == 4
        );

        repeat (20)
            @(posedge clk);

        if (expected_bytes.size() != 0 ||
            expected_lengths.size() != 0 ||
            expected_actions.size() != 0 ||
            expected_queues.size() != 0) begin

            $display(
                "FAIL: output scoreboard not empty"
            );

            $fatal;

        end

        if (packets_accepted != 5) begin

            $display(
                "FAIL: accepted=%0d expected=5",
                packets_accepted
            );

            $fatal;

        end

        if (packets_forwarded != 4) begin

            $display(
                "FAIL: forwarded=%0d expected=4",
                packets_forwarded
            );

            $fatal;

        end

        if (packets_dropped != 1) begin

            $display(
                "FAIL: dropped=%0d expected=1",
                packets_dropped
            );

            $fatal;

        end

        if (rx_packets != 4) begin

            $display(
                "FAIL: output packets=%0d expected=4",
                rx_packets
            );

            $fatal;

        end

        if (forward_events != 1 ||
            drop_events != 1 ||
            redirect_events != 1 ||
            modify_events != 1 ||
            count_events != 1) begin

            $display(
                "FAIL: disposition events F=%0d D=%0d R=%0d M=%0d C=%0d",
                forward_events,
                drop_events,
                redirect_events,
                modify_events,
                count_events
            );

            $fatal;

        end

        if (output_stalls == 0) begin

            $display(
                "FAIL: output backpressure was not exercised"
            );

            $fatal;

        end

        $display("");
        $display(
            "============================================"
        );
        $display(
            " PROJECT08 08E PACKET ACTION BUFFER: PASS"
        );
        $display(
            "============================================"
        );
        $display(
            " Dual-bank packet storage   : PASS"
        );
        $display(
            " Packet/decision ordering   : PASS"
        );
        $display(
            " Bank-full backpressure     : PASS"
        );
        $display(
            " Output backpressure        : PASS"
        );
        $display(
            " Byte-perfect replay        : PASS"
        );
        $display(
            " FORWARD execution          : PASS"
        );
        $display(
            " DROP suppression           : PASS"
        );
        $display(
            " REDIRECT queue transport   : PASS"
        );
        $display(
            " MODIFY disposition         : PASS"
        );
        $display(
            " COUNT disposition          : PASS"
        );
        $display(
            " Packets accepted           : %0d",
            packets_accepted
        );
        $display(
            " Packets output             : %0d",
            packets_forwarded
        );
        $display(
            " Packets dropped            : %0d",
            packets_dropped
        );
        $display(
            " Output stall cycles        : %0d",
            output_stalls
        );
        $display(
            "============================================"
        );

        $finish;

    end

    initial begin

        #10_000_000;

        $display(
            "FAIL: Project08 08E simulation timeout"
        );

        $fatal;

    end

endmodule
