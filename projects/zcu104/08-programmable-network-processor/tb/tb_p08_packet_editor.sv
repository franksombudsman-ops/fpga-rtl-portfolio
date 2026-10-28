`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Verification:
 *   IPv4 / UDP / TCP Packet Modification and Checksum Regeneration
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module tb_p08_packet_editor;

    logic clk = 1'b0;

    always #4 clk = ~clk;     // 125 MHz

    logic aresetn = 1'b0;

    logic [63:0] s_axis_tdata;
    logic [7:0]  s_axis_tkeep;
    logic        s_axis_tvalid;
    logic        s_axis_tready;
    logic        s_axis_tlast;

    logic edit_enable;

    logic rewrite_src_ip;
    logic rewrite_dst_ip;
    logic rewrite_src_port;
    logic rewrite_dst_port;

    logic [31:0] new_src_ip;
    logic [31:0] new_dst_ip;
    logic [15:0] new_src_port;
    logic [15:0] new_dst_port;

    logic [63:0] m_axis_tdata;
    logic [7:0]  m_axis_tkeep;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;

    logic edit_done;
    logic edit_error;

    p08_packet_editor dut (

        .clk                (clk),
        .aresetn            (aresetn),

        .s_axis_tdata       (s_axis_tdata),
        .s_axis_tkeep       (s_axis_tkeep),
        .s_axis_tvalid      (s_axis_tvalid),
        .s_axis_tready      (s_axis_tready),
        .s_axis_tlast       (s_axis_tlast),

        .edit_enable        (edit_enable),

        .rewrite_src_ip     (rewrite_src_ip),
        .rewrite_dst_ip     (rewrite_dst_ip),
        .rewrite_src_port   (rewrite_src_port),
        .rewrite_dst_port   (rewrite_dst_port),

        .new_src_ip         (new_src_ip),
        .new_dst_ip         (new_dst_ip),
        .new_src_port       (new_src_port),
        .new_dst_port       (new_dst_port),

        .m_axis_tdata       (m_axis_tdata),
        .m_axis_tkeep       (m_axis_tkeep),
        .m_axis_tvalid      (m_axis_tvalid),
        .m_axis_tready      (m_axis_tready),
        .m_axis_tlast       (m_axis_tlast),

        .edit_done          (edit_done),
        .edit_error         (edit_error)
    );

    logic [7:0] tx_mem [0:2047];
    logic [7:0] original_mem [0:2047];
    logic [7:0] rx_mem [0:2047];

    integer tx_len;
    integer rx_len;

    logic rx_complete;

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
                ((cycle_count % 5) != 0);

    end

    always @(posedge clk) begin

        integer k;

        if (aresetn &&
            m_axis_tvalid &&
            !m_axis_tready)
            output_stalls =
                output_stalls + 1;

        if (aresetn &&
            m_axis_tvalid &&
            m_axis_tready) begin

            for (k = 0; k < 8; k = k + 1) begin

                if (m_axis_tkeep[k]) begin

                    rx_mem[rx_len] =
                        m_axis_tdata[
                            k*8 +: 8
                        ];

                    rx_len =
                        rx_len + 1;

                end

            end

            if (m_axis_tlast)
                rx_complete =
                    1'b1;

        end

    end

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

    task automatic ethernet_header(
        input logic use_vlan,
        input logic [11:0] vlan
    );

        begin

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

            if (use_vlan) begin

                put16be(16'h8100);
                put16be({4'd0, vlan});
                put16be(16'h0800);

            end
            else begin

                put16be(16'h0800);

            end

        end

    endtask

    task automatic build_udp(
        input logic use_vlan,
        input logic [11:0] vlan,
        input logic [31:0] sip,
        input logic [31:0] dip,
        input logic [15:0] sport,
        input logic [15:0] dport,
        input integer payload_len
    );

        integer n;
        integer total_len;
        integer udp_len;

        begin

            clear_packet();

            ethernet_header(
                use_vlan,
                vlan
            );

            total_len =
                20 +
                8 +
                payload_len;

            udp_len =
                8 +
                payload_len;

            put8(8'h45);
            put8(8'h00);

            put16be(
                total_len[15:0]
            );

            put16be(16'h1234);
            put16be(16'h4000);

            put8(8'h40);
            put8(8'd17);

            /*
             * Initial checksums intentionally zero.
             * DUT must regenerate them when editing.
             */
            put16be(16'h0000);

            put32be(sip);
            put32be(dip);

            put16be(sport);
            put16be(dport);

            put16be(
                udp_len[15:0]
            );

            put16be(16'h0000);

            for (n = 0;
                 n < payload_len;
                 n = n + 1)
                put8(
                    (8'h80 + n) &
                    8'hFF
                );

        end

    endtask

    task automatic build_tcp(
        input logic [31:0] sip,
        input logic [31:0] dip,
        input logic [15:0] sport,
        input logic [15:0] dport,
        input integer payload_len
    );

        integer n;
        integer total_len;

        begin

            clear_packet();

            ethernet_header(
                1'b0,
                12'd0
            );

            total_len =
                20 +
                20 +
                payload_len;

            put8(8'h45);
            put8(8'h00);

            put16be(
                total_len[15:0]
            );

            put16be(16'h4321);
            put16be(16'h4000);

            put8(8'h40);
            put8(8'd6);

            put16be(16'h0000);

            put32be(sip);
            put32be(dip);

            put16be(sport);
            put16be(dport);

            put32be(32'h01020304);
            put32be(32'h00000000);

            put8(8'h50);
            put8(8'h18);

            put16be(16'h4000);

            put16be(16'h0000);

            put16be(16'h0000);

            for (n = 0;
                 n < payload_len;
                 n = n + 1)
                put8(
                    (8'h30 + n) &
                    8'hFF
                );

        end

    endtask

    task automatic build_non_ipv4;

        integer n;

        begin

            clear_packet();

            put8(8'hFF);
            put8(8'hFF);
            put8(8'hFF);
            put8(8'hFF);
            put8(8'hFF);
            put8(8'hFF);

            put8(8'h02);
            put8(8'hAA);
            put8(8'hBB);
            put8(8'hCC);
            put8(8'hDD);
            put8(8'hEE);

            put16be(16'h0806);

            for (n = 14; n < 60; n = n + 1)
                put8(n[7:0]);

        end

    endtask

    task automatic preserve_original;

        integer n;

        begin

            for (n = 0;
                 n < tx_len;
                 n = n + 1)
                original_mem[n] =
                    tx_mem[n];

        end

    endtask

    task automatic send_packet;

        integer offset;
        integer lane;
        integer beat_length;

        logic [63:0] data;
        logic [7:0] keep;

        begin

            rx_len =
                0;

            rx_complete =
                1'b0;

            offset =
                0;

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

                for (lane = 0;
                     lane < beat_length;
                     lane = lane + 1) begin

                    data[
                        lane*8 +: 8
                    ] =
                        tx_mem[
                            offset + lane
                        ];

                    keep[lane] =
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
                      beat_length)
                     == tx_len);

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

    function automatic [15:0] fold_sum(
        input integer value
    );

        integer temp;

        begin

            temp =
                value;

            while ((temp >> 16) != 0)
                temp =
                    (temp & 16'hFFFF) +
                    (temp >> 16);

            fold_sum =
                temp[15:0];

        end

    endfunction

    task automatic verify_ipv4_checksum(
        input integer l3
    );

        integer ihl;
        integer n;
        integer sum;
        integer word_value;

        begin

            ihl =
                (rx_mem[l3] &
                 8'h0F) * 4;

            sum = 0;

            for (n = 0;
                 n < ihl;
                 n = n + 2) begin

                word_value =
                    (rx_mem[l3+n] << 8) |
                    rx_mem[l3+n+1];

                sum =
                    sum +
                    word_value;

            end

            if (fold_sum(sum) !=
                16'hFFFF) begin

                $display(
                    "FAIL: IPv4 checksum fold=%04x",
                    fold_sum(sum)
                );

                $fatal;

            end

        end

    endtask

    task automatic verify_l4_checksum(
        input integer l3
    );

        integer ihl;
        integer l4;
        integer ip_len;
        integer l4_len;
        integer proto;

        integer n;
        integer sum;
        integer word_value;

        begin

            ihl =
                (rx_mem[l3] &
                 8'h0F) * 4;

            ip_len =
                (rx_mem[l3+2] << 8) |
                rx_mem[l3+3];

            l4 =
                l3 + ihl;

            l4_len =
                ip_len - ihl;

            proto =
                rx_mem[l3+9];

            sum = 0;

            sum +=
                (rx_mem[l3+12] << 8) |
                rx_mem[l3+13];

            sum +=
                (rx_mem[l3+14] << 8) |
                rx_mem[l3+15];

            sum +=
                (rx_mem[l3+16] << 8) |
                rx_mem[l3+17];

            sum +=
                (rx_mem[l3+18] << 8) |
                rx_mem[l3+19];

            sum +=
                proto;

            sum +=
                l4_len;

            for (n = 0;
                 n < l4_len;
                 n = n + 2) begin

                if ((n + 1) <
                    l4_len)
                    word_value =
                        (rx_mem[l4+n] << 8) |
                        rx_mem[l4+n+1];
                else
                    word_value =
                        (rx_mem[l4+n] << 8);

                sum =
                    sum +
                    word_value;

            end

            if (fold_sum(sum) !=
                16'hFFFF) begin

                $display(
                    "FAIL: L4 checksum fold=%04x proto=%0d",
                    fold_sum(sum),
                    proto
                );

                $fatal;

            end

        end

    endtask

    task automatic wait_for_output(
        input logic expected_error
    );

        begin

            wait (
                edit_done === 1'b1
            );

            #1;

            if (edit_error !==
                expected_error) begin

                $display(
                    "FAIL: edit_error=%0d expected=%0d",
                    edit_error,
                    expected_error
                );

                $fatal;

            end

            wait (
                rx_complete === 1'b1
            );

            repeat (2)
                @(posedge clk);

            if (rx_len != tx_len) begin

                $display(
                    "FAIL: output length=%0d input=%0d",
                    rx_len,
                    tx_len
                );

                $fatal;

            end

        end

    endtask

    task automatic verify_exact_bypass;

        integer n;

        begin

            for (n = 0;
                 n < tx_len;
                 n = n + 1) begin

                if (rx_mem[n] !==
                    original_mem[n]) begin

                    $display(
                        "FAIL: bypass mismatch byte=%0d",
                        n
                    );

                    $fatal;

                end

            end

        end

    endtask

    integer tests_passed = 0;
    integer l3;

    initial begin

        s_axis_tdata  = 64'd0;
        s_axis_tkeep  = 8'd0;
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0;

        edit_enable = 1'b0;

        rewrite_src_ip   = 1'b0;
        rewrite_dst_ip   = 1'b0;
        rewrite_src_port = 1'b0;
        rewrite_dst_port = 1'b0;

        new_src_ip   = 32'd0;
        new_dst_ip   = 32'd0;
        new_src_port = 16'd0;
        new_dst_port = 16'd0;

        rx_len =
            0;

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
         * TEST 1 — IPv4 / UDP full rewrite
         * -----------------------------------------------------
         */

        build_udp(
            1'b0,
            12'd0,
            32'h0A000001,
            32'hC0A80101,
            16'd1234,
            16'd5000,
            31
        );

        preserve_original();

        edit_enable =
            1'b1;

        rewrite_src_ip =
            1'b1;

        rewrite_dst_ip =
            1'b1;

        rewrite_src_port =
            1'b1;

        rewrite_dst_port =
            1'b1;

        new_src_ip =
            32'h0A0A0A01;

        new_dst_ip =
            32'hAC100064;

        new_src_port =
            16'd40000;

        new_dst_port =
            16'd9000;

        send_packet();

        wait_for_output(
            1'b0
        );

        l3 = 14;

        if ({
            rx_mem[l3+12],
            rx_mem[l3+13],
            rx_mem[l3+14],
            rx_mem[l3+15]
        } !== 32'h0A0A0A01 ||
            {
            rx_mem[l3+16],
            rx_mem[l3+17],
            rx_mem[l3+18],
            rx_mem[l3+19]
        } !== 32'hAC100064 ||
            {
            rx_mem[l3+20],
            rx_mem[l3+21]
        } !== 16'd40000 ||
            {
            rx_mem[l3+22],
            rx_mem[l3+23]
        } !== 16'd9000) begin

            $display(
                "FAIL: UDP rewrite fields"
            );

            $fatal;

        end

        verify_ipv4_checksum(l3);
        verify_l4_checksum(l3);

        tests_passed =
            tests_passed + 1;

        $display(
            "TEST UDP_FULL_REWRITE: PASS"
        );

        /*
         * -----------------------------------------------------
         * TEST 2 — VLAN IPv4 / UDP rewrite
         * -----------------------------------------------------
         */

        build_udp(
            1'b1,
            12'd100,
            32'hC0A80A01,
            32'hC0A80A02,
            16'd1111,
            16'd2222,
            17
        );

        preserve_original();

        edit_enable =
            1'b1;

        rewrite_src_ip =
            1'b0;

        rewrite_dst_ip =
            1'b1;

        rewrite_src_port =
            1'b0;

        rewrite_dst_port =
            1'b1;

        new_dst_ip =
            32'hC0A81464;

        new_dst_port =
            16'd7000;

        send_packet();

        wait_for_output(
            1'b0
        );

        l3 = 18;

        if ({
            rx_mem[l3+16],
            rx_mem[l3+17],
            rx_mem[l3+18],
            rx_mem[l3+19]
        } !== 32'hC0A81464 ||
            {
            rx_mem[l3+22],
            rx_mem[l3+23]
        } !== 16'd7000) begin

            $display(
                "FAIL: VLAN UDP rewrite fields"
            );

            $fatal;

        end

        verify_ipv4_checksum(l3);
        verify_l4_checksum(l3);

        tests_passed =
            tests_passed + 1;

        $display(
            "TEST VLAN_UDP_REWRITE: PASS"
        );

        /*
         * -----------------------------------------------------
         * TEST 3 — TCP rewrite
         * -----------------------------------------------------
         */

        build_tcp(
            32'hAC100001,
            32'hAC100002,
            16'd55000,
            16'd443,
            19
        );

        preserve_original();

        edit_enable =
            1'b1;

        rewrite_src_ip =
            1'b1;

        rewrite_dst_ip =
            1'b1;

        rewrite_src_port =
            1'b1;

        rewrite_dst_port =
            1'b1;

        new_src_ip =
            32'h0A010101;

        new_dst_ip =
            32'h0A010102;

        new_src_port =
            16'd60000;

        new_dst_port =
            16'd8443;

        send_packet();

        wait_for_output(
            1'b0
        );

        l3 = 14;

        if ({
            rx_mem[l3+12],
            rx_mem[l3+13],
            rx_mem[l3+14],
            rx_mem[l3+15]
        } !== 32'h0A010101 ||
            {
            rx_mem[l3+16],
            rx_mem[l3+17],
            rx_mem[l3+18],
            rx_mem[l3+19]
        } !== 32'h0A010102 ||
            {
            rx_mem[l3+20],
            rx_mem[l3+21]
        } !== 16'd60000 ||
            {
            rx_mem[l3+22],
            rx_mem[l3+23]
        } !== 16'd8443) begin

            $display(
                "FAIL: TCP rewrite fields"
            );

            $fatal;

        end

        verify_ipv4_checksum(l3);
        verify_l4_checksum(l3);

        tests_passed =
            tests_passed + 1;

        $display(
            "TEST TCP_FULL_REWRITE: PASS"
        );

        /*
         * -----------------------------------------------------
         * TEST 4 — editor bypass is byte exact
         * -----------------------------------------------------
         */

        build_udp(
            1'b0,
            12'd0,
            32'h0A020201,
            32'h0A020202,
            16'd3000,
            16'd4000,
            13
        );

        preserve_original();

        edit_enable =
            1'b0;

        rewrite_src_ip =
            1'b0;

        rewrite_dst_ip =
            1'b0;

        rewrite_src_port =
            1'b0;

        rewrite_dst_port =
            1'b0;

        send_packet();

        wait_for_output(
            1'b0
        );

        verify_exact_bypass();

        tests_passed =
            tests_passed + 1;

        $display(
            "TEST BYTE_EXACT_BYPASS: PASS"
        );

        /*
         * -----------------------------------------------------
         * TEST 5 — unsupported non-IPv4 edit rejected safely
         * -----------------------------------------------------
         */

        build_non_ipv4();

        preserve_original();

        edit_enable =
            1'b1;

        rewrite_src_ip =
            1'b1;

        rewrite_dst_ip =
            1'b0;

        rewrite_src_port =
            1'b0;

        rewrite_dst_port =
            1'b0;

        new_src_ip =
            32'h01020304;

        send_packet();

        wait_for_output(
            1'b1
        );

        verify_exact_bypass();

        tests_passed =
            tests_passed + 1;

        $display(
            "TEST UNSUPPORTED_SAFE_BYPASS: PASS"
        );

        if (tests_passed != 5) begin

            $display(
                "FAIL: tests_passed=%0d expected=5",
                tests_passed
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
            " PROJECT08 08F PACKET EDITOR: PASS"
        );
        $display(
            "============================================"
        );
        $display(
            " IPv4 source rewrite       : PASS"
        );
        $display(
            " IPv4 destination rewrite  : PASS"
        );
        $display(
            " UDP source-port rewrite   : PASS"
        );
        $display(
            " UDP destination rewrite   : PASS"
        );
        $display(
            " TCP source-port rewrite   : PASS"
        );
        $display(
            " TCP destination rewrite   : PASS"
        );
        $display(
            " VLAN IPv4 editing         : PASS"
        );
        $display(
            " IPv4 checksum regenerate  : PASS"
        );
        $display(
            " UDP checksum regenerate   : PASS"
        );
        $display(
            " TCP checksum regenerate   : PASS"
        );
        $display(
            " Byte-exact bypass         : PASS"
        );
        $display(
            " Unsupported safe bypass   : PASS"
        );
        $display(
            " Output backpressure       : PASS"
        );
        $display(
            " Tests                     : %0d",
            tests_passed
        );
        $display(
            " Output stall cycles       : %0d",
            output_stalls
        );
        $display(
            "============================================"
        );

        $finish;

    end

    initial begin

        #20_000_000;

        $display(
            "FAIL: Project08 08F simulation timeout"
        );

        $fatal;

    end

endmodule
