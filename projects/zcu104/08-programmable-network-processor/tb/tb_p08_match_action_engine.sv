`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Verification:
 *   Programmable 5-Tuple Match / Action Engine
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module tb_p08_match_action_engine;

    localparam logic [2:0] ACTION_FORWARD  = 3'd0;
    localparam logic [2:0] ACTION_DROP     = 3'd1;
    localparam logic [2:0] ACTION_REDIRECT = 3'd2;
    localparam logic [2:0] ACTION_MODIFY   = 3'd3;
    localparam logic [2:0] ACTION_COUNT    = 3'd4;

    logic clk = 1'b0;

    always #4 clk = ~clk;     // 125 MHz

    logic aresetn = 1'b0;

    logic metadata_valid;
    logic malformed;

    logic vlan_present;
    logic [11:0] vlan_id;

    logic [31:0] src_ipv4;
    logic [31:0] dst_ipv4;
    logic [7:0]  ip_protocol;
    logic [15:0] src_port;
    logic [15:0] dst_port;

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
    logic [1:0] cfg_queue;

    logic decision_valid;
    logic matched;
    logic [4:0] matched_rule;

    logic [2:0] action;
    logic [1:0] queue_id;

    logic [31:0] flow_hash;

    p08_match_action_engine dut (

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
        .cfg_queue               (cfg_queue),

        .decision_valid          (decision_valid),
        .matched                 (matched),
        .matched_rule            (matched_rule),

        .action                  (action),
        .queue_id                (queue_id),

        .flow_hash               (flow_hash)
    );

    integer tests_passed = 0;

    task automatic clear_cfg;

        begin

            cfg_rule_we = 1'b0;
            cfg_rule_index = 5'd0;
            cfg_rule_valid = 1'b0;

            cfg_vlan_present_value = 1'b0;
            cfg_vlan_present_mask  = 1'b0;

            cfg_vlan_value = 12'd0;
            cfg_vlan_mask  = 12'd0;

            cfg_src_ip_value = 32'd0;
            cfg_src_ip_mask  = 32'd0;

            cfg_dst_ip_value = 32'd0;
            cfg_dst_ip_mask  = 32'd0;

            cfg_protocol_value = 8'd0;
            cfg_protocol_mask  = 8'd0;

            cfg_src_port_value = 16'd0;
            cfg_src_port_mask  = 16'd0;

            cfg_dst_port_value = 16'd0;
            cfg_dst_port_mask  = 16'd0;

            cfg_action = ACTION_DROP;
            cfg_queue  = 2'd0;

        end

    endtask

    task automatic program_rule(
        input integer idx,
        input logic valid,

        input logic vp_value,
        input logic vp_mask,

        input logic [11:0] vid_value,
        input logic [11:0] vid_mask,

        input logic [31:0] sip_value,
        input logic [31:0] sip_mask,

        input logic [31:0] dip_value,
        input logic [31:0] dip_mask,

        input logic [7:0] proto_value,
        input logic [7:0] proto_mask,

        input logic [15:0] sport_value,
        input logic [15:0] sport_mask,

        input logic [15:0] dport_value,
        input logic [15:0] dport_mask,

        input logic [2:0] rule_action_value,
        input logic [1:0] rule_queue_value
    );

        begin

            @(negedge clk);

            cfg_rule_we =
                1'b1;

            cfg_rule_index =
                idx;

            cfg_rule_valid =
                valid;

            cfg_vlan_present_value =
                vp_value;

            cfg_vlan_present_mask =
                vp_mask;

            cfg_vlan_value =
                vid_value;

            cfg_vlan_mask =
                vid_mask;

            cfg_src_ip_value =
                sip_value;

            cfg_src_ip_mask =
                sip_mask;

            cfg_dst_ip_value =
                dip_value;

            cfg_dst_ip_mask =
                dip_mask;

            cfg_protocol_value =
                proto_value;

            cfg_protocol_mask =
                proto_mask;

            cfg_src_port_value =
                sport_value;

            cfg_src_port_mask =
                sport_mask;

            cfg_dst_port_value =
                dport_value;

            cfg_dst_port_mask =
                dport_mask;

            cfg_action =
                rule_action_value;

            cfg_queue =
                rule_queue_value;

            @(posedge clk);
            @(negedge clk);

            clear_cfg();

        end

    endtask

    logic [31:0] last_hash;

    task automatic test_packet(
        input string name,

        input logic bad,

        input logic vp,
        input logic [11:0] vid,

        input logic [31:0] sip,
        input logic [31:0] dip,

        input logic [7:0] proto,

        input logic [15:0] sport,
        input logic [15:0] dport,

        input logic exp_match,
        input logic [4:0] exp_rule,

        input logic [2:0] exp_action,
        input logic [1:0] exp_queue
    );

        begin

            @(negedge clk);

            malformed =
                bad;

            vlan_present =
                vp;

            vlan_id =
                vid;

            src_ipv4 =
                sip;

            dst_ipv4 =
                dip;

            ip_protocol =
                proto;

            src_port =
                sport;

            dst_port =
                dport;

            metadata_valid =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            metadata_valid =
                1'b0;

            wait (
                decision_valid === 1'b1
            );

            #1;

            if (matched !== exp_match ||
                action !== exp_action ||
                queue_id !== exp_queue ||
                (exp_match &&
                 matched_rule !== exp_rule)) begin

                $display(
                    "FAIL: %s",
                    name
                );

                $display(
                    " match=%0d rule=%0d action=%0d queue=%0d hash=%08x",
                    matched,
                    matched_rule,
                    action,
                    queue_id,
                    flow_hash
                );

                $fatal;

            end

            last_hash =
                flow_hash;

            tests_passed =
                tests_passed + 1;

            $display(
                "TEST %-28s : PASS  match=%0d rule=%0d action=%0d queue=%0d hash=%08x",
                name,
                matched,
                matched_rule,
                action,
                queue_id,
                flow_hash
            );

        end

    endtask

    logic [31:0] hash_a;
    logic [31:0] hash_b;
    logic [31:0] hash_c;

    initial begin

        metadata_valid = 1'b0;
        malformed      = 1'b0;

        vlan_present = 1'b0;
        vlan_id      = 12'd0;

        src_ipv4    = 32'd0;
        dst_ipv4    = 32'd0;
        ip_protocol = 8'd0;
        src_port    = 16'd0;
        dst_port    = 16'd0;

        clear_cfg();

        repeat (10)
            @(posedge clk);

        aresetn = 1'b1;

        repeat (4)
            @(posedge clk);

        $display("");
        $display(
            "===== PROGRAMMING 32-ENTRY RULE ENGINE ====="
        );

        /*
         * RULE 0
         *
         * Exact source 10.0.0.50 -> DROP
         */
        program_rule(
            0, 1'b1,
            1'b0, 1'b0,
            12'd0, 12'd0,
            32'h0A000032, 32'hFFFFFFFF,
            32'd0, 32'd0,
            8'd0, 8'd0,
            16'd0, 16'd0,
            16'd0, 16'd0,
            ACTION_DROP, 2'd0
        );

        /*
         * RULE 1
         *
         * UDP destination 5000 -> FORWARD
         */
        program_rule(
            1, 1'b1,
            1'b0, 1'b0,
            12'd0, 12'd0,
            32'd0, 32'd0,
            32'd0, 32'd0,
            8'd17, 8'hFF,
            16'd0, 16'd0,
            16'd5000, 16'hFFFF,
            ACTION_FORWARD, 2'd0
        );

        /*
         * RULE 2
         *
         * UDP destination 8000 -> REDIRECT queue 2
         */
        program_rule(
            2, 1'b1,
            1'b0, 1'b0,
            12'd0, 12'd0,
            32'd0, 32'd0,
            32'd0, 32'd0,
            8'd17, 8'hFF,
            16'd0, 16'd0,
            16'd8000, 16'hFFFF,
            ACTION_REDIRECT, 2'd2
        );

        /*
         * RULE 3
         *
         * 192.168.1.0/24 -> MODIFY, queue 1
         */
        program_rule(
            3, 1'b1,
            1'b0, 1'b0,
            12'd0, 12'd0,
            32'hC0A80100, 32'hFFFFFF00,
            32'd0, 32'd0,
            8'd0, 8'd0,
            16'd0, 16'd0,
            16'd0, 16'd0,
            ACTION_MODIFY, 2'd1
        );

        /*
         * RULE 4
         *
         * VLAN 100 + UDP destination 9000 -> COUNT
         */
        program_rule(
            4, 1'b1,
            1'b1, 1'b1,
            12'd100, 12'hFFF,
            32'd0, 32'd0,
            32'd0, 32'd0,
            8'd17, 8'hFF,
            16'd0, 16'd0,
            16'd9000, 16'hFFFF,
            ACTION_COUNT, 2'd0
        );

        /*
         * RULE 5
         *
         * TCP destination 443 -> FORWARD queue 3
         */
        program_rule(
            5, 1'b1,
            1'b0, 1'b0,
            12'd0, 12'd0,
            32'd0, 32'd0,
            32'd0, 32'd0,
            8'd6, 8'hFF,
            16'd0, 16'd0,
            16'd443, 16'hFFFF,
            ACTION_FORWARD, 2'd3
        );

        $display(
            "RULE PROGRAMMING: PASS"
        );

        /*
         * -----------------------------------------------------
         * 1. PRIORITY
         *
         * Matches rule 0 and rule 1.
         * Lowest index must win.
         * -----------------------------------------------------
         */
        test_packet(
            "PRIORITY_DROP",
            1'b0,
            1'b0, 12'd0,
            32'h0A000032,
            32'hC0A80101,
            8'd17,
            16'd1234,
            16'd5000,
            1'b1, 5'd0,
            ACTION_DROP, 2'd0
        );

        /*
         * 2. UDP 5000 forward.
         */
        test_packet(
            "UDP_5000_FORWARD",
            1'b0,
            1'b0, 12'd0,
            32'h0A000001,
            32'hC0A80101,
            8'd17,
            16'd1234,
            16'd5000,
            1'b1, 5'd1,
            ACTION_FORWARD, 2'd0
        );

        hash_a = last_hash;

        /*
         * 3. Same 5-tuple -> identical hash.
         */
        test_packet(
            "HASH_REPEAT",
            1'b0,
            1'b0, 12'd0,
            32'h0A000001,
            32'hC0A80101,
            8'd17,
            16'd1234,
            16'd5000,
            1'b1, 5'd1,
            ACTION_FORWARD, 2'd0
        );

        hash_b = last_hash;

        if (hash_a !== hash_b) begin

            $display(
                "FAIL: identical 5-tuple produced different hashes"
            );

            $fatal;

        end

        /*
         * 4. Redirect.
         */
        test_packet(
            "UDP_8000_REDIRECT",
            1'b0,
            1'b0, 12'd0,
            32'h0A000001,
            32'hC0A80101,
            8'd17,
            16'd1234,
            16'd8000,
            1'b1, 5'd2,
            ACTION_REDIRECT, 2'd2
        );

        hash_c = last_hash;

        if (hash_a === hash_c) begin

            $display(
                "FAIL: changed 5-tuple did not alter flow hash"
            );

            $fatal;

        end

        $display(
            "5-TUPLE HASH STABILITY/SENSITIVITY: PASS"
        );

        /*
         * 5. CIDR-style source subnet mask.
         */
        test_packet(
            "SUBNET_MODIFY",
            1'b0,
            1'b0, 12'd0,
            32'hC0A8017B,
            32'h0A010101,
            8'd17,
            16'd2222,
            16'd3333,
            1'b1, 5'd3,
            ACTION_MODIFY, 2'd1
        );

        /*
         * 6. VLAN-aware match.
         */
        test_packet(
            "VLAN100_COUNT",
            1'b0,
            1'b1, 12'd100,
            32'h0A030301,
            32'h0A030302,
            8'd17,
            16'd4000,
            16'd9000,
            1'b1, 5'd4,
            ACTION_COUNT, 2'd0
        );

        /*
         * 7. TCP rule.
         */
        test_packet(
            "TCP443_FORWARD",
            1'b0,
            1'b0, 12'd0,
            32'h0A040401,
            32'h0A040402,
            8'd6,
            16'd55000,
            16'd443,
            1'b1, 5'd5,
            ACTION_FORWARD, 2'd3
        );

        /*
         * 8. No rule -> default DROP.
         */
        test_packet(
            "DEFAULT_DROP",
            1'b0,
            1'b0, 12'd0,
            32'hAC100001,
            32'hAC100002,
            8'd17,
            16'd1111,
            16'd2222,
            1'b0, 5'd0,
            ACTION_DROP, 2'd0
        );

        /*
         * 9. Malformed packet overrides policy.
         */
        test_packet(
            "MALFORMED_DROP",
            1'b1,
            1'b0, 12'd0,
            32'h0A000001,
            32'hC0A80101,
            8'd17,
            16'd1234,
            16'd5000,
            1'b0, 5'd0,
            ACTION_DROP, 2'd0
        );

        /*
         * -----------------------------------------------------
         * Runtime update.
         *
         * Rewrite rule 1 from FORWARD to DROP.
         * No reset. No RTL rebuild.
         * -----------------------------------------------------
         */

        program_rule(
            1, 1'b1,
            1'b0, 1'b0,
            12'd0, 12'd0,
            32'd0, 32'd0,
            32'd0, 32'd0,
            8'd17, 8'hFF,
            16'd0, 16'd0,
            16'd5000, 16'hFFFF,
            ACTION_DROP, 2'd0
        );

        /*
         * 10. Same packet now drops.
         */
        test_packet(
            "RUNTIME_RULE_UPDATE",
            1'b0,
            1'b0, 12'd0,
            32'h0A000001,
            32'hC0A80101,
            8'd17,
            16'd1234,
            16'd5000,
            1'b1, 5'd1,
            ACTION_DROP, 2'd0
        );

        if (tests_passed != 10) begin

            $display(
                "FAIL: tests_passed=%0d expected=10",
                tests_passed
            );

            $fatal;

        end

        $display("");
        $display(
            "============================================"
        );
        $display(
            " PROJECT08 08D MATCH/ACTION ENGINE: PASS"
        );
        $display(
            "============================================"
        );
        $display(
            " Rule entries             : 32"
        );
        $display(
            " 5-tuple hash             : PASS"
        );
        $display(
            " Exact matching           : PASS"
        );
        $display(
            " Masked subnet matching   : PASS"
        );
        $display(
            " VLAN matching            : PASS"
        );
        $display(
            " Rule priority            : PASS"
        );
        $display(
            " FORWARD action           : PASS"
        );
        $display(
            " DROP action              : PASS"
        );
        $display(
            " REDIRECT action          : PASS"
        );
        $display(
            " MODIFY action            : PASS"
        );
        $display(
            " COUNT action             : PASS"
        );
        $display(
            " Default-drop policy      : PASS"
        );
        $display(
            " Malformed override       : PASS"
        );
        $display(
            " Runtime rule update      : PASS"
        );
        $display(
            " Decision tests           : %0d",
            tests_passed
        );
        $display(
            "============================================"
        );

        $finish;

    end

    initial begin

        #5_000_000;

        $display(
            "FAIL: Project08 08D simulation timeout"
        );

        $fatal;

    end

endmodule
