`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Module:
 *   Programmable 5-Tuple Match / Action Engine
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module p08_match_action_engine #(
    parameter integer RULE_COUNT = 32
)(
    input  logic         clk,
    input  logic         aresetn,

    /*
     * Parsed metadata input.
     */
    input  logic         metadata_valid,
    input  logic         malformed,

    input  logic         vlan_present,
    input  logic [11:0]  vlan_id,

    input  logic [31:0]  src_ipv4,
    input  logic [31:0]  dst_ipv4,
    input  logic [7:0]   ip_protocol,
    input  logic [15:0]  src_port,
    input  logic [15:0]  dst_port,

    /*
     * Runtime rule programming interface.
     *
     * A rule becomes visible after cfg_rule_we is sampled.
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
    input  logic [1:0]   cfg_queue,

    /*
     * Decision output.
     */
    output logic         decision_valid,
    output logic         matched,
    output logic [4:0]   matched_rule,

    output logic [2:0]   action,
    output logic [1:0]   queue_id,

    /*
     * Hash of:
     * src IP, dst IP, protocol, src port, dst port.
     */
    output logic [31:0]  flow_hash
);

    localparam logic [2:0] ACTION_FORWARD  = 3'd0;
    localparam logic [2:0] ACTION_DROP     = 3'd1;
    localparam logic [2:0] ACTION_REDIRECT = 3'd2;
    localparam logic [2:0] ACTION_MODIFY   = 3'd3;
    localparam logic [2:0] ACTION_COUNT    = 3'd4;

    logic rule_valid [0:RULE_COUNT-1];

    logic rule_vlan_present_value [0:RULE_COUNT-1];
    logic rule_vlan_present_mask  [0:RULE_COUNT-1];

    logic [11:0] rule_vlan_value [0:RULE_COUNT-1];
    logic [11:0] rule_vlan_mask  [0:RULE_COUNT-1];

    logic [31:0] rule_src_ip_value [0:RULE_COUNT-1];
    logic [31:0] rule_src_ip_mask  [0:RULE_COUNT-1];

    logic [31:0] rule_dst_ip_value [0:RULE_COUNT-1];
    logic [31:0] rule_dst_ip_mask  [0:RULE_COUNT-1];

    logic [7:0] rule_protocol_value [0:RULE_COUNT-1];
    logic [7:0] rule_protocol_mask  [0:RULE_COUNT-1];

    logic [15:0] rule_src_port_value [0:RULE_COUNT-1];
    logic [15:0] rule_src_port_mask  [0:RULE_COUNT-1];

    logic [15:0] rule_dst_port_value [0:RULE_COUNT-1];
    logic [15:0] rule_dst_port_mask  [0:RULE_COUNT-1];

    logic [2:0] rule_action [0:RULE_COUNT-1];
    logic [1:0] rule_queue  [0:RULE_COUNT-1];

    integer i;

    /*
     * Runtime rule storage.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            for (i = 0; i < RULE_COUNT; i = i + 1) begin

                rule_valid[i] <= 1'b0;

                rule_vlan_present_value[i] <= 1'b0;
                rule_vlan_present_mask[i]  <= 1'b0;

                rule_vlan_value[i] <= 12'd0;
                rule_vlan_mask[i]  <= 12'd0;

                rule_src_ip_value[i] <= 32'd0;
                rule_src_ip_mask[i]  <= 32'd0;

                rule_dst_ip_value[i] <= 32'd0;
                rule_dst_ip_mask[i]  <= 32'd0;

                rule_protocol_value[i] <= 8'd0;
                rule_protocol_mask[i]  <= 8'd0;

                rule_src_port_value[i] <= 16'd0;
                rule_src_port_mask[i]  <= 16'd0;

                rule_dst_port_value[i] <= 16'd0;
                rule_dst_port_mask[i]  <= 16'd0;

                rule_action[i] <= ACTION_DROP;
                rule_queue[i]  <= 2'd0;

            end

        end
        else if (cfg_rule_we) begin

            rule_valid[cfg_rule_index] <=
                cfg_rule_valid;

            rule_vlan_present_value[
                cfg_rule_index
            ] <=
                cfg_vlan_present_value;

            rule_vlan_present_mask[
                cfg_rule_index
            ] <=
                cfg_vlan_present_mask;

            rule_vlan_value[
                cfg_rule_index
            ] <=
                cfg_vlan_value;

            rule_vlan_mask[
                cfg_rule_index
            ] <=
                cfg_vlan_mask;

            rule_src_ip_value[
                cfg_rule_index
            ] <=
                cfg_src_ip_value;

            rule_src_ip_mask[
                cfg_rule_index
            ] <=
                cfg_src_ip_mask;

            rule_dst_ip_value[
                cfg_rule_index
            ] <=
                cfg_dst_ip_value;

            rule_dst_ip_mask[
                cfg_rule_index
            ] <=
                cfg_dst_ip_mask;

            rule_protocol_value[
                cfg_rule_index
            ] <=
                cfg_protocol_value;

            rule_protocol_mask[
                cfg_rule_index
            ] <=
                cfg_protocol_mask;

            rule_src_port_value[
                cfg_rule_index
            ] <=
                cfg_src_port_value;

            rule_src_port_mask[
                cfg_rule_index
            ] <=
                cfg_src_port_mask;

            rule_dst_port_value[
                cfg_rule_index
            ] <=
                cfg_dst_port_value;

            rule_dst_port_mask[
                cfg_rule_index
            ] <=
                cfg_dst_port_mask;

            rule_action[
                cfg_rule_index
            ] <=
                cfg_action;

            rule_queue[
                cfg_rule_index
            ] <=
                cfg_queue;

        end

    end

    /*
     * Lightweight deterministic 5-tuple hash.
     *
     * This is a flow-distribution hash, not a cryptographic hash.
     */
    function automatic logic [31:0] make_flow_hash(
        input logic [31:0] sip,
        input logic [31:0] dip,
        input logic [7:0]  proto,
        input logic [15:0] sport,
        input logic [15:0] dport
    );

        logic [31:0] h;

        begin

            h = sip;

            h =
                {h[26:0], h[31:27]} ^
                dip;

            h =
                {h[20:0], h[31:21]} ^
                {sport, dport};

            h =
                {h[24:0], h[31:25]} ^
                {24'd0, proto};

            h = h ^ (h >> 16);
            h = h ^ (h << 7);
            h = h ^ (h >> 11);

            make_flow_hash = h;

        end

    endfunction

    logic       match_found_comb;
    logic [4:0] matched_rule_comb;
    logic [2:0] action_comb;
    logic [1:0] queue_comb;

    integer j;

    /*
     * Lowest rule index has highest priority.
     *
     * Mask semantics:
     *
     *   mask bit = 1 -> compare this bit
     *   mask bit = 0 -> wildcard
     */
    always_comb begin

        match_found_comb = 1'b0;
        matched_rule_comb = 5'd0;

        /*
         * Security-oriented default policy:
         * unmatched packets DROP.
         */
        action_comb = ACTION_DROP;
        queue_comb  = 2'd0;

        for (j = 0; j < RULE_COUNT; j = j + 1) begin

            if (!match_found_comb &&
                rule_valid[j] &&

                (((vlan_present ^
                   rule_vlan_present_value[j]) &
                  rule_vlan_present_mask[j]) == 1'b0) &&

                ((vlan_id &
                  rule_vlan_mask[j]) ==
                 (rule_vlan_value[j] &
                  rule_vlan_mask[j])) &&

                ((src_ipv4 &
                  rule_src_ip_mask[j]) ==
                 (rule_src_ip_value[j] &
                  rule_src_ip_mask[j])) &&

                ((dst_ipv4 &
                  rule_dst_ip_mask[j]) ==
                 (rule_dst_ip_value[j] &
                  rule_dst_ip_mask[j])) &&

                ((ip_protocol &
                  rule_protocol_mask[j]) ==
                 (rule_protocol_value[j] &
                  rule_protocol_mask[j])) &&

                ((src_port &
                  rule_src_port_mask[j]) ==
                 (rule_src_port_value[j] &
                  rule_src_port_mask[j])) &&

                ((dst_port &
                  rule_dst_port_mask[j]) ==
                 (rule_dst_port_value[j] &
                  rule_dst_port_mask[j]))) begin

                match_found_comb =
                    1'b1;

                matched_rule_comb =
                    j[4:0];

                action_comb =
                    rule_action[j];

                queue_comb =
                    rule_queue[j];

            end

        end

    end

    /*
     * One-stage decision pipeline.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            decision_valid <= 1'b0;

            matched      <= 1'b0;
            matched_rule <= 5'd0;

            action   <= ACTION_DROP;
            queue_id <= 2'd0;

            flow_hash <= 32'd0;

        end
        else begin

            decision_valid <=
                metadata_valid;

            if (metadata_valid) begin

                flow_hash <=
                    make_flow_hash(
                        src_ipv4,
                        dst_ipv4,
                        ip_protocol,
                        src_port,
                        dst_port
                    );

                /*
                 * Malformed traffic always drops before
                 * programmable policy is considered.
                 */
                if (malformed) begin

                    matched      <= 1'b0;
                    matched_rule <= 5'd0;

                    action   <= ACTION_DROP;
                    queue_id <= 2'd0;

                end
                else begin

                    matched <=
                        match_found_comb;

                    matched_rule <=
                        matched_rule_comb;

                    action <=
                        action_comb;

                    queue_id <=
                        queue_comb;

                end

            end

        end

    end

endmodule
