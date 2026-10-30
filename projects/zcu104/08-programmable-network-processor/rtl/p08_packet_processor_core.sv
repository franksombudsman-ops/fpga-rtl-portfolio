`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Module:
 *   Integrated Programmable Packet Processor Core
 *
 * Datapath:
 *
 *   AXI4-Stream Input
 *          |
 *          v
 *   Ethernet/VLAN/IPv4/L4 Parser
 *          |
 *          v
 *   32-Entry Match/Action Engine
 *          |
 *          v
 *   Decision-Synchronized Packet Buffer
 *          |
 *          +------ DROP
 *          |
 *          v
 *   IPv4 / UDP / TCP Packet Editor
 *          |
 *          v
 *   Four-Queue QoS Egress Scheduler
 *          |
 *          v
 *   AXI4-Stream Output
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module p08_packet_processor_core (

    input  logic         clk,
    input  logic         aresetn,

    /*
     * Packet ingress.
     */
    input  logic [63:0]  s_axis_tdata,
    input  logic [7:0]   s_axis_tkeep,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,
    input  logic         s_axis_tlast,

    /*
     * Packet egress.
     */
    output logic [63:0]  m_axis_tdata,
    output logic [7:0]   m_axis_tkeep,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,
    output logic         m_axis_tlast,

    output logic [1:0]   m_packet_queue,

    /*
     * Match/action rule programming.
     */
    input  logic         cfg_rule_we,
    input  logic [4:0]   cfg_rule_index,
    input  logic         cfg_rule_valid,

    input  logic         cfg_vlan_present_value,
    input  logic         cfg_vlan_present_mask,

    input  logic [11:0]  cfg_vlan_value,
    input  logic [11:0]  cfg_vlan_mask,

    input  logic [31:0]  cfg_src_ip_value,
    input  logic [31:0]  cfg_src_ip_mask,

    input  logic [31:0]  cfg_dst_ip_value,
    input  logic [31:0]  cfg_dst_ip_mask,

    input  logic [7:0]   cfg_protocol_value,
    input  logic [7:0]   cfg_protocol_mask,

    input  logic [15:0]  cfg_src_port_value,
    input  logic [15:0]  cfg_src_port_mask,

    input  logic [15:0]  cfg_dst_port_value,
    input  logic [15:0]  cfg_dst_port_mask,

    input  logic [2:0]   cfg_action,
    input  logic [1:0]   cfg_action_queue,

    /*
     * Per-rule MODIFY profile.
     */
    input  logic         cfg_edit_we,
    input  logic [4:0]   cfg_edit_index,

    input  logic         cfg_rewrite_src_ip,
    input  logic         cfg_rewrite_dst_ip,
    input  logic         cfg_rewrite_src_port,
    input  logic         cfg_rewrite_dst_port,

    input  logic [31:0]  cfg_new_src_ip,
    input  logic [31:0]  cfg_new_dst_ip,
    input  logic [15:0]  cfg_new_src_port,
    input  logic [15:0]  cfg_new_dst_port,

    /*
     * Egress QoS configuration.
     */
    input  logic         cfg_qos_we,
    input  logic [1:0]   cfg_qos_queue,
    input  logic [3:0]   cfg_qos_weight,
    input  logic [15:0]  cfg_qos_gap_cycles,

    /*
     * Core telemetry.
     */
    output logic [31:0]  packets_accepted,
    output logic [31:0]  packets_forwarded,
    output logic [31:0]  packets_dropped,

    output logic [31:0]  scheduler_enqueued,
    output logic [31:0]  scheduler_transmitted
);

    localparam logic [2:0] ACTION_FORWARD  = 3'd0;
    localparam logic [2:0] ACTION_DROP     = 3'd1;
    localparam logic [2:0] ACTION_REDIRECT = 3'd2;
    localparam logic [2:0] ACTION_MODIFY   = 3'd3;

    /*
     * ---------------------------------------------------------
     * PARSER → ACTION BUFFER STREAM
     * ---------------------------------------------------------
     */

    logic [63:0] parser_tdata;
    logic [7:0]  parser_tkeep;
    logic        parser_tvalid;
    logic        parser_tready;
    logic        parser_tlast;

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

    p08_packet_parser u_parser (

        .clk            (clk),
        .aresetn        (aresetn),

        .s_axis_tdata   (s_axis_tdata),
        .s_axis_tkeep   (s_axis_tkeep),
        .s_axis_tvalid  (s_axis_tvalid),
        .s_axis_tready  (s_axis_tready),
        .s_axis_tlast   (s_axis_tlast),

        .m_axis_tdata   (parser_tdata),
        .m_axis_tkeep   (parser_tkeep),
        .m_axis_tvalid  (parser_tvalid),
        .m_axis_tready  (parser_tready),
        .m_axis_tlast   (parser_tlast),

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
     * ---------------------------------------------------------
     * MATCH / ACTION
     * ---------------------------------------------------------
     */

    logic        decision_valid;
    logic        decision_matched;
    logic [4:0]  decision_rule;

    logic [2:0]  decision_action;
    logic [1:0]  decision_queue;

    logic [31:0] flow_hash;

    p08_match_action_engine u_match_action (

        .clk                     (clk),
        .aresetn                 (aresetn),

        .metadata_valid          (metadata_valid),
        .malformed               (malformed),

        .vlan_present            (vlan_present),
        .vlan_id                 (vlan_id),

        .src_ipv4                (src_ipv4),
        .dst_ipv4                (dst_ipv4),
        .ip_protocol             (ip_protocol),
        .src_port                (src_port),
        .dst_port                (dst_port),

        .cfg_rule_we             (cfg_rule_we),
        .cfg_rule_index          (cfg_rule_index),
        .cfg_rule_valid          (cfg_rule_valid),

        .cfg_vlan_present_value  (cfg_vlan_present_value),
        .cfg_vlan_present_mask   (cfg_vlan_present_mask),

        .cfg_vlan_value          (cfg_vlan_value),
        .cfg_vlan_mask           (cfg_vlan_mask),

        .cfg_src_ip_value        (cfg_src_ip_value),
        .cfg_src_ip_mask         (cfg_src_ip_mask),

        .cfg_dst_ip_value        (cfg_dst_ip_value),
        .cfg_dst_ip_mask         (cfg_dst_ip_mask),

        .cfg_protocol_value      (cfg_protocol_value),
        .cfg_protocol_mask       (cfg_protocol_mask),

        .cfg_src_port_value      (cfg_src_port_value),
        .cfg_src_port_mask       (cfg_src_port_mask),

        .cfg_dst_port_value      (cfg_dst_port_value),
        .cfg_dst_port_mask       (cfg_dst_port_mask),

        .cfg_action              (cfg_action),
        .cfg_queue               (cfg_action_queue),

        .decision_valid          (decision_valid),
        .matched                 (decision_matched),
        .matched_rule            (decision_rule),

        .action                  (decision_action),
        .queue_id                (decision_queue),

        .flow_hash               (flow_hash)
    );

    /*
     * ---------------------------------------------------------
     * PER-RULE MODIFY PROFILE MEMORY
     * ---------------------------------------------------------
     */

    logic profile_rewrite_src_ip   [0:31];
    logic profile_rewrite_dst_ip   [0:31];
    logic profile_rewrite_src_port [0:31];
    logic profile_rewrite_dst_port [0:31];

    logic [31:0] profile_new_src_ip [0:31];
    logic [31:0] profile_new_dst_ip [0:31];

    logic [15:0] profile_new_src_port [0:31];
    logic [15:0] profile_new_dst_port [0:31];

    integer p;

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            for (p = 0; p < 32; p = p + 1) begin

                profile_rewrite_src_ip[p] <=
                    1'b0;

                profile_rewrite_dst_ip[p] <=
                    1'b0;

                profile_rewrite_src_port[p] <=
                    1'b0;

                profile_rewrite_dst_port[p] <=
                    1'b0;

                profile_new_src_ip[p] <=
                    32'd0;

                profile_new_dst_ip[p] <=
                    32'd0;

                profile_new_src_port[p] <=
                    16'd0;

                profile_new_dst_port[p] <=
                    16'd0;

            end

        end
        else if (cfg_edit_we) begin

            profile_rewrite_src_ip[
                cfg_edit_index
            ] <=
                cfg_rewrite_src_ip;

            profile_rewrite_dst_ip[
                cfg_edit_index
            ] <=
                cfg_rewrite_dst_ip;

            profile_rewrite_src_port[
                cfg_edit_index
            ] <=
                cfg_rewrite_src_port;

            profile_rewrite_dst_port[
                cfg_edit_index
            ] <=
                cfg_rewrite_dst_port;

            profile_new_src_ip[
                cfg_edit_index
            ] <=
                cfg_new_src_ip;

            profile_new_dst_ip[
                cfg_edit_index
            ] <=
                cfg_new_dst_ip;

            profile_new_src_port[
                cfg_edit_index
            ] <=
                cfg_new_src_port;

            profile_new_dst_port[
                cfg_edit_index
            ] <=
                cfg_new_dst_port;

        end

    end

    /*
     * Each non-DROP packet gets one rule/profile token.
     *
     * The dual-bank action buffer can have at most two
     * non-drop packets outstanding, so a two-entry token FIFO
     * is sufficient for this architecture.
     */
    logic [4:0] profile_fifo [0:1];

    logic profile_wr;
    logic profile_rd;

    logic [1:0] profile_count;

    logic profile_push;
    logic profile_pop;

    assign profile_push =
        decision_valid &&
        (decision_action != ACTION_DROP);

    /*
     * ---------------------------------------------------------
     * DECISION-SYNCHRONIZED PACKET BUFFER
     * ---------------------------------------------------------
     */

    logic [63:0] action_tdata;
    logic [7:0]  action_tkeep;
    logic        action_tvalid;
    logic        action_tready;
    logic        action_tlast;

    logic [2:0]  action_packet_action;
    logic [1:0]  action_packet_queue;

    logic forward_event;
    logic drop_event;
    logic redirect_event;
    logic modify_event;
    logic count_event;

    p08_packet_action_buffer u_action_buffer (

        .clk                (clk),
        .aresetn            (aresetn),

        .s_axis_tdata       (parser_tdata),
        .s_axis_tkeep       (parser_tkeep),
        .s_axis_tvalid      (parser_tvalid),
        .s_axis_tready      (parser_tready),
        .s_axis_tlast       (parser_tlast),

        .decision_valid     (decision_valid),
        .decision_action    (decision_action),
        .decision_queue     (decision_queue),

        .m_axis_tdata       (action_tdata),
        .m_axis_tkeep       (action_tkeep),
        .m_axis_tvalid      (action_tvalid),
        .m_axis_tready      (action_tready),
        .m_axis_tlast       (action_tlast),

        .m_packet_action    (action_packet_action),
        .m_packet_queue     (action_packet_queue),

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
     * ---------------------------------------------------------
     * PACKET EDITOR SIDEBAND SYNCHRONIZATION
     * ---------------------------------------------------------
     */

    logic editor_input_active;

    logic [1:0] editor_queue_reg;
    logic [1:0] scheduler_packet_queue;

    logic [4:0] editor_profile_index;

    logic editor_first_transfer;

    logic [63:0] editor_tdata;
    logic [7:0]  editor_tkeep;
    logic        editor_tvalid;
    logic        editor_input_ready;
    logic        editor_output_ready;
    logic        editor_tlast;

    logic editor_done;
    logic editor_error;

    /*
     * The first beat cannot enter the editor until its profile
     * token is available.
     */
    assign action_tready =
        editor_input_ready &&
        (
            editor_input_active ||
            (profile_count != 0)
        );

    assign editor_first_transfer =
        action_tvalid &&
        action_tready &&
        !editor_input_active;

    /*
     * Fast-path queue sideband alignment.
     *
     * On the first beat of a non-MODIFY packet, the packet data
     * can now pass combinationally through the editor. The queue
     * register is updated on that same clock edge, so its old
     * value cannot be used for the first scheduler beat.
     *
     * Use the live action-buffer queue for that first bypass beat.
     * Once the first beat transfers, editor_queue_reg is valid for
     * the remainder of the packet.
     *
     * MODIFY packets are store-and-forward and therefore use the
     * registered queue during their later replay.
     */
    assign scheduler_packet_queue =
        (
            !editor_input_active &&
            action_tvalid &&
            (action_packet_action != ACTION_MODIFY)
        )
        ? action_packet_queue
        : editor_queue_reg;

    assign profile_pop =
        editor_first_transfer;

    assign editor_profile_index =
        profile_fifo[
            profile_rd
        ];

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            profile_wr <=
                1'b0;

            profile_rd <=
                1'b0;

            profile_count <=
                2'd0;

            editor_input_active <=
                1'b0;

            editor_queue_reg <=
                2'd0;

        end
        else begin

            /*
             * Push token when match/action approves
             * a packet for the output path.
             */
            if (profile_push) begin

                profile_fifo[
                    profile_wr
                ] <=
                    decision_rule;

                profile_wr <=
                    profile_wr +
                    1'b1;

            end

            /*
             * Pop token when the corresponding packet begins
             * entering the editor.
             */
            if (profile_pop) begin

                profile_rd <=
                    profile_rd +
                    1'b1;

            end

            case ({
                profile_push,
                profile_pop
            })

                2'b10:
                    profile_count <=
                        profile_count +
                        1'b1;

                2'b01:
                    profile_count <=
                        profile_count -
                        1'b1;

                default:
                    profile_count <=
                        profile_count;

            endcase

            if (action_tvalid &&
                action_tready) begin

                if (!editor_input_active) begin

                    editor_queue_reg <=
                        action_packet_queue;

                    if (!action_tlast)
                        editor_input_active <=
                            1'b1;

                end
                else if (action_tlast) begin

                    editor_input_active <=
                        1'b0;

                end

            end

        end

    end

    p08_packet_editor u_editor (

        .clk                (clk),
        .aresetn            (aresetn),

        .s_axis_tdata       (action_tdata),
        .s_axis_tkeep       (action_tkeep),
        .s_axis_tvalid      (
            action_tvalid &&
            (
                editor_input_active ||
                (profile_count != 0)
            )
        ),
        .s_axis_tready      (editor_input_ready),
        .s_axis_tlast       (action_tlast),

        .edit_enable        (
            action_packet_action ==
            ACTION_MODIFY
        ),

        .rewrite_src_ip     (
            profile_rewrite_src_ip[
                editor_profile_index
            ]
        ),

        .rewrite_dst_ip     (
            profile_rewrite_dst_ip[
                editor_profile_index
            ]
        ),

        .rewrite_src_port   (
            profile_rewrite_src_port[
                editor_profile_index
            ]
        ),

        .rewrite_dst_port   (
            profile_rewrite_dst_port[
                editor_profile_index
            ]
        ),

        .new_src_ip         (
            profile_new_src_ip[
                editor_profile_index
            ]
        ),

        .new_dst_ip         (
            profile_new_dst_ip[
                editor_profile_index
            ]
        ),

        .new_src_port       (
            profile_new_src_port[
                editor_profile_index
            ]
        ),

        .new_dst_port       (
            profile_new_dst_port[
                editor_profile_index
            ]
        ),

        .m_axis_tdata       (editor_tdata),
        .m_axis_tkeep       (editor_tkeep),
        .m_axis_tvalid      (editor_tvalid),
        .m_axis_tready      (editor_output_ready),
        .m_axis_tlast       (editor_tlast),

        .edit_done          (editor_done),
        .edit_error         (editor_error)
    );

    /*
     * Important:
     *
     * The packet editor has independent input/output ready signals
     * in concept, but its existing interface names both sides with
     * a single m_axis_tready input and s_axis_tready output.
     *
     * Therefore split the scheduler-facing ready path explicitly.
     */

    /*
     * ---------------------------------------------------------
     * FOUR-QUEUE EGRESS SCHEDULER
     * ---------------------------------------------------------
     */

    logic [15:0] q0_occupancy;
    logic [15:0] q1_occupancy;
    logic [15:0] q2_occupancy;
    logic [15:0] q3_occupancy;

    logic [15:0] q0_packets;
    logic [15:0] q1_packets;
    logic [15:0] q2_packets;
    logic [15:0] q3_packets;

    logic packet_sent_event;
    logic [1:0] packet_sent_queue;

    p08_egress_scheduler u_scheduler (

        .clk                 (clk),
        .aresetn             (aresetn),

        .s_axis_tdata        (editor_tdata),
        .s_axis_tkeep        (editor_tkeep),
        .s_axis_tvalid       (editor_tvalid),
        .s_axis_tready       (editor_output_ready),
        .s_axis_tlast        (editor_tlast),

        .s_packet_queue      (scheduler_packet_queue),

        .cfg_we              (cfg_qos_we),
        .cfg_queue           (cfg_qos_queue),
        .cfg_weight          (cfg_qos_weight),
        .cfg_gap_cycles      (cfg_qos_gap_cycles),

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

        .packets_enqueued    (scheduler_enqueued),
        .packets_transmitted (scheduler_transmitted),

        .packet_sent_event   (packet_sent_event),
        .packet_sent_queue   (packet_sent_queue)
    );

endmodule
