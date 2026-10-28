`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Verification:
 *   Ethernet / VLAN / IPv4 / UDP / TCP packet parser
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module tb_p08_packet_parser;

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

    logic        metadata_valid;

    logic [15:0] packet_length;

    logic [47:0] dst_mac;
    logic [47:0] src_mac;

    logic        vlan_present;
    logic [11:0] vlan_id;

    logic [15:0] ethertype;

    logic        ipv4_valid;
    logic [31:0] src_ipv4;
    logic [31:0] dst_ipv4;
    logic [7:0]  ip_protocol;

    logic        l4_valid;
    logic [15:0] src_port;
    logic [15:0] dst_port;

    logic        udp_valid;
    logic        tcp_valid;

    logic        malformed;

    p08_packet_parser dut (

        .clk            (clk),
        .aresetn        (aresetn),

        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tkeep   (s_axis_tkeep),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),

        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tkeep   (m_axis_tkeep),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast),

        .metadata_valid (metadata_valid),

        .packet_length  (packet_length),

        .dst_mac        (dst_mac),
        .src_mac        (src_mac),

        .vlan_present   (vlan_present),
        .vlan_id        (vlan_id),

        .ethertype      (ethertype),

        .ipv4_valid     (ipv4_valid),
        .src_ipv4       (src_ipv4),
        .dst_ipv4       (dst_ipv4),
        .ip_protocol    (ip_protocol),

        .l4_valid       (l4_valid),
        .src_port       (src_port),
        .dst_port       (dst_port),

        .udp_valid      (udp_valid),
        .tcp_valid      (tcp_valid),

        .malformed      (malformed)
    );

    /*
     * Deterministic backpressure.
     */
    integer cycle_counter = 0;

    always @(posedge clk) begin

        if (!aresetn)
            cycle_counter <= 0;
        else
            cycle_counter <=
                cycle_counter + 1;

    end

    always_comb begin

        if (!aresetn)
            m_axis_tready = 1'b0;
        else
            m_axis_tready =
                ((cycle_counter % 5) != 0);

    end

    integer stall_cycles = 0;

    always @(posedge clk) begin

        if (aresetn &&
            s_axis_tvalid &&
            !s_axis_tready)
            stall_cycles =
                stall_cycles + 1;

    end

    /*
     * Packet construction workspace.
     */
    logic [7:0] packet_mem [0:511];

    integer plen;

    logic [7:0] expected_bytes[$];

    task automatic clear_packet;

        begin
            plen = 0;
        end

    endtask

    task automatic put8(
        input logic [7:0] value
    );

        begin

            packet_mem[plen] =
                value;

            plen = plen + 1;

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

    task automatic build_eth_header(
        input logic        use_vlan,
        input logic [11:0] vid,
        input logic [15:0] final_ethertype
    );

        begin

            /*
             * Destination MAC 02:11:22:33:44:55
             */
            put8(8'h02);
            put8(8'h11);
            put8(8'h22);
            put8(8'h33);
            put8(8'h44);
            put8(8'h55);

            /*
             * Source MAC 02:AA:BB:CC:DD:EE
             */
            put8(8'h02);
            put8(8'hAA);
            put8(8'hBB);
            put8(8'hCC);
            put8(8'hDD);
            put8(8'hEE);

            if (use_vlan) begin

                put16be(16'h8100);
                put16be({4'h0, vid});
                put16be(final_ethertype);

            end
            else begin

                put16be(final_ethertype);

            end

        end

    endtask

    task automatic build_udp_packet(
        input logic        use_vlan,
        input logic [11:0] vid,
        input integer      ihl_words,
        input logic [31:0] sip,
        input logic [31:0] dip,
        input logic [15:0] sport,
        input logic [15:0] dport,
        input integer      payload_bytes
    );

        integer ip_length;
        integer udp_length;
        integer n;

        begin

            clear_packet();

            build_eth_header(
                use_vlan,
                vid,
                16'h0800
            );

            ip_length =
                ihl_words * 4 +
                8 +
                payload_bytes;

            udp_length =
                8 +
                payload_bytes;

            put8(
                8'h40 +
                ihl_words[3:0]
            );

            put8(8'h00);

            put16be(
                ip_length[15:0]
            );

            put16be(16'h1234);
            put16be(16'h4000);

            put8(8'h40);     // TTL
            put8(8'd17);     // UDP

            put16be(16'h0000);

            put32be(sip);
            put32be(dip);

            /*
             * IPv4 options for IHL > 5.
             */
            for (n = 0;
                 n < ((ihl_words * 4) - 20);
                 n = n + 1)
                put8(8'h01);

            put16be(sport);
            put16be(dport);

            put16be(
                udp_length[15:0]
            );

            put16be(16'h0000);

            for (n = 0;
                 n < payload_bytes;
                 n = n + 1)
                put8(
                    (8'h80 + n) &
                    8'hFF
                );

        end

    endtask

    task automatic build_tcp_packet;

        integer n;

        begin

            clear_packet();

            build_eth_header(
                1'b0,
                12'd0,
                16'h0800
            );

            put8(8'h45);
            put8(8'h00);

            put16be(16'd48);

            put16be(16'h5678);
            put16be(16'h4000);

            put8(8'h40);
            put8(8'd6);

            put16be(16'h0000);

            put32be(32'hAC100001);
            put32be(32'hAC100002);

            /*
             * TCP header.
             */
            put16be(16'd55000);
            put16be(16'd443);

            put32be(32'h01020304);
            put32be(32'h00000000);

            put8(8'h50);
            put8(8'h02);

            put16be(16'hFFFF);
            put16be(16'h0000);
            put16be(16'h0000);

            /*
             * Eight bytes payload.
             */
            for (n = 0; n < 8; n = n + 1)
                put8(8'hA0 + n);

        end

    endtask

    task automatic build_non_ipv4;

        begin

            clear_packet();

            build_eth_header(
                1'b0,
                12'd0,
                16'h0806
            );

            while (plen < 60)
                put8(plen & 8'hFF);

        end

    endtask

    task automatic build_truncated_eth;

        integer n;

        begin

            clear_packet();

            for (n = 0; n < 10; n = n + 1)
                put8(8'hD0 + n);

        end

    endtask

    task automatic send_current_packet;

        integer offset;
        integer lane;
        integer beat_length;

        logic [63:0] beat_data;
        logic [7:0]  beat_keep;

        begin

            for (offset = 0;
                 offset < plen;
                 offset = offset + 1)
                expected_bytes.push_back(
                    packet_mem[offset]
                );

            offset = 0;

            while (offset < plen) begin

                if ((plen - offset) > 8)
                    beat_length = 8;
                else
                    beat_length =
                        plen - offset;

                beat_data = 64'd0;
                beat_keep = 8'd0;

                for (lane = 0;
                     lane < beat_length;
                     lane = lane + 1) begin

                    beat_data[
                        lane*8 +: 8
                    ] =
                        packet_mem[
                            offset + lane
                        ];

                    beat_keep[lane] =
                        1'b1;

                end

                @(negedge clk);

                s_axis_tdata  = beat_data;
                s_axis_tkeep  = beat_keep;
                s_axis_tvalid = 1'b1;

                s_axis_tlast =
                    ((offset +
                      beat_length)
                     == plen);

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

    /*
     * Byte-accurate pass-through scoreboard.
     */
    integer lane_index;
    logic [7:0] expected_byte;

    always @(posedge clk) begin

        if (aresetn &&
            m_axis_tvalid &&
            m_axis_tready) begin

            for (lane_index = 0;
                 lane_index < 8;
                 lane_index =
                    lane_index + 1) begin

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
                            "FAIL: pass-through byte mismatch"
                        );

                        $fatal;

                    end

                end

            end

        end

    end

    integer tests_passed = 0;

    task automatic expect_metadata(
        input string       test_name,

        input integer      exp_length,

        input logic        exp_vlan,
        input logic [11:0] exp_vlan_id,

        input logic [15:0] exp_ethertype,

        input logic        exp_ipv4,
        input logic [31:0] exp_sip,
        input logic [31:0] exp_dip,
        input logic [7:0]  exp_protocol,

        input logic        exp_l4,
        input logic [15:0] exp_sport,
        input logic [15:0] exp_dport,

        input logic        exp_udp,
        input logic        exp_tcp,

        input logic        exp_malformed
    );

        begin

            wait (
                metadata_valid === 1'b1
            );

            #1;

            if (packet_length !==
                exp_length[15:0] ||

                vlan_present !==
                exp_vlan ||

                vlan_id !==
                exp_vlan_id ||

                ethertype !==
                exp_ethertype ||

                ipv4_valid !==
                exp_ipv4 ||

                src_ipv4 !==
                exp_sip ||

                dst_ipv4 !==
                exp_dip ||

                ip_protocol !==
                exp_protocol ||

                l4_valid !==
                exp_l4 ||

                src_port !==
                exp_sport ||

                dst_port !==
                exp_dport ||

                udp_valid !==
                exp_udp ||

                tcp_valid !==
                exp_tcp ||

                malformed !==
                exp_malformed) begin

                $display(
                    "FAIL: %s",
                    test_name
                );

                $display(
                    " len=%0d vlan=%0d vid=%0d et=%04x",
                    packet_length,
                    vlan_present,
                    vlan_id,
                    ethertype
                );

                $display(
                    " ipv4=%0d sip=%08x dip=%08x proto=%0d",
                    ipv4_valid,
                    src_ipv4,
                    dst_ipv4,
                    ip_protocol
                );

                $display(
                    " l4=%0d sport=%0d dport=%0d udp=%0d tcp=%0d malformed=%0d",
                    l4_valid,
                    src_port,
                    dst_port,
                    udp_valid,
                    tcp_valid,
                    malformed
                );

                $fatal;

            end

            if (expected_bytes.size()
                != 0) begin

                $display(
                    "FAIL: %s output scoreboard not empty: %0d",
                    test_name,
                    expected_bytes.size()
                );

                $fatal;

            end

            tests_passed =
                tests_passed + 1;

            $display(
                "TEST %s: PASS",
                test_name
            );

        end

    endtask

    initial begin

        s_axis_tdata  = 64'd0;
        s_axis_tkeep  = 8'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        repeat (10)
            @(posedge clk);

        aresetn = 1'b1;

        repeat (4)
            @(posedge clk);

        /*
         * -----------------------------------------------------
         * TEST 1
         * Plain Ethernet / IPv4 / UDP.
         * -----------------------------------------------------
         */

        build_udp_packet(
            1'b0,
            12'd0,
            5,
            32'h0A000001,
            32'hC0A80164,
            16'd1234,
            16'd5000,
            23
        );

        send_current_packet();

        expect_metadata(
            "IPv4_UDP",
            plen,
            1'b0,
            12'd0,
            16'h0800,
            1'b1,
            32'h0A000001,
            32'hC0A80164,
            8'd17,
            1'b1,
            16'd1234,
            16'd5000,
            1'b1,
            1'b0,
            1'b0
        );

        if (dst_mac !==
            48'h021122334455 ||
            src_mac !==
            48'h02AABBCCDDEE) begin

            $display(
                "FAIL: MAC extraction"
            );

            $fatal;

        end

        /*
         * -----------------------------------------------------
         * TEST 2
         * VLAN + IPv4 options + UDP.
         * -----------------------------------------------------
         */

        build_udp_packet(
            1'b1,
            12'd100,
            6,
            32'hC0A80A01,
            32'hC0A80A02,
            16'd1111,
            16'd2222,
            17
        );

        send_current_packet();

        expect_metadata(
            "VLAN_IPV4_OPTIONS_UDP",
            plen,
            1'b1,
            12'd100,
            16'h0800,
            1'b1,
            32'hC0A80A01,
            32'hC0A80A02,
            8'd17,
            1'b1,
            16'd1111,
            16'd2222,
            1'b1,
            1'b0,
            1'b0
        );

        /*
         * -----------------------------------------------------
         * TEST 3
         * IPv4 / TCP recognition.
         * -----------------------------------------------------
         */

        build_tcp_packet();

        send_current_packet();

        expect_metadata(
            "IPv4_TCP",
            plen,
            1'b0,
            12'd0,
            16'h0800,
            1'b1,
            32'hAC100001,
            32'hAC100002,
            8'd6,
            1'b1,
            16'd55000,
            16'd443,
            1'b0,
            1'b1,
            1'b0
        );

        /*
         * -----------------------------------------------------
         * TEST 4
         * Unsupported/non-IPv4 Ethernet frame.
         * Must remain valid Ethernet, not malformed.
         * -----------------------------------------------------
         */

        build_non_ipv4();

        send_current_packet();

        expect_metadata(
            "NON_IPV4",
            plen,
            1'b0,
            12'd0,
            16'h0806,
            1'b0,
            32'd0,
            32'd0,
            8'd0,
            1'b0,
            16'd0,
            16'd0,
            1'b0,
            1'b0,
            1'b0
        );

        /*
         * -----------------------------------------------------
         * TEST 5
         * Truncated Ethernet frame.
         * -----------------------------------------------------
         */

        build_truncated_eth();

        send_current_packet();

        expect_metadata(
            "TRUNCATED_ETH",
            plen,
            1'b0,
            12'd0,
            16'd0,
            1'b0,
            32'd0,
            32'd0,
            8'd0,
            1'b0,
            16'd0,
            16'd0,
            1'b0,
            1'b0,
            1'b1
        );

        /*
         * -----------------------------------------------------
         * TEST 6
         * Invalid IP version.
         * -----------------------------------------------------
         */

        build_udp_packet(
            1'b0,
            12'd0,
            5,
            32'h0A010101,
            32'h0A010102,
            16'd3000,
            16'd4000,
            8
        );

        packet_mem[14] =
            8'h65;

        send_current_packet();

        expect_metadata(
            "INVALID_IP_VERSION",
            plen,
            1'b0,
            12'd0,
            16'h0800,
            1'b0,
            32'd0,
            32'd0,
            8'd0,
            1'b0,
            16'd0,
            16'd0,
            1'b0,
            1'b0,
            1'b1
        );

        /*
         * -----------------------------------------------------
         * TEST 7
         * Truncated UDP header.
         * -----------------------------------------------------
         */

        build_udp_packet(
            1'b0,
            12'd0,
            5,
            32'h0A020201,
            32'h0A020202,
            16'd7000,
            16'd8000,
            0
        );

        /*
         * Remove four bytes from the UDP header.
         */
        plen = plen - 4;

        send_current_packet();

        expect_metadata(
            "TRUNCATED_UDP",
            plen,
            1'b0,
            12'd0,
            16'h0800,
            1'b1,
            32'h0A020201,
            32'h0A020202,
            8'd17,
            1'b0,
            16'd0,
            16'd0,
            1'b0,
            1'b0,
            1'b1
        );

        if (tests_passed != 7) begin

            $display(
                "FAIL: tests_passed=%0d expected=7",
                tests_passed
            );

            $fatal;

        end

        if (stall_cycles == 0) begin

            $display(
                "FAIL: parser was never exercised under backpressure"
            );

            $fatal;

        end

        $display("");
        $display(
            "============================================"
        );
        $display(
            " PROJECT08 08C PACKET PARSER: PASS"
        );
        $display(
            "============================================"
        );
        $display(
            " Ethernet II             : PASS"
        );
        $display(
            " VLAN                    : PASS"
        );
        $display(
            " IPv4                    : PASS"
        );
        $display(
            " IPv4 options / IHL      : PASS"
        );
        $display(
            " UDP                     : PASS"
        );
        $display(
            " TCP recognition         : PASS"
        );
        $display(
            " Non-IPv4 handling       : PASS"
        );
        $display(
            " Truncation detection    : PASS"
        );
        $display(
            " AXIS pass-through       : PASS"
        );
        $display(
            " Backpressure exercised  : PASS"
        );
        $display(
            " Packets tested          : %0d",
            tests_passed
        );
        $display(
            " Backpressure stalls     : %0d cycles",
            stall_cycles
        );
        $display(
            "============================================"
        );

        $finish;

    end

    initial begin

        #5_000_000;

        $display(
            "FAIL: Project08 08C simulation timeout"
        );

        $fatal;

    end

endmodule
