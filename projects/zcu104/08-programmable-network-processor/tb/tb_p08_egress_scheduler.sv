`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Verification:
 *   Four-Queue Packet-Aware Weighted Egress Scheduler
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module tb_p08_egress_scheduler;

    logic clk = 1'b0;

    always #4 clk = ~clk;     // 125 MHz

    logic aresetn = 1'b0;

    logic [63:0] s_axis_tdata;
    logic [7:0]  s_axis_tkeep;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    logic [1:0]  s_packet_queue;

    logic        cfg_we;
    logic [1:0]  cfg_queue;
    logic [3:0]  cfg_weight;
    logic [15:0] cfg_gap_cycles;

    logic [63:0] m_axis_tdata;
    logic [7:0]  m_axis_tkeep;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;

    logic [1:0]  m_packet_queue;

    logic [15:0] q0_occupancy;
    logic [15:0] q1_occupancy;
    logic [15:0] q2_occupancy;
    logic [15:0] q3_occupancy;

    logic [15:0] q0_packets;
    logic [15:0] q1_packets;
    logic [15:0] q2_packets;
    logic [15:0] q3_packets;

    logic [31:0] packets_enqueued;
    logic [31:0] packets_transmitted;

    logic        packet_sent_event;
    logic [1:0]  packet_sent_queue;

    p08_egress_scheduler #(
        .QUEUE_DEPTH_BEATS(32)
    ) dut (
        .clk                 (clk),
        .aresetn             (aresetn),

        .s_axis_tdata        (s_axis_tdata),
        .s_axis_tkeep        (s_axis_tkeep),
        .s_axis_tvalid       (s_axis_tvalid),
        .s_axis_tready       (s_axis_tready),
        .s_axis_tlast        (s_axis_tlast),

        .s_packet_queue      (s_packet_queue),

        .cfg_we              (cfg_we),
        .cfg_queue           (cfg_queue),
        .cfg_weight          (cfg_weight),
        .cfg_gap_cycles      (cfg_gap_cycles),

        .m_axis_tdata        (m_axis_tdata),
        .m_axis_tkeep        (m_axis_tkeep),
        .m_axis_tvalid       (m_axis_tvalid),
        .m_axis_tready       (m_axis_tready),
        .m_axis_tlast        (m_axis_tlast),

        .m_packet_queue      (m_packet_queue),

        .q0_occupancy        (q0_occupancy),
        .q1_occupancy        (q1_occupancy),
        .q2_occupancy        (q2_occupancy),
        .q3_occupancy        (q3_occupancy),

        .q0_packets          (q0_packets),
        .q1_packets          (q1_packets),
        .q2_packets          (q2_packets),
        .q3_packets          (q3_packets),

        .packets_enqueued    (packets_enqueued),
        .packets_transmitted (packets_transmitted),

        .packet_sent_event   (packet_sent_event),
        .packet_sent_queue   (packet_sent_queue)
    );

    integer cycle_counter = 0;

    logic output_enable;
    logic stall_enable;

    integer output_stalls = 0;

    always @(posedge clk) begin

        if (!aresetn)
            cycle_counter <= 0;
        else
            cycle_counter <=
                cycle_counter + 1;

    end

    always_comb begin

        if (!aresetn ||
            !output_enable)
            m_axis_tready =
                1'b0;
        else if (stall_enable)
            m_axis_tready =
                ((cycle_counter % 5) != 0);
        else
            m_axis_tready =
                1'b1;

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
                packet_id * 29 +
                offset * 11 +
                8'h37;

            pattern_byte =
                value[7:0];

        end

    endfunction

    /*
     * Per-queue packet scoreboard.
     */
    integer exp_id [0:3][0:31];
    integer exp_len [0:3][0:31];

    integer exp_wr [0:3];
    integer exp_rd [0:3];

    task automatic expect_packet(
        input integer queue_id,
        input integer packet_id,
        input integer packet_length
    );

        begin

            exp_id[
                queue_id
            ][
                exp_wr[queue_id]
            ] =
                packet_id;

            exp_len[
                queue_id
            ][
                exp_wr[queue_id]
            ] =
                packet_length;

            exp_wr[queue_id] =
                exp_wr[queue_id] + 1;

        end

    endtask

    task automatic configure_queue(
        input integer queue_id,
        input integer weight,
        input integer gap
    );

        begin

            @(negedge clk);

            cfg_queue =
                queue_id;

            cfg_weight =
                weight;

            cfg_gap_cycles =
                gap;

            cfg_we =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            cfg_we =
                1'b0;

        end

    endtask

    task automatic send_packet(
        input integer queue_id,
        input integer packet_id,
        input integer packet_length
    );

        integer offset;
        integer lane;
        integer beat_length;

        logic [63:0] data;
        logic [7:0] keep;

        begin

            expect_packet(
                queue_id,
                packet_id,
                packet_length
            );

            offset = 0;

            while (offset <
                   packet_length) begin

                if ((packet_length -
                     offset) > 8)
                    beat_length = 8;
                else
                    beat_length =
                        packet_length -
                        offset;

                data =
                    64'd0;

                keep =
                    8'd0;

                for (lane = 0;
                     lane < beat_length;
                     lane = lane + 1) begin

                    data[
                        lane*8 +: 8
                    ] =
                        pattern_byte(
                            packet_id,
                            offset +
                            lane
                        );

                    keep[lane] =
                        1'b1;

                end

                @(negedge clk);

                s_packet_queue =
                    queue_id;

                s_axis_tdata =
                    data;

                s_axis_tkeep =
                    keep;

                s_axis_tvalid =
                    1'b1;

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

            s_axis_tvalid =
                1'b0;

            s_axis_tlast =
                1'b0;

            s_axis_tkeep =
                8'd0;

            s_axis_tdata =
                64'd0;

        end

    endtask

    /*
     * Output packet scoreboard.
     */
    logic rx_active = 1'b0;

    integer rx_queue;
    integer rx_id;
    integer rx_expected_length;
    integer rx_offset;

    integer lane_index;
    integer output_packets = 0;

    integer queue_sequence [0:63];
    integer sequence_count = 0;

    integer rate_phase = 0;

    integer rate_q2_packet_index = 0;
    integer rate_q2_first_end = 0;
    integer rate_q2_second_start = 0;

    always @(posedge clk) begin

        integer bytes_this_beat;

        if (aresetn &&
            m_axis_tvalid &&
            m_axis_tready) begin

            bytes_this_beat =
                0;

            if (!rx_active) begin

                rx_queue =
                    m_packet_queue;

                if (exp_rd[rx_queue] >=
                    exp_wr[rx_queue]) begin

                    $display(
                        "FAIL: unexpected packet from queue %0d",
                        rx_queue
                    );

                    $fatal;

                end

                rx_id =
                    exp_id[
                        rx_queue
                    ][
                        exp_rd[rx_queue]
                    ];

                rx_expected_length =
                    exp_len[
                        rx_queue
                    ][
                        exp_rd[rx_queue]
                    ];

                rx_offset =
                    0;

                rx_active =
                    1'b1;

                queue_sequence[
                    sequence_count
                ] =
                    rx_queue;

                sequence_count =
                    sequence_count + 1;

                if (rate_phase &&
                    rx_queue == 2) begin

                    rate_q2_packet_index =
                        rate_q2_packet_index + 1;

                    if (rate_q2_packet_index == 2)
                        rate_q2_second_start =
                            cycle_counter;

                end

            end
            else if (
                m_packet_queue !=
                rx_queue
            ) begin

                $display(
                    "FAIL: packet interleaving detected"
                );

                $fatal;

            end

            for (lane_index = 0;
                 lane_index < 8;
                 lane_index = lane_index + 1) begin

                if (m_axis_tkeep[
                        lane_index
                    ]) begin

                    if (m_axis_tdata[
                            lane_index*8 +: 8
                        ] !==
                        pattern_byte(
                            rx_id,
                            rx_offset
                        )) begin

                        $display(
                            "FAIL: byte mismatch queue=%0d packet=%0d offset=%0d",
                            rx_queue,
                            rx_id,
                            rx_offset
                        );

                        $fatal;

                    end

                    rx_offset =
                        rx_offset + 1;

                    bytes_this_beat =
                        bytes_this_beat + 1;

                end

            end

            if (m_axis_tlast) begin

                if (rx_offset !=
                    rx_expected_length) begin

                    $display(
                        "FAIL: packet length queue=%0d got=%0d expected=%0d",
                        rx_queue,
                        rx_offset,
                        rx_expected_length
                    );

                    $fatal;

                end

                if (rate_phase &&
                    rx_queue == 2 &&
                    rate_q2_packet_index == 1)
                    rate_q2_first_end =
                        cycle_counter;

                exp_rd[
                    rx_queue
                ] =
                    exp_rd[
                        rx_queue
                    ] + 1;

                output_packets =
                    output_packets + 1;

                rx_active =
                    1'b0;

            end

        end

    end

    integer q;

    initial begin

        s_axis_tdata =
            64'd0;

        s_axis_tkeep =
            8'd0;

        s_axis_tvalid =
            1'b0;

        s_axis_tlast =
            1'b0;

        s_packet_queue =
            2'd0;

        cfg_we =
            1'b0;

        cfg_queue =
            2'd0;

        cfg_weight =
            4'd1;

        cfg_gap_cycles =
            16'd0;

        output_enable =
            1'b0;

        stall_enable =
            1'b0;

        for (q = 0; q < 4; q = q + 1) begin

            exp_wr[q] =
                0;

            exp_rd[q] =
                0;

        end

        repeat (10)
            @(posedge clk);

        aresetn =
            1'b1;

        repeat (4)
            @(posedge clk);

        /*
         * Weighted round-robin:
         *
         * Q0 weight 2
         * Q1/Q2/Q3 weight 1
         */
        configure_queue(
            0, 2, 0
        );

        configure_queue(
            1, 1, 0
        );

        configure_queue(
            2, 1, 0
        );

        configure_queue(
            3, 1, 0
        );

        $display("");
        $display(
            "===== 08G PHASE 1: FOUR QUEUES / WRR ====="
        );

        /*
         * Output held while queues are populated.
         */
        send_packet(0, 100, 32);
        send_packet(0, 101, 17);
        send_packet(0, 102, 25);

        send_packet(1, 200, 21);
        send_packet(1, 201, 13);

        send_packet(2, 300, 29);

        send_packet(3, 400, 15);

        stall_enable =
            1'b1;

        output_enable =
            1'b1;

        wait (
            output_packets == 7
        );

        repeat (10)
            @(posedge clk);

        if (packets_enqueued != 7 ||
            packets_transmitted != 7) begin

            $display(
                "FAIL: packet accounting enq=%0d tx=%0d",
                packets_enqueued,
                packets_transmitted
            );

            $fatal;

        end

        /*
         * With all queues populated before release and weights
         * 2:1:1:1, the first WRR round must begin:
         *
         * Q0 -> Q1 -> Q2 -> Q3 -> Q0
         */
        if (queue_sequence[0] != 0 ||
            queue_sequence[1] != 1 ||
            queue_sequence[2] != 2 ||
            queue_sequence[3] != 3 ||
            queue_sequence[4] != 0) begin

            $display(
                "FAIL: WRR order %0d %0d %0d %0d %0d",
                queue_sequence[0],
                queue_sequence[1],
                queue_sequence[2],
                queue_sequence[3],
                queue_sequence[4]
            );

            $fatal;

        end

        $display(
            "WEIGHTED ROUND-ROBIN ORDER: PASS"
        );

        if (output_stalls == 0) begin

            $display(
                "FAIL: downstream backpressure not exercised"
            );

            $fatal;

        end

        $display(
            "OUTPUT BACKPRESSURE: PASS"
        );

        /*
         * -----------------------------------------------------
         * PHASE 2 — rate control.
         * -----------------------------------------------------
         */
        $display("");
        $display(
            "===== 08G PHASE 2: RATE CONTROL ====="
        );

        output_enable =
            1'b0;

        stall_enable =
            1'b0;

        configure_queue(
            2,
            1,
            12
        );

        rate_phase =
            1;

        rate_q2_packet_index =
            0;

        send_packet(
            2,
            500,
            16
        );

        send_packet(
            2,
            501,
            16
        );

        output_enable =
            1'b1;

        wait (
            output_packets == 9
        );

        repeat (5)
            @(posedge clk);

        if ((rate_q2_second_start -
             rate_q2_first_end) < 12) begin

            $display(
                "FAIL: rate gap=%0d expected >=12",
                rate_q2_second_start -
                rate_q2_first_end
            );

            $fatal;

        end

        $display(
            "RATE CONTROL GAP: PASS cycles=%0d",
            rate_q2_second_start -
            rate_q2_first_end
        );

        rate_phase =
            0;

        /*
         * -----------------------------------------------------
         * PHASE 3 — queue-full backpressure.
         *
         * Four 64-byte packets = 32 beats = full Q3.
         * -----------------------------------------------------
         */
        $display("");
        $display(
            "===== 08G PHASE 3: QUEUE FULL ====="
        );

        output_enable =
            1'b0;

        configure_queue(
            3,
            1,
            0
        );

        send_packet(3, 600, 64);
        send_packet(3, 601, 64);
        send_packet(3, 602, 64);
        send_packet(3, 603, 64);

        @(negedge clk);

        s_packet_queue =
            2'd3;

        #1;

        if (s_axis_tready !==
            1'b0) begin

            $display(
                "FAIL: Q3 full did not assert ingress backpressure"
            );

            $fatal;

        end

        $display(
            "QUEUE-FULL BACKPRESSURE: PASS"
        );

        output_enable =
            1'b1;

        wait (
            output_packets == 13
        );

        repeat (10)
            @(posedge clk);

        /*
         * All expected packet queues must be empty.
         */
        for (q = 0;
             q < 4;
             q = q + 1) begin

            if (exp_rd[q] !=
                exp_wr[q]) begin

                $display(
                    "FAIL: scoreboard queue=%0d rd=%0d wr=%0d",
                    q,
                    exp_rd[q],
                    exp_wr[q]
                );

                $fatal;

            end

        end

        if (q0_packets != 0 ||
            q1_packets != 0 ||
            q2_packets != 0 ||
            q3_packets != 0 ||
            q0_occupancy != 0 ||
            q1_occupancy != 0 ||
            q2_occupancy != 0 ||
            q3_occupancy != 0) begin

            $display(
                "FAIL: queues not empty at completion"
            );

            $fatal;

        end

        if (packets_enqueued != 13 ||
            packets_transmitted != 13) begin

            $display(
                "FAIL: final accounting enq=%0d tx=%0d",
                packets_enqueued,
                packets_transmitted
            );

            $fatal;

        end

        $display("");
        $display(
            "============================================"
        );
        $display(
            " PROJECT08 08G EGRESS SCHEDULER: PASS"
        );
        $display(
            "============================================"
        );
        $display(
            " Hardware queues            : 4"
        );
        $display(
            " Packet-aware scheduling    : PASS"
        );
        $display(
            " No packet interleaving     : PASS"
        );
        $display(
            " Weighted round-robin       : PASS"
        );
        $display(
            " Runtime queue weights      : PASS"
        );
        $display(
            " Per-queue rate control     : PASS"
        );
        $display(
            " Queue-full backpressure    : PASS"
        );
        $display(
            " Output backpressure        : PASS"
        );
        $display(
            " Byte-perfect scheduling    : PASS"
        );
        $display(
            " Queue telemetry            : PASS"
        );
        $display(
            " Packets enqueued           : %0d",
            packets_enqueued
        );
        $display(
            " Packets transmitted        : %0d",
            packets_transmitted
        );
        $display(
            " Output stall cycles        : %0d",
            output_stalls
        );
        $display(
            " Rate-gap measured          : %0d cycles",
            rate_q2_second_start -
            rate_q2_first_end
        );
        $display(
            "============================================"
        );

        $finish;

    end

    initial begin

        #20_000_000;

        $display(
            "FAIL: Project08 08G simulation timeout"
        );

        $fatal;

    end

endmodule
