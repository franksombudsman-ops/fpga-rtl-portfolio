`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Module:
 *   Streaming Ethernet/VLAN/IPv4/L4 Packet Parser
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module p08_packet_parser (

    input  logic         clk,
    input  logic         aresetn,

    input  logic [63:0]  s_axis_tdata,
    input  logic [7:0]   s_axis_tkeep,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,
    input  logic         s_axis_tlast,

    output logic [63:0]  m_axis_tdata,
    output logic [7:0]   m_axis_tkeep,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,
    output logic         m_axis_tlast,

    output logic         metadata_valid,

    output logic [15:0]  packet_length,

    output logic [47:0]  dst_mac,
    output logic [47:0]  src_mac,

    output logic         vlan_present,
    output logic [11:0]  vlan_id,

    output logic [15:0]  ethertype,

    output logic         ipv4_valid,
    output logic [31:0]  src_ipv4,
    output logic [31:0]  dst_ipv4,
    output logic [7:0]   ip_protocol,

    output logic         l4_valid,
    output logic [15:0]  src_port,
    output logic [15:0]  dst_port,

    output logic         udp_valid,
    output logic         tcp_valid,

    output logic         malformed
);

    /*
     * Transparent AXI-Stream datapath.
     *
     * The parser observes only successfully accepted transfers.
     */
    assign m_axis_tdata  = s_axis_tdata;
    assign m_axis_tkeep  = s_axis_tkeep;
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tlast  = s_axis_tlast;

    assign s_axis_tready = m_axis_tready;

    /*
     * 128 bytes covers:
     *
     *   Ethernet + VLAN       18 bytes
     *   maximum IPv4 header   60 bytes
     *   minimum TCP header    20 bytes
     *
     * with margin for future parser extensions.
     */
    logic [7:0] header_mem [0:127];

    logic [15:0] byte_count;
    logic [15:0] final_length;

    logic        stream_error;
    logic        final_stream_error;

    logic        parse_pending;

    integer i;

    integer l3_offset;
    integer l4_offset;
    integer ihl_bytes;

    logic [15:0] parse_ethertype;

    logic parse_bad;
    logic beat_error;

    function automatic [3:0] popcount8(
        input logic [7:0] value
    );

        integer k;

        begin

            popcount8 = 4'd0;

            for (k = 0; k < 8; k = k + 1)
                popcount8 =
                    popcount8 +
                    value[k];

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

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            byte_count         <= 16'd0;
            final_length       <= 16'd0;

            stream_error       <= 1'b0;
            final_stream_error <= 1'b0;

            parse_pending      <= 1'b0;
            metadata_valid     <= 1'b0;

            packet_length      <= 16'd0;

            dst_mac            <= 48'd0;
            src_mac            <= 48'd0;

            vlan_present       <= 1'b0;
            vlan_id            <= 12'd0;

            ethertype          <= 16'd0;

            ipv4_valid         <= 1'b0;
            src_ipv4           <= 32'd0;
            dst_ipv4           <= 32'd0;
            ip_protocol        <= 8'd0;

            l4_valid           <= 1'b0;
            src_port           <= 16'd0;
            dst_port           <= 16'd0;

            udp_valid          <= 1'b0;
            tcp_valid          <= 1'b0;

            malformed          <= 1'b0;

        end
        else begin

            /*
             * Metadata is a one-cycle event.
             */
            metadata_valid <= 1'b0;

            /*
             * Parse one cycle after TLAST.
             *
             * This guarantees that bytes from the final AXI beat
             * have already entered header_mem.
             */
            if (parse_pending) begin

                parse_pending  <= 1'b0;
                metadata_valid <= 1'b1;

                packet_length <= final_length;

                dst_mac       <= 48'd0;
                src_mac       <= 48'd0;

                vlan_present  <= 1'b0;
                vlan_id       <= 12'd0;

                ethertype     <= 16'd0;

                ipv4_valid    <= 1'b0;
                src_ipv4      <= 32'd0;
                dst_ipv4      <= 32'd0;
                ip_protocol   <= 8'd0;

                l4_valid      <= 1'b0;
                src_port      <= 16'd0;
                dst_port      <= 16'd0;

                udp_valid     <= 1'b0;
                tcp_valid     <= 1'b0;

                parse_bad =
                    final_stream_error;

                l3_offset = 14;
                l4_offset = 0;
                ihl_bytes = 0;

                parse_ethertype = 16'd0;

                /*
                 * Ethernet II header.
                 */
                if (final_length < 14) begin

                    parse_bad = 1'b1;

                end
                else begin

                    dst_mac <= {
                        header_mem[0],
                        header_mem[1],
                        header_mem[2],
                        header_mem[3],
                        header_mem[4],
                        header_mem[5]
                    };

                    src_mac <= {
                        header_mem[6],
                        header_mem[7],
                        header_mem[8],
                        header_mem[9],
                        header_mem[10],
                        header_mem[11]
                    };

                    parse_ethertype = {
                        header_mem[12],
                        header_mem[13]
                    };

                    ethertype <=
                        parse_ethertype;

                    /*
                     * IEEE 802.1Q / 802.1ad tagged frame.
                     */
                    if (parse_ethertype == 16'h8100 ||
                        parse_ethertype == 16'h88A8) begin

                        vlan_present <= 1'b1;

                        if (final_length < 18) begin

                            parse_bad = 1'b1;

                        end
                        else begin

                            vlan_id <= {
                                header_mem[14][3:0],
                                header_mem[15]
                            };

                            parse_ethertype = {
                                header_mem[16],
                                header_mem[17]
                            };

                            ethertype <=
                                parse_ethertype;

                            l3_offset = 18;

                        end

                    end

                    /*
                     * IPv4.
                     */
                    if (!parse_bad &&
                        parse_ethertype == 16'h0800) begin

                        if (final_length <
                            (l3_offset + 20)) begin

                            parse_bad = 1'b1;

                        end
                        else if (
                            header_mem[l3_offset][7:4]
                            != 4'h4
                        ) begin

                            parse_bad = 1'b1;

                        end
                        else begin

                            ihl_bytes =
                                header_mem[
                                    l3_offset
                                ][3:0] * 4;

                            if (ihl_bytes < 20 ||
                                final_length <
                                (l3_offset +
                                 ihl_bytes)) begin

                                parse_bad = 1'b1;

                            end
                            else begin

                                ipv4_valid <= 1'b1;

                                ip_protocol <=
                                    header_mem[
                                        l3_offset + 9
                                    ];

                                src_ipv4 <= {
                                    header_mem[
                                        l3_offset + 12
                                    ],
                                    header_mem[
                                        l3_offset + 13
                                    ],
                                    header_mem[
                                        l3_offset + 14
                                    ],
                                    header_mem[
                                        l3_offset + 15
                                    ]
                                };

                                dst_ipv4 <= {
                                    header_mem[
                                        l3_offset + 16
                                    ],
                                    header_mem[
                                        l3_offset + 17
                                    ],
                                    header_mem[
                                        l3_offset + 18
                                    ],
                                    header_mem[
                                        l3_offset + 19
                                    ]
                                };

                                l4_offset =
                                    l3_offset +
                                    ihl_bytes;

                                /*
                                 * UDP.
                                 */
                                if (header_mem[
                                        l3_offset + 9
                                    ] == 8'd17) begin

                                    if (final_length <
                                        (l4_offset + 8)) begin

                                        parse_bad = 1'b1;

                                    end
                                    else begin

                                        l4_valid <= 1'b1;
                                        udp_valid <= 1'b1;

                                        src_port <= {
                                            header_mem[
                                                l4_offset
                                            ],
                                            header_mem[
                                                l4_offset + 1
                                            ]
                                        };

                                        dst_port <= {
                                            header_mem[
                                                l4_offset + 2
                                            ],
                                            header_mem[
                                                l4_offset + 3
                                            ]
                                        };

                                    end

                                end

                                /*
                                 * TCP.
                                 */
                                else if (
                                    header_mem[
                                        l3_offset + 9
                                    ] == 8'd6
                                ) begin

                                    if (final_length <
                                        (l4_offset + 20)) begin

                                        parse_bad = 1'b1;

                                    end
                                    else begin

                                        l4_valid <= 1'b1;
                                        tcp_valid <= 1'b1;

                                        src_port <= {
                                            header_mem[
                                                l4_offset
                                            ],
                                            header_mem[
                                                l4_offset + 1
                                            ]
                                        };

                                        dst_port <= {
                                            header_mem[
                                                l4_offset + 2
                                            ],
                                            header_mem[
                                                l4_offset + 3
                                            ]
                                        };

                                    end

                                end

                            end

                        end

                    end

                end

                malformed <=
                    parse_bad;

            end

            /*
             * Capture accepted packet bytes.
             */
            if (s_axis_tvalid &&
                s_axis_tready) begin

                beat_error = 1'b0;

                if (!s_axis_tlast &&
                    s_axis_tkeep != 8'hFF)
                    beat_error = 1'b1;

                if (s_axis_tlast &&
                    !keep_contiguous(
                        s_axis_tkeep
                    ))
                    beat_error = 1'b1;

                for (i = 0;
                     i < 8;
                     i = i + 1) begin

                    if (s_axis_tkeep[i] &&
                        ((byte_count + i)
                         < 128)) begin

                        header_mem[
                            byte_count + i
                        ] <=
                            s_axis_tdata[
                                i*8 +: 8
                            ];

                    end

                end

                if (s_axis_tlast) begin

                    final_length <=
                        byte_count +
                        popcount8(
                            s_axis_tkeep
                        );

                    final_stream_error <=
                        stream_error |
                        beat_error;

                    parse_pending <= 1'b1;

                    byte_count   <= 16'd0;
                    stream_error <= 1'b0;

                end
                else begin

                    byte_count <=
                        byte_count +
                        popcount8(
                            s_axis_tkeep
                        );

                    stream_error <=
                        stream_error |
                        beat_error;

                end

            end

        end

    end

endmodule
