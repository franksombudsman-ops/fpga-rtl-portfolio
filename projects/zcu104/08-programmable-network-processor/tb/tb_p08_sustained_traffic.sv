`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Verification:
 *   Sustained End-to-End Traffic and Performance Characterization
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module tb_p08_sustained_traffic;

    localparam logic [2:0] ACTION_FORWARD  = 3'd0;
    localparam logic [2:0] ACTION_DROP     = 3'd1;
    localparam logic [2:0] ACTION_REDIRECT = 3'd2;

    localparam integer PERF_PACKETS     = 1024;
    localparam integer PERF_FRAME_BYTES = 256;

    localparam integer STRESS_PACKETS   = 512;
    localparam integer UPDATE_PACKETS   = 128;

    logic clk = 1'b0;

    always #4 clk = ~clk;     // 125 MHz

    logic aresetn = 1'b0;

    logic [63:0] s_axis_tdata;
    logic [7:0]  s_axis_tkeep;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    logic [63:0] m_axis_tdata;
    logic [7:0]  m_axis_tkeep;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;

    logic [1:0] m_packet_queue;

    logic cfg_rule_we;
    logic [4:0] cfg_rule_index;
    logic cfg_rule_valid;

    logic cfg_vlan_present_value;
    logic cfg_vlan_present_mask;

    logic [11:0] cfg_vlan_value;
    logic [11:0] cfg_vlan_mask;

    logic [31:0] cfg_src_ip_value;
    logic [31:0] cfg_src_ip_mask;

    logic [31:0] cfg_dst_ip_value;
    logic [31:0] cfg_dst_ip_mask;

    logic [7:0] cfg_protocol_value;
    logic [7:0] cfg_protocol_mask;

    logic [15:0] cfg_src_port_value;
    logic [15:0] cfg_src_port_mask;

    logic [15:0] cfg_dst_port_value;
    logic [15:0] cfg_dst_port_mask;

    logic [2:0] cfg_action;
    logic [1:0] cfg_action_queue;

    logic cfg_edit_we;
    logic [4:0] cfg_edit_index;

    logic cfg_rewrite_src_ip;
    logic cfg_rewrite_dst_ip;
    logic cfg_rewrite_src_port;
    logic cfg_rewrite_dst_port;

    logic [31:0] cfg_new_src_ip;
    logic [31:0] cfg_new_dst_ip;
    logic [15:0] cfg_new_src_port;
    logic [15:0] cfg_new_dst_port;

    logic cfg_qos_we;
    logic [1:0] cfg_qos_queue;
    logic [3:0] cfg_qos_weight;
    logic [15:0] cfg_qos_gap_cycles;

    logic [31:0] packets_accepted;
    logic [31:0] packets_forwarded;
    logic [31:0] packets_dropped;

    logic [31:0] scheduler_enqueued;
    logic [31:0] scheduler_transmitted;

    p08_packet_processor_core dut (

        .clk                   (clk),
        .aresetn               (aresetn),

        .s_axis_tdata          (s_axis_tdata),
        .s_axis_tkeep          (s_axis_tkeep),
        .s_axis_tvalid         (s_axis_tvalid),
        .s_axis_tready         (s_axis_tready),
        .s_axis_tlast          (s_axis_tlast),

        .m_axis_tdata          (m_axis_tdata),
        .m_axis_tkeep          (m_axis_tkeep),
        .m_axis_tvalid         (m_axis_tvalid),
        .m_axis_tready         (m_axis_tready),
        .m_axis_tlast          (m_axis_tlast),

        .m_packet_queue        (m_packet_queue),

        .cfg_rule_we           (cfg_rule_we),
        .cfg_rule_index        (cfg_rule_index),
        .cfg_rule_valid        (cfg_rule_valid),

        .cfg_vlan_present_value(cfg_vlan_present_value),
        .cfg_vlan_present_mask (cfg_vlan_present_mask),

        .cfg_vlan_value        (cfg_vlan_value),
        .cfg_vlan_mask         (cfg_vlan_mask),

        .cfg_src_ip_value      (cfg_src_ip_value),
        .cfg_src_ip_mask       (cfg_src_ip_mask),

        .cfg_dst_ip_value      (cfg_dst_ip_value),
        .cfg_dst_ip_mask       (cfg_dst_ip_mask),

        .cfg_protocol_value    (cfg_protocol_value),
        .cfg_protocol_mask     (cfg_protocol_mask),

        .cfg_src_port_value    (cfg_src_port_value),
        .cfg_src_port_mask     (cfg_src_port_mask),

        .cfg_dst_port_value    (cfg_dst_port_value),
        .cfg_dst_port_mask     (cfg_dst_port_mask),

        .cfg_action            (cfg_action),
        .cfg_action_queue      (cfg_action_queue),

        .cfg_edit_we           (cfg_edit_we),
        .cfg_edit_index        (cfg_edit_index),

        .cfg_rewrite_src_ip    (cfg_rewrite_src_ip),
        .cfg_rewrite_dst_ip    (cfg_rewrite_dst_ip),
        .cfg_rewrite_src_port  (cfg_rewrite_src_port),
        .cfg_rewrite_dst_port  (cfg_rewrite_dst_port),

        .cfg_new_src_ip        (cfg_new_src_ip),
        .cfg_new_dst_ip        (cfg_new_dst_ip),
        .cfg_new_src_port      (cfg_new_src_port),
        .cfg_new_dst_port      (cfg_new_dst_port),

        .cfg_qos_we            (cfg_qos_we),
        .cfg_qos_queue         (cfg_qos_queue),
        .cfg_qos_weight        (cfg_qos_weight),
        .cfg_qos_gap_cycles    (cfg_qos_gap_cycles),

        .packets_accepted      (packets_accepted),
        .packets_forwarded     (packets_forwarded),
        .packets_dropped       (packets_dropped),

        .scheduler_enqueued    (scheduler_enqueued),
        .scheduler_transmitted (scheduler_transmitted)
    );

    /*
     * ---------------------------------------------------------
     * CLOCK / BACKPRESSURE ACCOUNTING
     * ---------------------------------------------------------
     */

    longint unsigned cycle_counter;

    logic stress_backpressure;

    longint unsigned ingress_stall_cycles;
    longint unsigned egress_stall_cycles;

    always @(posedge clk) begin

        if (!aresetn)
            cycle_counter <= 0;
        else
            cycle_counter <= cycle_counter + 1;

    end

    always_comb begin

        if (!aresetn)
            m_axis_tready = 1'b0;
        else if (!stress_backpressure)
            m_axis_tready = 1'b1;
        else
            m_axis_tready =
                ((cycle_counter % 7) != 0) &&
                ((cycle_counter % 13) != 0);

    end

    always @(posedge clk) begin

        if (aresetn &&
            s_axis_tvalid &&
            !s_axis_tready)
            ingress_stall_cycles =
                ingress_stall_cycles + 1;

        if (aresetn &&
            m_axis_tvalid &&
            !m_axis_tready)
            egress_stall_cycles =
                egress_stall_cycles + 1;

    end

    /*
     * ---------------------------------------------------------
     * PACKET CONSTRUCTION
     * ---------------------------------------------------------
     */

    logic [7:0] tx_mem [0:2047];
    integer tx_len;

    task automatic clear_packet;
        begin
            tx_len = 0;
        end
    endtask

    task automatic put8(
        input logic [7:0] value
    );
        begin
            tx_mem[tx_len] = value;
            tx_len = tx_len + 1;
        end
    endtask

    task automatic put16be(
        input logic [15:0] value
    );
        begin
            put8(value[15:8]);
            put8(value[7:0]);
        end
    endtask

    task automatic put32be(
        input logic [31:0] value
    );
        begin
            put8(value[31:24]);
            put8(value[23:16]);
            put8(value[15:8]);
            put8(value[7:0]);
        end
    endtask

    task automatic build_udp_exact(
        input integer packet_id,
        input integer total_frame_bytes,
        input logic [31:0] sip,
        input logic [31:0] dip,
        input logic [15:0] sport,
        input logic [15:0] dport
    );

        integer payload_length;
        integer ip_length;
        integer udp_length;
        integer n;

        begin

            if (total_frame_bytes < 42) begin
                $display("FAIL: requested frame too short");
                $fatal;
            end

            clear_packet();

            payload_length =
                total_frame_bytes - 42;

            ip_length =
                20 + 8 + payload_length;

            udp_length =
                8 + payload_length;

            /*
             * Ethernet.
             */
            put8(8'h02);
            put8(8'h11);
            put8(8'h22);
            put8(8'h33);
            put8(8'h44);
            put8(8'h55);

            put8(8'h02);
            put8(8'hAA);
            put8(8'hBB);
            put8(8'hCC);
            put8(8'hDD);
            put8(8'hEE);

            put16be(16'h0800);

            /*
             * IPv4.
             */
            put8(8'h45);
            put8(8'h00);

            put16be(ip_length[15:0]);

            put16be(packet_id[15:0]);
            put16be(16'h4000);

            put8(8'h40);
            put8(8'd17);

            put16be(16'h0000);

            put32be(sip);
            put32be(dip);

            /*
             * UDP.
             */
            put16be(sport);
            put16be(dport);

            put16be(udp_length[15:0]);
            put16be(16'h0000);

            /*
             * Deterministic packet-unique payload.
             */
            for (n = 0;
                 n < payload_length;
                 n = n + 1)
                put8(
                    (packet_id * 29 +
                     n * 17 +
                     8'h53) &
                    8'hFF
                );

        end

    endtask

    /*
     * ---------------------------------------------------------
     * EXPECTED OUTPUT STORAGE
     * ---------------------------------------------------------
     *
     * Per-queue scoreboards allow the hardware scheduler to
     * reorder packets between queues while preserving FIFO order
     * inside each queue.
     */

    logic [7:0] expected_bytes [0:3][0:400000];

    integer expected_byte_wr [0:3];
    integer expected_byte_rd [0:3];

    integer expected_length [0:3][0:2047];

    integer expected_pkt_wr [0:3];
    integer expected_pkt_rd [0:3];

    task automatic expect_current_packet(
        input integer queue_id
    );

        integer n;

        begin

            expected_length[
                queue_id
            ][
                expected_pkt_wr[queue_id]
            ] =
                tx_len;

            expected_pkt_wr[queue_id] =
                expected_pkt_wr[queue_id] + 1;

            for (n = 0;
                 n < tx_len;
                 n = n + 1) begin

                expected_bytes[
                    queue_id
                ][
                    expected_byte_wr[queue_id]
                ] =
                    tx_mem[n];

                expected_byte_wr[queue_id] =
                    expected_byte_wr[queue_id] + 1;

            end

        end

    endtask

    /*
     * ---------------------------------------------------------
     * CONTINUOUS SOURCE
     * ---------------------------------------------------------
     *
     * No artificial cycle is inserted between consecutive
     * packets. Backpressure alone determines source stalls.
     */

    task automatic send_current_packet_continuous;

        integer offset;
        integer k;
        integer beat_length;

        logic [63:0] data;
        logic [7:0] keep;

        begin

            offset = 0;

            while (offset < tx_len) begin

                if ((tx_len - offset) > 8)
                    beat_length = 8;
                else
                    beat_length =
                        tx_len - offset;

                data = 64'd0;
                keep = 8'd0;

                for (k = 0;
                     k < beat_length;
                     k = k + 1) begin

                    data[k*8 +: 8] =
                        tx_mem[offset + k];

                    keep[k] =
                        1'b1;

                end

                @(negedge clk);

                s_axis_tdata =
                    data;

                s_axis_tkeep =
                    keep;

                s_axis_tvalid =
                    1'b1;

                s_axis_tlast =
                    ((offset +
                      beat_length) ==
                     tx_len);

                @(posedge clk);

                while (!s_axis_tready)
                    @(posedge clk);

                offset =
                    offset + beat_length;

            end

        end

    endtask

    task automatic end_source_stream;

        begin

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
     * ---------------------------------------------------------
     * OUTPUT SCOREBOARD
     * ---------------------------------------------------------
     */

    logic output_packet_active;

    integer output_queue;
    integer output_packet_bytes;
    integer output_packet_expected_length;

    integer lane;

    longint unsigned output_packets;
    longint unsigned output_bytes;

    integer perf_output_packets;

    logic perf_phase;
    logic perf_started;

    longint unsigned perf_start_cycle;
    longint unsigned perf_end_cycle;

    always @(posedge clk) begin

        logic [7:0] expected_byte;

        if (aresetn &&
            s_axis_tvalid &&
            s_axis_tready &&
            perf_phase &&
            !perf_started) begin

            perf_started =
                1'b1;

            perf_start_cycle =
                cycle_counter;

        end

        if (aresetn &&
            m_axis_tvalid &&
            m_axis_tready) begin

            if (!output_packet_active) begin

                output_queue =
                    m_packet_queue;

                if (expected_pkt_rd[
                        output_queue
                    ] >=
                    expected_pkt_wr[
                        output_queue
                    ]) begin

                    $display(
                        "FAIL: unexpected output packet queue=%0d",
                        output_queue
                    );

                    $fatal;

                end

                output_packet_expected_length =
                    expected_length[
                        output_queue
                    ][
                        expected_pkt_rd[
                            output_queue
                        ]
                    ];

                output_packet_bytes =
                    0;

                output_packet_active =
                    1'b1;

            end
            else if (m_packet_queue !=
                     output_queue) begin

                $display(
                    "FAIL: queue changed inside packet"
                );

                $fatal;

            end

            for (lane = 0;
                 lane < 8;
                 lane = lane + 1) begin

                if (m_axis_tkeep[lane]) begin

                    if (expected_byte_rd[
                            output_queue
                        ] >=
                        expected_byte_wr[
                            output_queue
                        ]) begin

                        $display(
                            "FAIL: output byte beyond scoreboard"
                        );

                        $fatal;

                    end

                    expected_byte =
                        expected_bytes[
                            output_queue
                        ][
                            expected_byte_rd[
                                output_queue
                            ]
                        ];

                    if (m_axis_tdata[
                            lane*8 +: 8
                        ] !==
                        expected_byte) begin

                        $display(
                            "FAIL: byte mismatch queue=%0d byte=%0d",
                            output_queue,
                            output_packet_bytes
                        );

                        $fatal;

                    end

                    expected_byte_rd[
                        output_queue
                    ] =
                        expected_byte_rd[
                            output_queue
                        ] + 1;

                    output_packet_bytes =
                        output_packet_bytes + 1;

                    output_bytes =
                        output_bytes + 1;

                end

            end

            if (m_axis_tlast) begin

                if (output_packet_bytes !=
                    output_packet_expected_length) begin

                    $display(
                        "FAIL: length queue=%0d got=%0d expected=%0d",
                        output_queue,
                        output_packet_bytes,
                        output_packet_expected_length
                    );

                    $fatal;

                end

                expected_pkt_rd[
                    output_queue
                ] =
                    expected_pkt_rd[
                        output_queue
                    ] + 1;

                output_packets =
                    output_packets + 1;

                output_packet_active =
                    1'b0;

                if (perf_phase) begin

                    perf_output_packets =
                        perf_output_packets + 1;

                    if (perf_output_packets ==
                        PERF_PACKETS)
                        perf_end_cycle =
                            cycle_counter;

                end

            end

        end

    end

    /*
     * ---------------------------------------------------------
     * CONFIGURATION HELPERS
     * ---------------------------------------------------------
     */

    task automatic clear_rule_cfg;

        begin

            cfg_rule_we =
                1'b0;

            cfg_rule_index =
                5'd0;

            cfg_rule_valid =
                1'b0;

            cfg_vlan_present_value =
                1'b0;

            cfg_vlan_present_mask =
                1'b0;

            cfg_vlan_value =
                12'd0;

            cfg_vlan_mask =
                12'd0;

            cfg_src_ip_value =
                32'd0;

            cfg_src_ip_mask =
                32'd0;

            cfg_dst_ip_value =
                32'd0;

            cfg_dst_ip_mask =
                32'd0;

            cfg_protocol_value =
                8'd0;

            cfg_protocol_mask =
                8'd0;

            cfg_src_port_value =
                16'd0;

            cfg_src_port_mask =
                16'd0;

            cfg_dst_port_value =
                16'd0;

            cfg_dst_port_mask =
                16'd0;

            cfg_action =
                ACTION_DROP;

            cfg_action_queue =
                2'd0;

        end

    endtask

    task automatic write_rule(
        input integer idx,
        input logic [31:0] sip_value,
        input logic [31:0] sip_mask,
        input logic [7:0] proto_value,
        input logic [7:0] proto_mask,
        input logic [15:0] dport_value,
        input logic [15:0] dport_mask,
        input logic [2:0] action_value,
        input logic [1:0] queue_value
    );

        begin

            @(negedge clk);

            clear_rule_cfg();

            cfg_rule_index =
                idx;

            cfg_rule_valid =
                1'b1;

            cfg_src_ip_value =
                sip_value;

            cfg_src_ip_mask =
                sip_mask;

            cfg_protocol_value =
                proto_value;

            cfg_protocol_mask =
                proto_mask;

            cfg_dst_port_value =
                dport_value;

            cfg_dst_port_mask =
                dport_mask;

            cfg_action =
                action_value;

            cfg_action_queue =
                queue_value;

            cfg_rule_we =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            cfg_rule_we =
                1'b0;

        end

    endtask

    task automatic configure_queue(
        input integer queue_id,
        input integer weight,
        input integer gap_cycles
    );

        begin

            @(negedge clk);

            cfg_qos_queue =
                queue_id;

            cfg_qos_weight =
                weight;

            cfg_qos_gap_cycles =
                gap_cycles;

            cfg_qos_we =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            cfg_qos_we =
                1'b0;

        end

    endtask

    /*
     * ---------------------------------------------------------
     * MAIN QUALIFICATION
     * ---------------------------------------------------------
     */

    integer n;
    integer q;
    integer frame_length;
    integer traffic_class;

    logic [31:0] source_ip;
    logic [15:0] source_port;
    logic [15:0] destination_port;

    longint unsigned perf_cycles;
    longint unsigned perf_bytes;
    longint unsigned perf_bits;

    longint unsigned throughput_mbps_x1000;
    longint unsigned utilization_pct_x1000;

    initial begin

        s_axis_tdata =
            64'd0;

        s_axis_tkeep =
            8'd0;

        s_axis_tvalid =
            1'b0;

        s_axis_tlast =
            1'b0;

        clear_rule_cfg();

        cfg_edit_we =
            1'b0;

        cfg_edit_index =
            5'd0;

        cfg_rewrite_src_ip =
            1'b0;

        cfg_rewrite_dst_ip =
            1'b0;

        cfg_rewrite_src_port =
            1'b0;

        cfg_rewrite_dst_port =
            1'b0;

        cfg_new_src_ip =
            32'd0;

        cfg_new_dst_ip =
            32'd0;

        cfg_new_src_port =
            16'd0;

        cfg_new_dst_port =
            16'd0;

        cfg_qos_we =
            1'b0;

        cfg_qos_queue =
            2'd0;

        cfg_qos_weight =
            4'd1;

        cfg_qos_gap_cycles =
            16'd0;

        stress_backpressure =
            1'b0;

        ingress_stall_cycles =
            0;

        egress_stall_cycles =
            0;

        output_packet_active =
            1'b0;

        output_packets =
            0;

        output_bytes =
            0;

        perf_phase =
            1'b0;

        perf_started =
            1'b0;

        perf_output_packets =
            0;

        perf_start_cycle =
            0;

        perf_end_cycle =
            0;

        for (q = 0; q < 4; q = q + 1) begin

            expected_byte_wr[q] = 0;
            expected_byte_rd[q] = 0;

            expected_pkt_wr[q] = 0;
            expected_pkt_rd[q] = 0;

        end

        repeat (10)
            @(posedge clk);

        aresetn =
            1'b1;

        repeat (5)
            @(posedge clk);

        /*
         * RULE 0:
         * exact source 10.0.0.50 -> DROP
         */
        write_rule(
            0,
            32'h0A000032,
            32'hFFFFFFFF,
            8'd0,
            8'd0,
            16'd0,
            16'd0,
            ACTION_DROP,
            2'd0
        );

        /*
         * RULE 1:
         * UDP destination 5000 -> FORWARD Q0
         */
        write_rule(
            1,
            32'd0,
            32'd0,
            8'd17,
            8'hFF,
            16'd5000,
            16'hFFFF,
            ACTION_FORWARD,
            2'd0
        );

        /*
         * RULE 2:
         * UDP destination 8000 -> REDIRECT Q2
         */
        write_rule(
            2,
            32'd0,
            32'd0,
            8'd17,
            8'hFF,
            16'd8000,
            16'hFFFF,
            ACTION_REDIRECT,
            2'd2
        );

        configure_queue(0, 2, 0);
        configure_queue(1, 1, 0);
        configure_queue(2, 1, 0);
        configure_queue(3, 1, 0);

        /*
         * =====================================================
         * PHASE 1 — SATURATED PERFORMANCE BASELINE
         * =====================================================
         */

        $display("");
        $display(
            "===== 08J PHASE 1: SATURATED FORWARD STREAM ====="
        );

        stress_backpressure =
            1'b0;

        perf_phase =
            1'b1;

        perf_started =
            1'b0;

        perf_output_packets =
            0;

        for (n = 0;
             n < PERF_PACKETS;
             n = n + 1) begin

            source_ip =
                32'h0A100000 +
                n +
                1;

            source_port =
                16'd10000 +
                (n & 16'h3FFF);

            build_udp_exact(
                n,
                PERF_FRAME_BYTES,
                source_ip,
                32'hC0A80101,
                source_port,
                16'd5000
            );

            expect_current_packet(
                0
            );

            send_current_packet_continuous();

        end

        end_source_stream();

        wait (
            perf_output_packets ==
            PERF_PACKETS
        );

        perf_phase =
            1'b0;

        repeat (10)
            @(posedge clk);

        perf_cycles =
            perf_end_cycle -
            perf_start_cycle +
            1;

        perf_bytes =
            PERF_PACKETS *
            PERF_FRAME_BYTES;

        perf_bits =
            perf_bytes * 8;

        /*
         * Mbps * 1000
         *
         * bits * 125 MHz / cycles / 1e6 * 1000
         * = bits * 125000 / cycles
         */
        throughput_mbps_x1000 =
            (perf_bits * 125000) /
            perf_cycles;

        /*
         * Percentage of 8,000 Mbps raw 64b/125MHz bus,
         * multiplied by 1000.
         */
        utilization_pct_x1000 =
            (throughput_mbps_x1000 *
             100) /
            8000;

        if (packets_accepted !=
            PERF_PACKETS ||
            packets_forwarded !=
            PERF_PACKETS ||
            packets_dropped !=
            0 ||
            scheduler_transmitted !=
            PERF_PACKETS) begin

            $display(
                "FAIL: phase1 accounting accepted=%0d forward=%0d drop=%0d tx=%0d",
                packets_accepted,
                packets_forwarded,
                packets_dropped,
                scheduler_transmitted
            );

            $fatal;

        end

        $display(
            "SATURATED FORWARD ACCOUNTING: PASS"
        );

        $display(
            "PERF_PACKETS=%0d",
            PERF_PACKETS
        );

        $display(
            "PERF_FRAME_BYTES=%0d",
            PERF_FRAME_BYTES
        );

        $display(
            "PERF_BYTES=%0d",
            perf_bytes
        );

        $display(
            "PERF_CYCLES=%0d",
            perf_cycles
        );

        $display(
            "PERF_THROUGHPUT_Mbps=%0d.%03d",
            throughput_mbps_x1000 / 1000,
            throughput_mbps_x1000 % 1000
        );

        $display(
            "PERF_RAW_BUS_UTILIZATION_PCT=%0d.%03d",
            utilization_pct_x1000 / 1000,
            utilization_pct_x1000 % 1000
        );

        /*
         * =====================================================
         * PHASE 2 — VARIABLE LENGTH / MIXED POLICY STRESS
         * =====================================================
         */

        $display("");
        $display(
            "===== 08J PHASE 2: MIXED POLICY / BACKPRESSURE ====="
        );

        stress_backpressure =
            1'b1;

        for (n = 0;
             n < STRESS_PACKETS;
             n = n + 1) begin

            frame_length =
                64 +
                ((n * 73 + 19) %
                 448);

            traffic_class =
                n % 4;

            source_ip =
                32'h0A200000 +
                n +
                1;

            source_port =
                16'd20000 +
                (n & 16'h3FFF);

            case (traffic_class)

                0: begin

                    destination_port =
                        16'd5000;

                    build_udp_exact(
                        2000 + n,
                        frame_length,
                        source_ip,
                        32'hC0A80201,
                        source_port,
                        destination_port
                    );

                    expect_current_packet(
                        0
                    );

                end

                1: begin

                    destination_port =
                        16'd8000;

                    build_udp_exact(
                        2000 + n,
                        frame_length,
                        source_ip,
                        32'hC0A80202,
                        source_port,
                        destination_port
                    );

                    expect_current_packet(
                        2
                    );

                end

                2: begin

                    /*
                     * Priority DROP rule.
                     */
                    source_ip =
                        32'h0A000032;

                    destination_port =
                        16'd5000;

                    build_udp_exact(
                        2000 + n,
                        frame_length,
                        source_ip,
                        32'hC0A80203,
                        source_port,
                        destination_port
                    );

                end

                default: begin

                    destination_port =
                        16'd5000;

                    build_udp_exact(
                        2000 + n,
                        frame_length,
                        source_ip,
                        32'hC0A80204,
                        source_port,
                        destination_port
                    );

                    expect_current_packet(
                        0
                    );

                end

            endcase

            send_current_packet_continuous();

        end

        end_source_stream();

        wait (
            packets_accepted ==
            (PERF_PACKETS +
             STRESS_PACKETS)
        );

        wait (
            packets_dropped ==
            128
        );

        wait (
            scheduler_transmitted ==
            (PERF_PACKETS + 384)
        );

        repeat (20)
            @(posedge clk);

        $display(
            "VARIABLE-LENGTH TRAFFIC: PASS"
        );

        $display(
            "MIXED FORWARD/REDIRECT/DROP: PASS"
        );

        $display(
            "RANDOMIZED BACKPRESSURE: PASS"
        );

        /*
         * =====================================================
         * PHASE 3 — LIVE POLICY UPDATE AFTER STRESS
         * =====================================================
         */

        $display("");
        $display(
            "===== 08J PHASE 3: LIVE POLICY CHANGE ====="
        );

        /*
         * Rule 1 changes:
         *
         * UDP :5000 FORWARD -> DROP
         *
         * No reset and no RTL rebuild.
         */
        write_rule(
            1,
            32'd0,
            32'd0,
            8'd17,
            8'hFF,
            16'd5000,
            16'hFFFF,
            ACTION_DROP,
            2'd0
        );

        for (n = 0;
             n < UPDATE_PACKETS;
             n = n + 1) begin

            frame_length =
                64 +
                ((n * 37 + 11) %
                 320);

            source_ip =
                32'h0A300000 +
                n +
                1;

            source_port =
                16'd30000 +
                n;

            build_udp_exact(
                4000 + n,
                frame_length,
                source_ip,
                32'hC0A80301,
                source_port,
                16'd5000
            );

            /*
             * No output is expected.
             */
            send_current_packet_continuous();

        end

        end_source_stream();

        wait (
            packets_accepted ==
            (PERF_PACKETS +
             STRESS_PACKETS +
             UPDATE_PACKETS)
        );

        wait (
            packets_dropped ==
            (128 +
             UPDATE_PACKETS)
        );

        repeat (30)
            @(posedge clk);

        if (scheduler_transmitted !=
            (PERF_PACKETS + 384)) begin

            $display(
                "FAIL: post-update packets leaked to scheduler tx=%0d",
                scheduler_transmitted
            );

            $fatal;

        end

        $display(
            "LIVE POLICY UPDATE UNDER QUALIFIED CORE: PASS"
        );

        /*
         * -----------------------------------------------------
         * FINAL SCOREBOARD
         * -----------------------------------------------------
         */

        for (q = 0;
             q < 4;
             q = q + 1) begin

            if (expected_pkt_rd[q] !=
                expected_pkt_wr[q]) begin

                $display(
                    "FAIL: packet scoreboard q=%0d rd=%0d wr=%0d",
                    q,
                    expected_pkt_rd[q],
                    expected_pkt_wr[q]
                );

                $fatal;

            end

            if (expected_byte_rd[q] !=
                expected_byte_wr[q]) begin

                $display(
                    "FAIL: byte scoreboard q=%0d rd=%0d wr=%0d",
                    q,
                    expected_byte_rd[q],
                    expected_byte_wr[q]
                );

                $fatal;

            end

        end

        if (packets_accepted != 1664) begin

            $display(
                "FAIL: final accepted=%0d expected=1664",
                packets_accepted
            );

            $fatal;

        end

        if (packets_forwarded != 1408) begin

            $display(
                "FAIL: final forwarded=%0d expected=1408",
                packets_forwarded
            );

            $fatal;

        end

        if (packets_dropped != 256) begin

            $display(
                "FAIL: final dropped=%0d expected=256",
                packets_dropped
            );

            $fatal;

        end

        if (scheduler_enqueued != 1408 ||
            scheduler_transmitted != 1408 ||
            output_packets != 1408) begin

            $display(
                "FAIL: output accounting enq=%0d tx=%0d observed=%0d",
                scheduler_enqueued,
                scheduler_transmitted,
                output_packets
            );

            $fatal;

        end

        if (ingress_stall_cycles == 0) begin

            $display(
                "FAIL: sustained traffic produced no ingress stalls"
            );

            $fatal;

        end

        if (egress_stall_cycles == 0) begin

            $display(
                "FAIL: stress phase produced no egress stalls"
            );

            $fatal;

        end

        $display("");
        $display(
            "============================================"
        );
        $display(
            " PROJECT08 08J SUSTAINED TRAFFIC: PASS"
        );
        $display(
            "============================================"
        );
        $display(
            " Integrated packets injected : %0d",
            packets_accepted
        );
        $display(
            " Packets forwarded           : %0d",
            packets_forwarded
        );
        $display(
            " Packets dropped             : %0d",
            packets_dropped
        );
        $display(
            " Output packets              : %0d",
            scheduler_transmitted
        );
        $display(
            " Unique flow stimulus        : >1600"
        );
        $display(
            " Variable packet lengths     : PASS"
        );
        $display(
            " Priority policy             : PASS"
        );
        $display(
            " Redirect traffic            : PASS"
        );
        $display(
            " Live policy update          : PASS"
        );
        $display(
            " Byte-perfect scoreboard     : PASS"
        );
        $display(
            " Ingress backpressure        : PASS"
        );
        $display(
            " Egress backpressure         : PASS"
        );
        $display(
            " Ingress stall cycles        : %0d",
            ingress_stall_cycles
        );
        $display(
            " Egress stall cycles         : %0d",
            egress_stall_cycles
        );
        $display(
            " Performance packets         : %0d",
            PERF_PACKETS
        );
        $display(
            " Performance frame bytes     : %0d",
            PERF_FRAME_BYTES
        );
        $display(
            " Performance cycles          : %0d",
            perf_cycles
        );
        $display(
            " Sustained simulated rate    : %0d.%03d Mbit/s",
            throughput_mbps_x1000 / 1000,
            throughput_mbps_x1000 % 1000
        );
        $display(
            " Raw AXIS utilization        : %0d.%03d %%",
            utilization_pct_x1000 / 1000,
            utilization_pct_x1000 % 1000
        );
        $display(
            "============================================"
        );

        $finish;

    end

    initial begin

        #200_000_000;

        $display(
            "FAIL: Project08 08J simulation timeout"
        );

        $fatal;

    end

endmodule
