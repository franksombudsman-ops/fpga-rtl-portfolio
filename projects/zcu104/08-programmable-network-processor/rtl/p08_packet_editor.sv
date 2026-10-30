`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Module:
 *   IPv4 / UDP / TCP Packet Editor and Checksum Engine
 *
 * Purpose:
 *   Store a complete AXI4-Stream packet, apply selected IPv4/L4
 *   field modifications, regenerate affected checksums, and replay
 *   the resulting frame under normal AXI4-Stream backpressure.
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module p08_packet_editor #(
    parameter integer MAX_PACKET_BYTES = 2048
)(
    input  logic         clk,
    input  logic         aresetn,

    input  logic [63:0]  s_axis_tdata,
    input  logic [7:0]   s_axis_tkeep,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,
    input  logic         s_axis_tlast,

    input  logic         edit_enable,

    input  logic         rewrite_src_ip,
    input  logic         rewrite_dst_ip,
    input  logic         rewrite_src_port,
    input  logic         rewrite_dst_port,

    input  logic [31:0]  new_src_ip,
    input  logic [31:0]  new_dst_ip,
    input  logic [15:0]  new_src_port,
    input  logic [15:0]  new_dst_port,

    output logic [63:0]  m_axis_tdata,
    output logic [7:0]   m_axis_tkeep,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,
    output logic         m_axis_tlast,

    output logic         edit_done,
    output logic         edit_error
);

    typedef enum logic [3:0] {
        ST_CAPTURE,
        ST_BYPASS,
        ST_PARSE_ETH,
        ST_PARSE_IP,
        ST_APPLY,
        ST_IP_SUM_INIT,
        ST_IP_SUM,
        ST_IP_WRITE,
        ST_L4_SUM_INIT,
        ST_L4_SUM,
        ST_L4_WRITE,
        ST_OUTPUT
    } state_t;

    state_t state;

    logic [7:0] packet_mem [0:MAX_PACKET_BYTES-1];

    logic [15:0] byte_count;
    logic [15:0] packet_length;

    logic [15:0] l3_offset;
    logic [15:0] l4_offset;

    logic [15:0] ip_header_length;
    logic [15:0] ip_total_length;
    logic [15:0] l4_length;

    logic [7:0]  protocol_reg;
    logic [15:0] ethertype_reg;

    logic packet_edit_enable;

    logic packet_rewrite_src_ip;
    logic packet_rewrite_dst_ip;
    logic packet_rewrite_src_port;
    logic packet_rewrite_dst_port;

    logic [31:0] packet_new_src_ip;
    logic [31:0] packet_new_dst_ip;
    logic [15:0] packet_new_src_port;
    logic [15:0] packet_new_dst_port;

    logic [31:0] sum_acc;
    logic [15:0] sum_index;
    logic [15:0] checksum_result;

    logic [15:0] output_offset;

    integer lane;

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

    function automatic [15:0] fold16(
        input logic [31:0] value
    );

        logic [31:0] temp;

        begin

            temp =
                {16'd0, value[15:0]} +
                {16'd0, value[31:16]};

            temp =
                {16'd0, temp[15:0]} +
                {16'd0, temp[31:16]};

            fold16 =
                temp[15:0];

        end

    endfunction

    /*
     * Input is accepted only while collecting one packet.
     */
    always_comb begin

        if (!aresetn) begin

            s_axis_tready =
                1'b0;

        end
        else if (
            (state == ST_CAPTURE &&
             !edit_enable) ||
            state == ST_BYPASS
        ) begin

            /*
             * Fast path:
             *
             * FORWARD / REDIRECT / COUNT packets never enter
             * store-and-forward editing memory.
             */
            s_axis_tready =
                m_axis_tready;

        end
        else begin

            s_axis_tready =
                (state == ST_CAPTURE) &&
                (byte_count <
                 MAX_PACKET_BYTES);

        end

    end

    /*
     * Reconstruct AXI beats from edited byte memory.
     */
    integer out_lane;

    always_comb begin

        m_axis_tdata  = 64'd0;
        m_axis_tkeep  = 8'd0;
        m_axis_tvalid = 1'b0;
        m_axis_tlast  = 1'b0;

        if (
            (state == ST_CAPTURE &&
             !edit_enable) ||
            state == ST_BYPASS
        ) begin

            /*
             * Zero-store fast path.
             *
             * Packet data, KEEP and TLAST propagate directly
             * through the editor when no rewrite is requested.
             */
            m_axis_tdata =
                s_axis_tdata;

            m_axis_tkeep =
                s_axis_tkeep;

            m_axis_tvalid =
                s_axis_tvalid;

            m_axis_tlast =
                s_axis_tlast;

        end
        else if (state == ST_OUTPUT) begin

            m_axis_tvalid =
                1'b1;

            for (out_lane = 0;
                 out_lane < 8;
                 out_lane = out_lane + 1) begin

                if ((output_offset +
                     out_lane) <
                    packet_length) begin

                    m_axis_tdata[
                        out_lane*8 +: 8
                    ] =
                        packet_mem[
                            output_offset +
                            out_lane
                        ];

                    m_axis_tkeep[
                        out_lane
                    ] =
                        1'b1;

                end

            end

            if ((output_offset + 8) >=
                packet_length)
                m_axis_tlast =
                    1'b1;

        end

    end

    logic [15:0] current_word;
    logic [31:0] final_sum;

    always_comb begin

        current_word = 16'd0;
        final_sum    = 32'd0;

        if (state == ST_IP_SUM) begin

            current_word = {
                packet_mem[
                    l3_offset +
                    sum_index
                ],
                packet_mem[
                    l3_offset +
                    sum_index +
                    1
                ]
            };

            final_sum =
                sum_acc +
                {16'd0,
                 current_word};

        end
        else if (state == ST_L4_SUM) begin

            if ((sum_index + 1) <
                l4_length) begin

                current_word = {
                    packet_mem[
                        l4_offset +
                        sum_index
                    ],
                    packet_mem[
                        l4_offset +
                        sum_index +
                        1
                    ]
                };

            end
            else begin

                current_word = {
                    packet_mem[
                        l4_offset +
                        sum_index
                    ],
                    8'h00
                };

            end

            final_sum =
                sum_acc +
                {16'd0,
                 current_word};

        end

    end

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            state <=
                ST_CAPTURE;

            byte_count <=
                16'd0;

            packet_length <=
                16'd0;

            l3_offset <=
                16'd0;

            l4_offset <=
                16'd0;

            ip_header_length <=
                16'd0;

            ip_total_length <=
                16'd0;

            l4_length <=
                16'd0;

            protocol_reg <=
                8'd0;

            ethertype_reg <=
                16'd0;

            packet_edit_enable <=
                1'b0;

            packet_rewrite_src_ip <=
                1'b0;

            packet_rewrite_dst_ip <=
                1'b0;

            packet_rewrite_src_port <=
                1'b0;

            packet_rewrite_dst_port <=
                1'b0;

            packet_new_src_ip <=
                32'd0;

            packet_new_dst_ip <=
                32'd0;

            packet_new_src_port <=
                16'd0;

            packet_new_dst_port <=
                16'd0;

            sum_acc <=
                32'd0;

            sum_index <=
                16'd0;

            checksum_result <=
                16'd0;

            output_offset <=
                16'd0;

            edit_done <=
                1'b0;

            edit_error <=
                1'b0;

        end
        else begin

            edit_done <=
                1'b0;

            /*
             * ====================================================
             * STREAMING FAST PATH
             * ====================================================
             *
             * edit_enable=0 packets never enter packet_mem and
             * never execute checksum states.
             *
             * One accepted input beat therefore corresponds to
             * one accepted output beat in the same cycle.
             */
            if (
                (state == ST_CAPTURE &&
                 !edit_enable) ||
                state == ST_BYPASS
            ) begin

                if (s_axis_tvalid &&
                    s_axis_tready) begin

                    if (state == ST_CAPTURE)
                        edit_error <=
                            1'b0;

                    if (s_axis_tlast) begin

                        edit_done <=
                            1'b1;

                        state <=
                            ST_CAPTURE;

                        byte_count <=
                            16'd0;

                        packet_length <=
                            16'd0;

                        output_offset <=
                            16'd0;

                    end
                    else begin

                        state <=
                            ST_BYPASS;

                    end

                end

            end
            else begin

            case (state)

                /*
                 * ------------------------------------------------
                 * PACKET CAPTURE
                 * ------------------------------------------------
                 */
                ST_CAPTURE: begin

                    if (s_axis_tvalid &&
                        s_axis_tready) begin

                        if (byte_count == 0) begin

                            packet_edit_enable <=
                                edit_enable;

                            packet_rewrite_src_ip <=
                                rewrite_src_ip;

                            packet_rewrite_dst_ip <=
                                rewrite_dst_ip;

                            packet_rewrite_src_port <=
                                rewrite_src_port;

                            packet_rewrite_dst_port <=
                                rewrite_dst_port;

                            packet_new_src_ip <=
                                new_src_ip;

                            packet_new_dst_ip <=
                                new_dst_ip;

                            packet_new_src_port <=
                                new_src_port;

                            packet_new_dst_port <=
                                new_dst_port;

                            edit_error <=
                                1'b0;

                        end

                        if ((!s_axis_tlast &&
                             s_axis_tkeep !=
                             8'hFF) ||
                            (s_axis_tlast &&
                             !keep_contiguous(
                                 s_axis_tkeep
                             ))) begin

                            edit_error <=
                                1'b1;

                        end

                        for (lane = 0;
                             lane < 8;
                             lane = lane + 1) begin

                            if (s_axis_tkeep[
                                    lane
                                ] &&
                                ((byte_count +
                                  lane) <
                                 MAX_PACKET_BYTES)) begin

                                packet_mem[
                                    byte_count +
                                    lane
                                ] <=
                                    s_axis_tdata[
                                        lane*8 +: 8
                                    ];

                            end

                        end

                        if (s_axis_tlast) begin

                            packet_length <=
                                byte_count +
                                popcount8(
                                    s_axis_tkeep
                                );

                            byte_count <=
                                byte_count +
                                popcount8(
                                    s_axis_tkeep
                                );

                            state <=
                                ST_PARSE_ETH;

                        end
                        else begin

                            byte_count <=
                                byte_count + 8;

                        end

                    end

                end

                /*
                 * ------------------------------------------------
                 * ETHERNET / VLAN PARSE
                 * ------------------------------------------------
                 */
                ST_PARSE_ETH: begin

                    if (!packet_edit_enable) begin

                        edit_done <=
                            1'b1;

                        state <=
                            ST_OUTPUT;

                        output_offset <=
                            16'd0;

                    end
                    else if (packet_length < 14) begin

                        edit_error <=
                            1'b1;

                        edit_done <=
                            1'b1;

                        state <=
                            ST_OUTPUT;

                        output_offset <=
                            16'd0;

                    end
                    else begin

                        ethertype_reg <= {
                            packet_mem[12],
                            packet_mem[13]
                        };

                        if ({
                            packet_mem[12],
                            packet_mem[13]
                        } == 16'h8100 ||
                            {
                            packet_mem[12],
                            packet_mem[13]
                        } == 16'h88A8) begin

                            if (packet_length < 18) begin

                                edit_error <=
                                    1'b1;

                                edit_done <=
                                    1'b1;

                                state <=
                                    ST_OUTPUT;

                                output_offset <=
                                    16'd0;

                            end
                            else begin

                                l3_offset <=
                                    16'd18;

                                ethertype_reg <= {
                                    packet_mem[16],
                                    packet_mem[17]
                                };

                                state <=
                                    ST_PARSE_IP;

                            end

                        end
                        else begin

                            l3_offset <=
                                16'd14;

                            state <=
                                ST_PARSE_IP;

                        end

                    end

                end

                /*
                 * ------------------------------------------------
                 * IPv4 / L4 STRUCTURE VALIDATION
                 * ------------------------------------------------
                 */
                ST_PARSE_IP: begin

                    if (ethertype_reg !=
                        16'h0800) begin

                        edit_error <=
                            1'b1;

                        edit_done <=
                            1'b1;

                        output_offset <=
                            16'd0;

                        state <=
                            ST_OUTPUT;

                    end
                    else if (
                        packet_length <
                        (l3_offset + 20)
                    ) begin

                        edit_error <=
                            1'b1;

                        edit_done <=
                            1'b1;

                        output_offset <=
                            16'd0;

                        state <=
                            ST_OUTPUT;

                    end
                    else if (
                        packet_mem[
                            l3_offset
                        ][7:4] != 4'h4 ||
                        packet_mem[
                            l3_offset
                        ][3:0] < 4'd5
                    ) begin

                        edit_error <=
                            1'b1;

                        edit_done <=
                            1'b1;

                        output_offset <=
                            16'd0;

                        state <=
                            ST_OUTPUT;

                    end
                    else begin

                        ip_header_length <=
                            {
                                12'd0,
                                packet_mem[
                                    l3_offset
                                ][3:0]
                            } << 2;

                        ip_total_length <= {
                            packet_mem[
                                l3_offset + 2
                            ],
                            packet_mem[
                                l3_offset + 3
                            ]
                        };

                        protocol_reg <=
                            packet_mem[
                                l3_offset + 9
                            ];

                        l4_offset <=
                            l3_offset +
                            ({
                                12'd0,
                                packet_mem[
                                    l3_offset
                                ][3:0]
                            } << 2);

                        l4_length <=
                            {
                                packet_mem[
                                    l3_offset + 2
                                ],
                                packet_mem[
                                    l3_offset + 3
                                ]
                            } -
                            ({
                                12'd0,
                                packet_mem[
                                    l3_offset
                                ][3:0]
                            } << 2);

                        if ({
                            packet_mem[
                                l3_offset + 2
                            ],
                            packet_mem[
                                l3_offset + 3
                            ]
                        } <
                            ({
                                12'd0,
                                packet_mem[
                                    l3_offset
                                ][3:0]
                            } << 2) ||
                            packet_length <
                            (l3_offset +
                             {
                                packet_mem[
                                    l3_offset + 2
                                ],
                                packet_mem[
                                    l3_offset + 3
                                ]
                             })) begin

                            edit_error <=
                                1'b1;

                            edit_done <=
                                1'b1;

                            output_offset <=
                                16'd0;

                            state <=
                                ST_OUTPUT;

                        end
                        else begin

                            state <=
                                ST_APPLY;

                        end

                    end

                end

                /*
                 * ------------------------------------------------
                 * APPLY EDITS AND ZERO CHECKSUM FIELDS
                 * ------------------------------------------------
                 */
                ST_APPLY: begin

                    if ((packet_rewrite_src_port ||
                         packet_rewrite_dst_port) &&
                        protocol_reg != 8'd17 &&
                        protocol_reg != 8'd6) begin

                        edit_error <=
                            1'b1;

                        edit_done <=
                            1'b1;

                        output_offset <=
                            16'd0;

                        state <=
                            ST_OUTPUT;

                    end
                    else if (
                        (protocol_reg == 8'd17 &&
                         l4_length < 8) ||
                        (protocol_reg == 8'd6 &&
                         l4_length < 20)
                    ) begin

                        edit_error <=
                            1'b1;

                        edit_done <=
                            1'b1;

                        output_offset <=
                            16'd0;

                        state <=
                            ST_OUTPUT;

                    end
                    else begin

                        if (packet_rewrite_src_ip) begin

                            packet_mem[
                                l3_offset + 12
                            ] <=
                                packet_new_src_ip[
                                    31:24
                                ];

                            packet_mem[
                                l3_offset + 13
                            ] <=
                                packet_new_src_ip[
                                    23:16
                                ];

                            packet_mem[
                                l3_offset + 14
                            ] <=
                                packet_new_src_ip[
                                    15:8
                                ];

                            packet_mem[
                                l3_offset + 15
                            ] <=
                                packet_new_src_ip[
                                    7:0
                                ];

                        end

                        if (packet_rewrite_dst_ip) begin

                            packet_mem[
                                l3_offset + 16
                            ] <=
                                packet_new_dst_ip[
                                    31:24
                                ];

                            packet_mem[
                                l3_offset + 17
                            ] <=
                                packet_new_dst_ip[
                                    23:16
                                ];

                            packet_mem[
                                l3_offset + 18
                            ] <=
                                packet_new_dst_ip[
                                    15:8
                                ];

                            packet_mem[
                                l3_offset + 19
                            ] <=
                                packet_new_dst_ip[
                                    7:0
                                ];

                        end

                        packet_mem[
                            l3_offset + 10
                        ] <= 8'h00;

                        packet_mem[
                            l3_offset + 11
                        ] <= 8'h00;

                        if (protocol_reg == 8'd17 ||
                            protocol_reg == 8'd6) begin

                            if (packet_rewrite_src_port) begin

                                packet_mem[
                                    l4_offset
                                ] <=
                                    packet_new_src_port[
                                        15:8
                                    ];

                                packet_mem[
                                    l4_offset + 1
                                ] <=
                                    packet_new_src_port[
                                        7:0
                                    ];

                            end

                            if (packet_rewrite_dst_port) begin

                                packet_mem[
                                    l4_offset + 2
                                ] <=
                                    packet_new_dst_port[
                                        15:8
                                    ];

                                packet_mem[
                                    l4_offset + 3
                                ] <=
                                    packet_new_dst_port[
                                        7:0
                                    ];

                            end

                            if (protocol_reg == 8'd17) begin

                                packet_mem[
                                    l4_offset + 6
                                ] <= 8'h00;

                                packet_mem[
                                    l4_offset + 7
                                ] <= 8'h00;

                            end
                            else begin

                                packet_mem[
                                    l4_offset + 16
                                ] <= 8'h00;

                                packet_mem[
                                    l4_offset + 17
                                ] <= 8'h00;

                            end

                        end

                        state <=
                            ST_IP_SUM_INIT;

                    end

                end

                /*
                 * ------------------------------------------------
                 * IPv4 HEADER CHECKSUM
                 * ------------------------------------------------
                 */
                ST_IP_SUM_INIT: begin

                    sum_acc <=
                        32'd0;

                    sum_index <=
                        16'd0;

                    state <=
                        ST_IP_SUM;

                end

                ST_IP_SUM: begin

                    if ((sum_index + 2) >=
                        ip_header_length) begin

                        checksum_result <=
                            ~fold16(
                                final_sum
                            );

                        state <=
                            ST_IP_WRITE;

                    end
                    else begin

                        sum_acc <=
                            final_sum;

                        sum_index <=
                            sum_index + 2;

                    end

                end

                ST_IP_WRITE: begin

                    packet_mem[
                        l3_offset + 10
                    ] <=
                        checksum_result[
                            15:8
                        ];

                    packet_mem[
                        l3_offset + 11
                    ] <=
                        checksum_result[
                            7:0
                        ];

                    if (protocol_reg == 8'd17 ||
                        protocol_reg == 8'd6) begin

                        state <=
                            ST_L4_SUM_INIT;

                    end
                    else begin

                        edit_done <=
                            1'b1;

                        output_offset <=
                            16'd0;

                        state <=
                            ST_OUTPUT;

                    end

                end

                /*
                 * ------------------------------------------------
                 * UDP/TCP PSEUDOHEADER + PAYLOAD CHECKSUM
                 * ------------------------------------------------
                 */
                ST_L4_SUM_INIT: begin

                    sum_acc <=
                        32'd0 +

                        {16'd0,
                         packet_mem[
                             l3_offset + 12
                         ],
                         packet_mem[
                             l3_offset + 13
                         ]} +

                        {16'd0,
                         packet_mem[
                             l3_offset + 14
                         ],
                         packet_mem[
                             l3_offset + 15
                         ]} +

                        {16'd0,
                         packet_mem[
                             l3_offset + 16
                         ],
                         packet_mem[
                             l3_offset + 17
                         ]} +

                        {16'd0,
                         packet_mem[
                             l3_offset + 18
                         ],
                         packet_mem[
                             l3_offset + 19
                         ]} +

                        {16'd0,
                         8'h00,
                         protocol_reg} +

                        {16'd0,
                         l4_length};

                    sum_index <=
                        16'd0;

                    state <=
                        ST_L4_SUM;

                end

                ST_L4_SUM: begin

                    if ((sum_index + 2) >=
                        l4_length) begin

                        checksum_result <=
                            ~fold16(
                                final_sum
                            );

                        state <=
                            ST_L4_WRITE;

                    end
                    else begin

                        sum_acc <=
                            final_sum;

                        sum_index <=
                            sum_index + 2;

                    end

                end

                ST_L4_WRITE: begin

                    if (protocol_reg == 8'd17) begin

                        /*
                         * UDP checksum result 0 is transmitted
                         * as all ones.
                         */
                        if (checksum_result == 16'h0000) begin

                            packet_mem[
                                l4_offset + 6
                            ] <= 8'hFF;

                            packet_mem[
                                l4_offset + 7
                            ] <= 8'hFF;

                        end
                        else begin

                            packet_mem[
                                l4_offset + 6
                            ] <=
                                checksum_result[
                                    15:8
                                ];

                            packet_mem[
                                l4_offset + 7
                            ] <=
                                checksum_result[
                                    7:0
                                ];

                        end

                    end
                    else begin

                        packet_mem[
                            l4_offset + 16
                        ] <=
                            checksum_result[
                                15:8
                            ];

                        packet_mem[
                            l4_offset + 17
                        ] <=
                            checksum_result[
                                7:0
                            ];

                    end

                    edit_done <=
                        1'b1;

                    output_offset <=
                        16'd0;

                    state <=
                        ST_OUTPUT;

                end

                /*
                 * ------------------------------------------------
                 * OUTPUT
                 * ------------------------------------------------
                 */
                ST_OUTPUT: begin

                    if (m_axis_tvalid &&
                        m_axis_tready) begin

                        if (m_axis_tlast) begin

                            state <=
                                ST_CAPTURE;

                            byte_count <=
                                16'd0;

                            packet_length <=
                                16'd0;

                            output_offset <=
                                16'd0;

                        end
                        else begin

                            output_offset <=
                                output_offset + 8;

                        end

                    end

                end

                default:
                    state <=
                        ST_CAPTURE;

            endcase

            end

        end

    end

endmodule
