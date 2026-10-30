`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Verification:
 *   End-to-End Integrated Programmable Packet Processor
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module tb_p08_packet_processor_core;

    localparam logic [2:0] ACTION_FORWARD  = 3'd0;
    localparam logic [2:0] ACTION_DROP     = 3'd1;
    localparam logic [2:0] ACTION_REDIRECT = 3'd2;
    localparam logic [2:0] ACTION_MODIFY   = 3'd3;

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
     * Deterministic external backpressure.
     */
    integer cycle_counter = 0;
    integer output_stalls = 0;

    always @(posedge clk) begin

        if (!aresetn)
            cycle_counter <= 0;
        else
            cycle_counter <= cycle_counter + 1;

    end

    always_comb begin

        if (!aresetn)
            m_axis_tready = 1'b0;
        else
            m_axis_tready =
                ((cycle_counter % 5) != 0);

    end

    always @(posedge clk) begin

        if (aresetn &&
            m_axis_tvalid &&
            !m_axis_tready)
            output_stalls =
                output_stalls + 1;

    end

    logic [7:0] tx_mem [0:2047];
    logic [7:0] saved_mem [0:2047];
    logic [7:0] rx_mem [0:2047];

    integer tx_len;
    integer rx_len;

    logic rx_active;
    logic rx_complete;

    logic [1:0] rx_queue;

    integer output_packets = 0;

    integer lane;

    always @(posedge clk) begin

        if (aresetn &&
            m_axis_tvalid &&
            m_axis_tready) begin

            if (!rx_active) begin

                rx_len =
                    0;

                rx_queue =
                    m_packet_queue;

                rx_active =
                    1'b1;

            end
            else if (m_packet_queue !=
                     rx_queue) begin

                $display(
                    "FAIL: queue changed inside packet"
                );

                $fatal;

            end

            for (lane = 0;
                 lane < 8;
                 lane = lane + 1) begin

                if (m_axis_tkeep[lane]) begin

                    rx_mem[rx_len] =
                        m_axis_tdata[
                            lane*8 +: 8
                        ];

                    rx_len =
                        rx_len + 1;

                end

            end

            if (m_axis_tlast) begin

                rx_active =
                    1'b0;

                rx_complete =
                    1'b1;

                output_packets =
                    output_packets + 1;

            end

        end

    end

    task automatic clear_cfg;

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

            clear_cfg();

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

    task automatic write_edit_profile(
        input integer idx,
        input logic [31:0] dst_ip,
        input logic [15:0] dst_port_value
    );

        begin

            @(negedge clk);

            cfg_edit_index =
                idx;

            cfg_rewrite_src_ip =
                1'b0;

            cfg_rewrite_dst_ip =
                1'b1;

            cfg_rewrite_src_port =
                1'b0;

            cfg_rewrite_dst_port =
                1'b1;

            cfg_new_src_ip =
                32'd0;

            cfg_new_dst_ip =
                dst_ip;

            cfg_new_src_port =
                16'd0;

            cfg_new_dst_port =
                dst_port_value;

            cfg_edit_we =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            cfg_edit_we =
                1'b0;

        end

    endtask

    task automatic configure_queue(
        input integer q,
        input integer weight,
        input integer gap
    );

        begin

            @(negedge clk);

            cfg_qos_queue =
                q;

            cfg_qos_weight =
                weight;

            cfg_qos_gap_cycles =
                gap;

            cfg_qos_we =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            cfg_qos_we =
                1'b0;

        end

    endtask

    task automatic clear_packet;

        begin

            tx_len = 0;

        end

    endtask

    task automatic put8(
        input logic [7:0] value
    );

        begin

            tx_mem[tx_len] =
                value;

            tx_len =
                tx_len + 1;

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

    task automatic build_udp(
        input logic [31:0] sip,
        input logic [31:0] dip,
        input logic [15:0] sport,
        input logic [15:0] dport,
        input integer payload_length
    );

        integer n;
        integer ip_length;
        integer udp_length;

        begin

            clear_packet();

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

            ip_length =
                20 +
                8 +
                payload_length;

            udp_length =
                8 +
                payload_length;

            /*
             * IPv4.
             */
            put8(8'h45);
            put8(8'h00);

            put16be(
                ip_length[15:0]
            );

            put16be(16'h1234);
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

            put16be(
                udp_length[15:0]
            );

            put16be(16'h0000);

            for (n = 0;
                 n < payload_length;
                 n = n + 1)
                put8(
                    (8'h60 + n) &
                    8'hFF
                );

        end

    endtask

    task automatic preserve_packet;

        integer n;

        begin

            for (n = 0;
                 n < tx_len;
                 n = n + 1)
                saved_mem[n] =
                    tx_mem[n];

        end

    endtask

    task automatic prepare_rx;

        begin

            rx_complete =
                1'b0;

        end

    endtask

    task automatic send_packet;

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

                data =
                    64'd0;

                keep =
                    8'd0;

                for (k = 0;
                     k < beat_length;
                     k = k + 1) begin

                    data[
                        k*8 +: 8
                    ] =
                        tx_mem[
                            offset + k
                        ];

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

    task automatic verify_exact(
        input logic [1:0] expected_queue
    );

        integer n;

        begin

            wait (
                rx_complete === 1'b1
            );

            #1;

            if (rx_queue !==
                expected_queue) begin

                $display(
                    "FAIL: queue=%0d expected=%0d",
                    rx_queue,
                    expected_queue
                );

                $fatal;

            end

            if (rx_len != tx_len) begin

                $display(
                    "FAIL: length=%0d expected=%0d",
                    rx_len,
                    tx_len
                );

                $fatal;

            end

            for (n = 0;
                 n < tx_len;
                 n = n + 1) begin

                if (rx_mem[n] !==
                    saved_mem[n]) begin

                    $display(
                        "FAIL: exact packet mismatch byte=%0d",
                        n
                    );

                    $fatal;

                end

            end

        end

    endtask

    function automatic [15:0] fold_sum(
        input integer value
    );

        integer temp;

        begin

            temp = value;

            while ((temp >> 16) != 0)
                temp =
                    (temp & 16'hFFFF) +
                    (temp >> 16);

            fold_sum =
                temp[15:0];

        end

    endfunction

    task automatic verify_ipv4_checksum;

        integer n;
        integer sum;
        integer word_value;

        begin

            sum = 0;

            for (n = 14;
                 n < 34;
                 n = n + 2) begin

                word_value =
                    (rx_mem[n] << 8) |
                    rx_mem[n+1];

                sum =
                    sum +
                    word_value;

            end

            if (fold_sum(sum) !=
                16'hFFFF) begin

                $display(
                    "FAIL: IPv4 checksum"
                );

                $fatal;

            end

        end

    endtask

    task automatic verify_udp_checksum;

        integer ip_len;
        integer udp_len;
        integer n;
        integer sum;
        integer word_value;

        begin

            ip_len =
                (rx_mem[16] << 8) |
                rx_mem[17];

            udp_len =
                ip_len - 20;

            sum = 0;

            sum +=
                (rx_mem[26] << 8) |
                rx_mem[27];

            sum +=
                (rx_mem[28] << 8) |
                rx_mem[29];

            sum +=
                (rx_mem[30] << 8) |
                rx_mem[31];

            sum +=
                (rx_mem[32] << 8) |
                rx_mem[33];

            sum +=
                17;

            sum +=
                udp_len;

            for (n = 34;
                 n < (34 + udp_len);
                 n = n + 2) begin

                if ((n + 1) <
                    (34 + udp_len))
                    word_value =
                        (rx_mem[n] << 8) |
                        rx_mem[n+1];
                else
                    word_value =
                        rx_mem[n] << 8;

                sum =
                    sum +
                    word_value;

            end

            if (fold_sum(sum) !=
                16'hFFFF) begin

                $display(
                    "FAIL: UDP checksum"
                );

                $fatal;

            end

        end

    endtask

    integer previous_outputs;
    integer previous_drops;

    initial begin

        s_axis_tdata =
            64'd0;

        s_axis_tkeep =
            8'd0;

        s_axis_tvalid =
            1'b0;

        s_axis_tlast =
            1'b0;

        clear_cfg();

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

        rx_len =
            0;

        rx_active =
            1'b0;

        rx_complete =
            1'b0;

        repeat (10)
            @(posedge clk);

        aresetn =
            1'b1;

        repeat (4)
            @(posedge clk);

        /*
         * -----------------------------------------------------
         * QoS defaults.
         * -----------------------------------------------------
         */
        configure_queue(0, 1, 0);
        configure_queue(1, 1, 0);
        configure_queue(2, 1, 0);
        configure_queue(3, 1, 0);

        /*
         * -----------------------------------------------------
         * RULE 0
         *
         * Source 10.0.0.50 -> DROP
         * -----------------------------------------------------
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
         * RULE 1
         * UDP destination 5000 -> FORWARD queue 0.
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
         * RULE 2
         * UDP destination 8000 -> REDIRECT queue 2.
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

        /*
         * RULE 3
         * UDP destination 9000 -> MODIFY queue 1.
         */
        write_rule(
            3,
            32'd0,
            32'd0,
            8'd17,
            8'hFF,
            16'd9000,
            16'hFFFF,
            ACTION_MODIFY,
            2'd1
        );

        write_edit_profile(
            3,
            32'hAC100064,
            16'd9100
        );

        $display("");
        $display(
            "===== 08H TEST 1: PRIORITY DROP ====="
        );

        previous_outputs =
            output_packets;

        previous_drops =
            packets_dropped;

        build_udp(
            32'h0A000032,
            32'hC0A80101,
            16'd1234,
            16'd5000,
            24
        );

        send_packet();

        wait (
            packets_dropped ==
            previous_drops + 1
        );

        repeat (20)
            @(posedge clk);

        if (output_packets !=
            previous_outputs) begin

            $display(
                "FAIL: dropped packet reached output"
            );

            $fatal;

        end

        $display(
            "PRIORITY DROP END-TO-END: PASS"
        );

        /*
         * -----------------------------------------------------
         * TEST 2 — FORWARD.
         * -----------------------------------------------------
         */
        $display("");
        $display(
            "===== 08H TEST 2: FORWARD ====="
        );

        build_udp(
            32'h0A000001,
            32'hC0A80101,
            16'd1234,
            16'd5000,
            27
        );

        preserve_packet();
        prepare_rx();
        send_packet();

        verify_exact(
            2'd0
        );

        $display(
            "FORWARD END-TO-END: PASS"
        );

        /*
         * -----------------------------------------------------
         * TEST 3 — REDIRECT queue 2.
         * -----------------------------------------------------
         */
        $display("");
        $display(
            "===== 08H TEST 3: REDIRECT ====="
        );

        build_udp(
            32'h0A000002,
            32'hC0A80102,
            16'd2000,
            16'd8000,
            19
        );

        preserve_packet();
        prepare_rx();
        send_packet();

        verify_exact(
            2'd2
        );

        $display(
            "REDIRECT END-TO-END: PASS"
        );

        /*
         * -----------------------------------------------------
         * TEST 4 — MODIFY.
         * -----------------------------------------------------
         */
        $display("");
        $display(
            "===== 08H TEST 4: MODIFY ====="
        );

        build_udp(
            32'h0A000003,
            32'hC0A80103,
            16'd3000,
            16'd9000,
            21
        );

        prepare_rx();
        send_packet();

        wait (
            rx_complete === 1'b1
        );

        #1;

        if (rx_queue !==
            2'd1) begin

            $display(
                "FAIL: MODIFY queue=%0d expected=1",
                rx_queue
            );

            $fatal;

        end

        if ({
            rx_mem[30],
            rx_mem[31],
            rx_mem[32],
            rx_mem[33]
        } !== 32'hAC100064) begin

            $display(
                "FAIL: destination IPv4 not modified"
            );

            $fatal;

        end

        if ({
            rx_mem[36],
            rx_mem[37]
        } !== 16'd9100) begin

            $display(
                "FAIL: destination UDP port not modified"
            );

            $fatal;

        end

        verify_ipv4_checksum();
        verify_udp_checksum();

        $display(
            "MODIFY + CHECKSUM END-TO-END: PASS"
        );

        /*
         * -----------------------------------------------------
         * TEST 5 — LIVE POLICY UPDATE.
         *
         * Rewrite rule 1 from FORWARD to DROP.
         * No reset. No FPGA rebuild.
         * -----------------------------------------------------
         */
        $display("");
        $display(
            "===== 08H TEST 5: LIVE RULE UPDATE ====="
        );

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

        previous_outputs =
            output_packets;

        previous_drops =
            packets_dropped;

        build_udp(
            32'h0A000001,
            32'hC0A80101,
            16'd1234,
            16'd5000,
            25
        );

        send_packet();

        wait (
            packets_dropped ==
            previous_drops + 1
        );

        repeat (20)
            @(posedge clk);

        if (output_packets !=
            previous_outputs) begin

            $display(
                "FAIL: live-updated DROP still produced output"
            );

            $fatal;

        end

        $display(
            "LIVE RULE UPDATE END-TO-END: PASS"
        );

        if (packets_accepted != 5) begin

            $display(
                "FAIL: accepted=%0d expected=5",
                packets_accepted
            );

            $fatal;

        end

        if (packets_forwarded != 3) begin

            $display(
                "FAIL: non-drop=%0d expected=3",
                packets_forwarded
            );

            $fatal;

        end

        if (packets_dropped != 2) begin

            $display(
                "FAIL: dropped=%0d expected=2",
                packets_dropped
            );

            $fatal;

        end

        if (scheduler_enqueued != 3 ||
            scheduler_transmitted != 3 ||
            output_packets != 3) begin

            $display(
                "FAIL: scheduler/output accounting enq=%0d tx=%0d out=%0d",
                scheduler_enqueued,
                scheduler_transmitted,
                output_packets
            );

            $fatal;

        end

        if (output_stalls == 0) begin

            $display(
                "FAIL: output backpressure not exercised"
            );

            $fatal;

        end

        $display("");
        $display(
            "============================================"
        );
        $display(
            " PROJECT08 08H INTEGRATED CORE: PASS"
        );
        $display(
            "============================================"
        );
        $display(
            " Parser integration          : PASS"
        );
        $display(
            " Match/action integration    : PASS"
        );
        $display(
            " Decision synchronization    : PASS"
        );
        $display(
            " Priority DROP               : PASS"
        );
        $display(
            " FORWARD datapath            : PASS"
        );
        $display(
            " REDIRECT queue routing      : PASS"
        );
        $display(
            " MODIFY packet rewrite       : PASS"
        );
        $display(
            " IPv4 checksum               : PASS"
        );
        $display(
            " UDP checksum                : PASS"
        );
        $display(
            " QoS scheduler integration   : PASS"
        );
        $display(
            " Runtime rule update         : PASS"
        );
        $display(
            " Output backpressure         : PASS"
        );
        $display(
            " Packets accepted            : %0d",
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
            " Scheduler packets           : %0d",
            scheduler_transmitted
        );
        $display(
            " Output stall cycles         : %0d",
            output_stalls
        );
        $display(
            "============================================"
        );

        $finish;

    end

    initial begin

        #40_000_000;

        $display(
            "FAIL: Project08 08H simulation timeout"
        );

        $fatal;

    end

endmodule
