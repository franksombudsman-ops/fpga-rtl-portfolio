/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

`timescale 1ns/1ps

module tb_axis_stream_infrastructure;

    localparam integer DATA_WIDTH = 64;
    localparam integer KEEP_WIDTH = 8;

    logic clk = 1'b0;
    always #4 clk = ~clk;     // 125 MHz

    logic aresetn = 1'b0;

    logic [DATA_WIDTH-1:0] s_tdata;
    logic [KEEP_WIDTH-1:0] s_tkeep;
    logic                  s_tvalid;
    logic                  s_tready;
    logic                  s_tlast;

    logic [DATA_WIDTH-1:0] m_tdata;
    logic [KEEP_WIDTH-1:0] m_tkeep;
    logic                  m_tvalid;
    logic                  m_tready;
    logic                  m_tlast;

    /*
     * 08B uses a transparent streaming path.
     * The purpose of this gate is to qualify the reusable
     * source, sink, handshake and scoreboard infrastructure
     * before inserting the Project08 packet processor.
     */
    assign m_tdata  = s_tdata;
    assign m_tkeep  = s_tkeep;
    assign m_tvalid = s_tvalid;
    assign m_tlast  = s_tlast;
    assign s_tready = m_tready;

    logic [7:0] expected_bytes[$];
    integer     expected_lengths[$];

    integer tx_packets = 0;
    integer tx_bytes   = 0;
    integer rx_packets = 0;
    integer rx_bytes   = 0;

    integer stall_cycles = 0;
    integer rx_packet_bytes = 0;

    logic backpressure_enable = 1'b0;
    logic [31:0] lfsr = 32'h1ACE_B00C;

    logic stall_active = 1'b0;
    logic [63:0] stall_data;
    logic [7:0]  stall_keep;
    logic        stall_last;

    function automatic [7:0] pattern_byte(
        input integer packet_id,
        input integer offset
    );
        integer value;
        begin
            value =
                packet_id * 37 +
                offset * 13 +
                8'h5A;

            pattern_byte = value[7:0];
        end
    endfunction

    function automatic logic keep_contiguous(
        input logic [7:0] keep
    );
        begin
            case (keep)
                8'h01,
                8'h03,
                8'h07,
                8'h0F,
                8'h1F,
                8'h3F,
                8'h7F,
                8'hFF:
                    keep_contiguous = 1'b1;

                default:
                    keep_contiguous = 1'b0;
            endcase
        end
    endfunction

    /*
     * Deterministic pseudo-random sink backpressure.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            lfsr <= 32'h1ACE_B00C;
            m_tready <= 1'b0;

        end
        else begin

            lfsr <= {
                lfsr[30:0],
                lfsr[31] ^
                lfsr[21] ^
                lfsr[1]  ^
                lfsr[0]
            };

            if (backpressure_enable)
                m_tready <= lfsr[0] | lfsr[4];
            else
                m_tready <= 1'b1;

        end

    end

    /*
     * AXI-Stream protocol check:
     * payload/control must remain stable while TVALID=1
     * and TREADY=0.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            stall_active <= 1'b0;

        end
        else begin

            if (stall_active) begin

                if (!s_tvalid) begin
                    $display(
                        "FAIL: TVALID dropped while stalled"
                    );
                    $fatal;
                end

                if (s_tdata !== stall_data ||
                    s_tkeep !== stall_keep ||
                    s_tlast !== stall_last) begin

                    $display(
                        "FAIL: AXIS payload changed while stalled"
                    );
                    $fatal;

                end

            end

            if (s_tvalid && !s_tready) begin

                stall_active <= 1'b1;
                stall_data   <= s_tdata;
                stall_keep   <= s_tkeep;
                stall_last   <= s_tlast;

                stall_cycles <= stall_cycles + 1;

            end
            else begin

                stall_active <= 1'b0;

            end

        end

    end

    /*
     * Self-checking sink.
     */
    integer lane;
    integer beat_bytes;
    integer expected_length;
    logic [7:0] expected_byte;

    always @(posedge clk) begin

        if (aresetn &&
            m_tvalid &&
            m_tready) begin

            beat_bytes = 0;

            if (!m_tlast &&
                m_tkeep !== 8'hFF) begin

                $display(
                    "FAIL: partial TKEEP before TLAST keep=%02x",
                    m_tkeep
                );

                $fatal;

            end

            if (m_tlast &&
                !keep_contiguous(m_tkeep)) begin

                $display(
                    "FAIL: invalid final TKEEP=%02x",
                    m_tkeep
                );

                $fatal;

            end

            for (lane = 0;
                 lane < KEEP_WIDTH;
                 lane = lane + 1) begin

                if (m_tkeep[lane]) begin

                    if (expected_bytes.size() == 0) begin

                        $display(
                            "FAIL: received unexpected byte"
                        );

                        $fatal;

                    end

                    expected_byte =
                        expected_bytes.pop_front();

                    if (m_tdata[
                            lane*8 +: 8
                        ] !== expected_byte) begin

                        $display(
                            "FAIL: byte mismatch rx=%02x expected=%02x packet=%0d",
                            m_tdata[lane*8 +: 8],
                            expected_byte,
                            rx_packets
                        );

                        $fatal;

                    end

                    beat_bytes = beat_bytes + 1;
                    rx_bytes   = rx_bytes + 1;

                end

            end

            if (m_tlast) begin

                if (expected_lengths.size() == 0) begin

                    $display(
                        "FAIL: unexpected TLAST"
                    );

                    $fatal;

                end

                expected_length =
                    expected_lengths.pop_front();

                if ((rx_packet_bytes +
                     beat_bytes) !=
                    expected_length) begin

                    $display(
                        "FAIL: packet length rx=%0d expected=%0d",
                        rx_packet_bytes + beat_bytes,
                        expected_length
                    );

                    $fatal;

                end

                rx_packet_bytes = 0;
                rx_packets      = rx_packets + 1;

            end
            else begin

                rx_packet_bytes =
                    rx_packet_bytes +
                    beat_bytes;

            end

        end

    end

    task automatic send_packet(
        input integer packet_length,
        input integer packet_id
    );

        integer offset;
        integer lane_index;
        integer beat_length;

        logic [63:0] beat_data;
        logic [7:0]  beat_keep;

        begin

            expected_lengths.push_back(
                packet_length
            );

            for (offset = 0;
                 offset < packet_length;
                 offset = offset + 1) begin

                expected_bytes.push_back(
                    pattern_byte(
                        packet_id,
                        offset
                    )
                );

            end

            tx_packets = tx_packets + 1;
            tx_bytes   = tx_bytes +
                         packet_length;

            offset = 0;

            while (offset <
                   packet_length) begin

                if ((packet_length - offset) > 8)
                    beat_length = 8;
                else
                    beat_length =
                        packet_length -
                        offset;

                beat_data = 64'h0;
                beat_keep = 8'h00;

                for (lane_index = 0;
                     lane_index < beat_length;
                     lane_index = lane_index + 1) begin

                    beat_data[
                        lane_index*8 +: 8
                    ] =
                        pattern_byte(
                            packet_id,
                            offset +
                            lane_index
                        );

                    beat_keep[lane_index] =
                        1'b1;

                end

                @(negedge clk);

                s_tdata  = beat_data;
                s_tkeep  = beat_keep;
                s_tvalid = 1'b1;

                s_tlast =
                    ((offset +
                      beat_length) ==
                     packet_length);

                @(posedge clk);

                while (!s_tready)
                    @(posedge clk);

                offset =
                    offset +
                    beat_length;

            end

        end

    endtask

    integer index;
    integer length;

    initial begin

        s_tdata  = 64'h0;
        s_tkeep  = 8'h0;
        s_tvalid = 1'b0;
        s_tlast  = 1'b0;

        repeat (10)
            @(posedge clk);

        aresetn = 1'b1;

        repeat (4)
            @(posedge clk);

        $display("");
        $display(
            "===== 08B PHASE 1: EXACT BOUNDARIES ====="
        );

        backpressure_enable = 1'b0;

        send_packet(1,    1);
        send_packet(7,    2);
        send_packet(8,    3);
        send_packet(9,    4);
        send_packet(15,   5);
        send_packet(16,   6);
        send_packet(63,   7);
        send_packet(64,   8);
        send_packet(65,   9);
        send_packet(1518, 10);

        $display(
            "PHASE 1: packet boundaries transmitted"
        );

        $display("");
        $display(
            "===== 08B PHASE 2: BACKPRESSURE ====="
        );

        backpressure_enable = 1'b1;

        /*
         * 128 deterministic variable-length packets.
         * Length range: 1..1024 bytes.
         */
        for (index = 0;
             index < 128;
             index = index + 1) begin

            length =
                1 +
                ((index * 73 + 19) %
                 1024);

            send_packet(
                length,
                1000 + index
            );

        end

        @(negedge clk);

        s_tvalid = 1'b0;
        s_tlast  = 1'b0;
        s_tkeep  = 8'h00;
        s_tdata  = 64'h0;

        /*
         * Allow sink accounting to settle.
         */
        repeat (20)
            @(posedge clk);

        if (expected_bytes.size() != 0) begin

            $display(
                "FAIL: expected byte queue not empty: %0d",
                expected_bytes.size()
            );

            $fatal;

        end

        if (expected_lengths.size() != 0) begin

            $display(
                "FAIL: expected packet queue not empty: %0d",
                expected_lengths.size()
            );

            $fatal;

        end

        if (tx_packets != rx_packets) begin

            $display(
                "FAIL: packet count TX=%0d RX=%0d",
                tx_packets,
                rx_packets
            );

            $fatal;

        end

        if (tx_bytes != rx_bytes) begin

            $display(
                "FAIL: byte count TX=%0d RX=%0d",
                tx_bytes,
                rx_bytes
            );

            $fatal;

        end

        if (stall_cycles == 0) begin

            $display(
                "FAIL: randomized backpressure produced no stalls"
            );

            $fatal;

        end

        $display("");
        $display(
            "============================================"
        );
        $display(
            " PROJECT08 08B AXI-STREAM INFRASTRUCTURE: PASS"
        );
        $display(
            "============================================"
        );
        $display(
            " Datapath width       : 64 bits"
        );
        $display(
            " Clock                : 125 MHz"
        );
        $display(
            " TX packets           : %0d",
            tx_packets
        );
        $display(
            " RX packets           : %0d",
            rx_packets
        );
        $display(
            " TX bytes             : %0d",
            tx_bytes
        );
        $display(
            " RX bytes             : %0d",
            rx_bytes
        );
        $display(
            " Backpressure stalls  : %0d cycles",
            stall_cycles
        );
        $display(
            " TKEEP/TLAST          : PASS"
        );
        $display(
            " Stall stability      : PASS"
        );
        $display(
            " Byte scoreboard      : PASS"
        );
        $display(
            " Packet boundaries    : PASS"
        );
        $display(
            "============================================"
        );

        $finish;

    end

    initial begin

        #20_000_000;

        $display(
            "FAIL: Project08 08B simulation timeout"
        );

        $fatal;

    end

endmodule
