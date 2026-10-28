`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Module:
 *   Four-Queue Packet-Aware Egress Scheduler
 *
 * Functions:
 *   - four independent hardware egress queues
 *   - packet-boundary-preserving arbitration
 *   - weighted round-robin scheduling
 *   - programmable per-queue packet gap / rate control
 *   - AXI4-Stream backpressure
 *   - queue occupancy and packet telemetry
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module p08_egress_scheduler #(
    parameter integer QUEUE_DEPTH_BEATS = 256
)(
    input  logic         clk,
    input  logic         aresetn,

    /*
     * Packet input.
     *
     * s_packet_queue is sampled on the first accepted beat
     * and remains authoritative for the complete packet.
     */
    input  logic [63:0]  s_axis_tdata,
    input  logic [7:0]   s_axis_tkeep,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,
    input  logic         s_axis_tlast,

    input  logic [1:0]   s_packet_queue,

    /*
     * Runtime QoS configuration.
     *
     * weight:
     *   packet-level weighted round-robin credit.
     *   zero is clamped to one.
     *
     * gap_cycles:
     *   minimum scheduler holdoff after a packet from
     *   the selected queue completes.
     */
    input  logic         cfg_we,
    input  logic [1:0]   cfg_queue,
    input  logic [3:0]   cfg_weight,
    input  logic [15:0]  cfg_gap_cycles,

    /*
     * Scheduled packet output.
     */
    output logic [63:0]  m_axis_tdata,
    output logic [7:0]   m_axis_tkeep,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,
    output logic         m_axis_tlast,

    output logic [1:0]   m_packet_queue,

    /*
     * Queue telemetry.
     */
    output logic [15:0]  q0_occupancy,
    output logic [15:0]  q1_occupancy,
    output logic [15:0]  q2_occupancy,
    output logic [15:0]  q3_occupancy,

    output logic [15:0]  q0_packets,
    output logic [15:0]  q1_packets,
    output logic [15:0]  q2_packets,
    output logic [15:0]  q3_packets,

    output logic [31:0]  packets_enqueued,
    output logic [31:0]  packets_transmitted,

    output logic         packet_sent_event,
    output logic [1:0]   packet_sent_queue
);

    localparam integer PTR_WIDTH =
        $clog2(QUEUE_DEPTH_BEATS);

    /*
     * Beat storage.
     */
    logic [63:0] data_mem [0:3][0:QUEUE_DEPTH_BEATS-1];
    logic [7:0]  keep_mem [0:3][0:QUEUE_DEPTH_BEATS-1];
    logic        last_mem [0:3][0:QUEUE_DEPTH_BEATS-1];

    logic [PTR_WIDTH-1:0] wr_ptr [0:3];
    logic [PTR_WIDTH-1:0] rd_ptr [0:3];

    logic [PTR_WIDTH:0] beat_count [0:3];
    logic [15:0] packet_count [0:3];

    /*
     * QoS configuration/state.
     */
    logic [3:0]  queue_weight [0:3];
    logic [3:0]  queue_credit [0:3];

    logic [15:0] queue_gap_cfg [0:3];
    logic [15:0] queue_gap_count [0:3];

    /*
     * Input packet queue ownership.
     */
    logic       ingress_active;
    logic [1:0] ingress_queue;

    logic [1:0] enqueue_queue;

    assign enqueue_queue =
        ingress_active ?
        ingress_queue :
        s_packet_queue;

    always_comb begin

        if (!aresetn) begin

            s_axis_tready =
                1'b0;

        end
        else begin

            s_axis_tready =
                (beat_count[
                    enqueue_queue
                 ] < QUEUE_DEPTH_BEATS);

        end

    end

    logic enqueue_fire;

    assign enqueue_fire =
        s_axis_tvalid &&
        s_axis_tready;

    /*
     * Scheduler state.
     */
    logic       output_active;
    logic [1:0] active_queue;

    logic [1:0] rr_pointer;

    logic       select_found;
    logic [1:0] select_queue;
    logic       any_eligible;

    integer scan;
    integer candidate;

    always_comb begin

        select_found =
            1'b0;

        select_queue =
            2'd0;

        any_eligible =
            1'b0;

        for (scan = 0;
             scan < 4;
             scan = scan + 1) begin

            candidate =
                (rr_pointer + scan) & 3;

            if (packet_count[candidate] != 0 &&
                queue_gap_count[candidate] == 0) begin

                any_eligible =
                    1'b1;

                if (!select_found &&
                    queue_credit[candidate] != 0) begin

                    select_found =
                        1'b1;

                    select_queue =
                        candidate[1:0];

                end

            end

        end

    end

    /*
     * Output is locked to one queue until TLAST.
     * Packet interleaving is therefore impossible.
     */
    always_comb begin

        m_axis_tdata  =
            64'd0;

        m_axis_tkeep  =
            8'd0;

        m_axis_tvalid =
            1'b0;

        m_axis_tlast  =
            1'b0;

        m_packet_queue =
            active_queue;

        if (output_active &&
            beat_count[active_queue] != 0) begin

            m_axis_tdata =
                data_mem[
                    active_queue
                ][
                    rd_ptr[
                        active_queue
                    ]
                ];

            m_axis_tkeep =
                keep_mem[
                    active_queue
                ][
                    rd_ptr[
                        active_queue
                    ]
                ];

            m_axis_tlast =
                last_mem[
                    active_queue
                ][
                    rd_ptr[
                        active_queue
                    ]
                ];

            m_axis_tvalid =
                1'b1;

        end

    end

    logic dequeue_fire;

    assign dequeue_fire =
        m_axis_tvalid &&
        m_axis_tready;

    integer q;

    logic enqueue_packet;
    logic dequeue_packet;

    always_comb begin

        enqueue_packet =
            enqueue_fire &&
            s_axis_tlast;

        dequeue_packet =
            dequeue_fire &&
            m_axis_tlast;

    end

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            ingress_active <=
                1'b0;

            ingress_queue <=
                2'd0;

            output_active <=
                1'b0;

            active_queue <=
                2'd0;

            rr_pointer <=
                2'd0;

            packets_enqueued <=
                32'd0;

            packets_transmitted <=
                32'd0;

            packet_sent_event <=
                1'b0;

            packet_sent_queue <=
                2'd0;

            for (q = 0;
                 q < 4;
                 q = q + 1) begin

                wr_ptr[q] <=
                    '0;

                rd_ptr[q] <=
                    '0;

                beat_count[q] <=
                    '0;

                packet_count[q] <=
                    16'd0;

                queue_weight[q] <=
                    4'd1;

                queue_credit[q] <=
                    4'd1;

                queue_gap_cfg[q] <=
                    16'd0;

                queue_gap_count[q] <=
                    16'd0;

            end

        end
        else begin

            packet_sent_event <=
                1'b0;

            /*
             * -----------------------------------------------
             * QoS CONFIGURATION
             * -----------------------------------------------
             */
            if (cfg_we) begin

                if (cfg_weight == 0) begin

                    queue_weight[
                        cfg_queue
                    ] <=
                        4'd1;

                    queue_credit[
                        cfg_queue
                    ] <=
                        4'd1;

                end
                else begin

                    queue_weight[
                        cfg_queue
                    ] <=
                        cfg_weight;

                    queue_credit[
                        cfg_queue
                    ] <=
                        cfg_weight;

                end

                queue_gap_cfg[
                    cfg_queue
                ] <=
                    cfg_gap_cycles;

            end

            /*
             * Rate-control countdowns.
             */
            for (q = 0;
                 q < 4;
                 q = q + 1) begin

                if (queue_gap_count[q] != 0)
                    queue_gap_count[q] <=
                        queue_gap_count[q] -
                        1'b1;

            end

            /*
             * -----------------------------------------------
             * INGRESS
             * -----------------------------------------------
             */
            if (enqueue_fire) begin

                data_mem[
                    enqueue_queue
                ][
                    wr_ptr[
                        enqueue_queue
                    ]
                ] <=
                    s_axis_tdata;

                keep_mem[
                    enqueue_queue
                ][
                    wr_ptr[
                        enqueue_queue
                    ]
                ] <=
                    s_axis_tkeep;

                last_mem[
                    enqueue_queue
                ][
                    wr_ptr[
                        enqueue_queue
                    ]
                ] <=
                    s_axis_tlast;

                wr_ptr[
                    enqueue_queue
                ] <=
                    wr_ptr[
                        enqueue_queue
                    ] +
                    1'b1;

                if (!ingress_active &&
                    !s_axis_tlast) begin

                    ingress_active <=
                        1'b1;

                    ingress_queue <=
                        s_packet_queue;

                end
                else if (ingress_active &&
                         s_axis_tlast) begin

                    ingress_active <=
                        1'b0;

                end

                if (s_axis_tlast)
                    packets_enqueued <=
                        packets_enqueued +
                        1'b1;

            end

            /*
             * -----------------------------------------------
             * OUTPUT READ POINTER
             * -----------------------------------------------
             */
            if (dequeue_fire) begin

                rd_ptr[
                    active_queue
                ] <=
                    rd_ptr[
                        active_queue
                    ] +
                    1'b1;

                if (m_axis_tlast) begin

                    packets_transmitted <=
                        packets_transmitted +
                        1'b1;

                    packet_sent_event <=
                        1'b1;

                    packet_sent_queue <=
                        active_queue;

                    queue_gap_count[
                        active_queue
                    ] <=
                        queue_gap_cfg[
                            active_queue
                        ];

                    output_active <=
                        1'b0;

                end

            end

            /*
             * -----------------------------------------------
             * BEAT COUNTS
             * -----------------------------------------------
             */
            for (q = 0;
                 q < 4;
                 q = q + 1) begin

                case ({
                    enqueue_fire &&
                    (enqueue_queue == q),

                    dequeue_fire &&
                    (active_queue == q)
                })

                    2'b10:
                        beat_count[q] <=
                            beat_count[q] +
                            1'b1;

                    2'b01:
                        beat_count[q] <=
                            beat_count[q] -
                            1'b1;

                    default:
                        beat_count[q] <=
                            beat_count[q];

                endcase

                /*
                 * Complete-packet availability.
                 */
                case ({
                    enqueue_packet &&
                    (enqueue_queue == q),

                    dequeue_packet &&
                    (active_queue == q)
                })

                    2'b10:
                        packet_count[q] <=
                            packet_count[q] +
                            1'b1;

                    2'b01:
                        packet_count[q] <=
                            packet_count[q] -
                            1'b1;

                    default:
                        packet_count[q] <=
                            packet_count[q];

                endcase

            end

            /*
             * -----------------------------------------------
             * PACKET-AWARE WEIGHTED ROUND ROBIN
             * -----------------------------------------------
             */
            if (!output_active) begin

                if (select_found) begin

                    active_queue <=
                        select_queue;

                    output_active <=
                        1'b1;

                    rr_pointer <=
                        select_queue +
                        1'b1;

                    queue_credit[
                        select_queue
                    ] <=
                        queue_credit[
                            select_queue
                        ] -
                        1'b1;

                end
                else if (any_eligible) begin

                    /*
                     * All eligible credits exhausted:
                     * begin a new WRR round.
                     */
                    for (q = 0;
                         q < 4;
                         q = q + 1) begin

                        queue_credit[q] <=
                            queue_weight[q];

                    end

                end

            end

        end

    end

    /*
     * Stable telemetry.
     */
    always_comb begin

        q0_occupancy =
            beat_count[0];

        q1_occupancy =
            beat_count[1];

        q2_occupancy =
            beat_count[2];

        q3_occupancy =
            beat_count[3];

        q0_packets =
            packet_count[0];

        q1_packets =
            packet_count[1];

        q2_packets =
            packet_count[2];

        q3_packets =
            packet_count[3];

    end

endmodule
