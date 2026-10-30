`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Module:
 *   Control / Telemetry Clock-Domain-Crossing Bridge
 *
 * Clock Domains:
 *   Control plane : 100 MHz target
 *   Packet plane  : 125 MHz target
 *
 * Architecture:
 *
 *   CONTROL DOMAIN
 *        |
 *        | bundled command payload
 *        | request / acknowledge toggle
 *        v
 *   DATA DOMAIN
 *
 *   DATA DOMAIN
 *        |
 *        | atomic telemetry snapshot
 *        | request / acknowledge toggle
 *        v
 *   CONTROL DOMAIN
 *
 * Multi-bit payloads are held stable for the complete CDC
 * transaction. They are NOT independently synchronized bit-by-bit.
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module p08_control_telemetry_cdc #(
    parameter integer CMD_WIDTH  = 256,
    parameter integer SNAP_WIDTH = 256
)(
    /*
     * ---------------------------------------------------------
     * CONTROL DOMAIN
     * ---------------------------------------------------------
     */

    input  logic                  ctrl_clk,
    input  logic                  ctrl_aresetn,

    input  logic                  ctrl_cmd_valid,
    output logic                  ctrl_cmd_ready,
    input  logic [CMD_WIDTH-1:0]  ctrl_cmd_payload,

    input  logic                  ctrl_snapshot_req,
    output logic                  ctrl_snapshot_busy,

    output logic                  ctrl_snapshot_valid,
    output logic [SNAP_WIDTH-1:0] ctrl_snapshot_payload,

    /*
     * ---------------------------------------------------------
     * DATA / PACKET DOMAIN
     * ---------------------------------------------------------
     */

    input  logic                  data_clk,
    input  logic                  data_aresetn,

    output logic                  data_cmd_valid,
    output logic [CMD_WIDTH-1:0]  data_cmd_payload,

    input  logic [SNAP_WIDTH-1:0] data_snapshot_payload
);

    /*
     * =========================================================
     * CONTROL -> DATA COMMAND MAILBOX
     * =========================================================
     */

    logic [CMD_WIDTH-1:0] cmd_hold_ctrl;

    logic cmd_req_toggle_ctrl;
    logic cmd_busy_ctrl;

    logic cmd_ack_toggle_data;

    (* ASYNC_REG = "TRUE" *)
    logic cmd_ack_sync1_ctrl;

    (* ASYNC_REG = "TRUE" *)
    logic cmd_ack_sync2_ctrl;

    logic [CMD_WIDTH-1:0] cmd_bus_async;

    assign cmd_bus_async =
        cmd_hold_ctrl;

    assign ctrl_cmd_ready =
        !cmd_busy_ctrl;

    /*
     * Control-domain command launch.
     *
     * Payload remains frozen until the data domain has captured
     * it and returned the acknowledgement toggle.
     */
    always_ff @(posedge ctrl_clk) begin

        if (!ctrl_aresetn) begin

            cmd_hold_ctrl <=
                '0;

            cmd_req_toggle_ctrl <=
                1'b0;

            cmd_busy_ctrl <=
                1'b0;

            cmd_ack_sync1_ctrl <=
                1'b0;

            cmd_ack_sync2_ctrl <=
                1'b0;

        end
        else begin

            cmd_ack_sync1_ctrl <=
                cmd_ack_toggle_data;

            cmd_ack_sync2_ctrl <=
                cmd_ack_sync1_ctrl;

            if (ctrl_cmd_valid &&
                ctrl_cmd_ready) begin

                cmd_hold_ctrl <=
                    ctrl_cmd_payload;

                cmd_req_toggle_ctrl <=
                    ~cmd_req_toggle_ctrl;

                cmd_busy_ctrl <=
                    1'b1;

            end

            if (cmd_busy_ctrl &&
                (cmd_ack_sync2_ctrl ==
                 cmd_req_toggle_ctrl)) begin

                cmd_busy_ctrl <=
                    1'b0;

            end

        end

    end

    /*
     * Synchronize command request into packet domain.
     */
    (* ASYNC_REG = "TRUE" *)
    logic cmd_req_sync1_data;

    (* ASYNC_REG = "TRUE" *)
    logic cmd_req_sync2_data;

    logic cmd_req_seen_data;

    logic cmd_capture_pending;
    logic cmd_pending_toggle;

    always_ff @(posedge data_clk) begin

        if (!data_aresetn) begin

            cmd_req_sync1_data <=
                1'b0;

            cmd_req_sync2_data <=
                1'b0;

            cmd_req_seen_data <=
                1'b0;

            cmd_capture_pending <=
                1'b0;

            cmd_pending_toggle <=
                1'b0;

            cmd_ack_toggle_data <=
                1'b0;

            data_cmd_valid <=
                1'b0;

            data_cmd_payload <=
                '0;

        end
        else begin

            data_cmd_valid <=
                1'b0;

            cmd_req_sync1_data <=
                cmd_req_toggle_ctrl;

            cmd_req_sync2_data <=
                cmd_req_sync1_data;

            /*
             * Request transition detected.
             *
             * Do not capture the bundled bus immediately.
             * Wait an additional data-domain cycle, allowing
             * substantial settling time after the synchronized
             * request transition.
             */
            if (!cmd_capture_pending &&
                (cmd_req_sync2_data !=
                 cmd_req_seen_data)) begin

                cmd_req_seen_data <=
                    cmd_req_sync2_data;

                cmd_pending_toggle <=
                    cmd_req_sync2_data;

                cmd_capture_pending <=
                    1'b1;

            end
            else if (cmd_capture_pending) begin

                data_cmd_payload <=
                    cmd_bus_async;

                data_cmd_valid <=
                    1'b1;

                cmd_ack_toggle_data <=
                    cmd_pending_toggle;

                cmd_capture_pending <=
                    1'b0;

            end

        end

    end

    /*
     * =========================================================
     * DATA -> CONTROL ATOMIC TELEMETRY SNAPSHOT
     * =========================================================
     */

    logic snap_req_toggle_ctrl;
    logic snap_busy_ctrl;

    logic snap_ack_toggle_data;

    (* ASYNC_REG = "TRUE" *)
    logic snap_ack_sync1_ctrl;

    (* ASYNC_REG = "TRUE" *)
    logic snap_ack_sync2_ctrl;

    logic snap_ack_seen_ctrl;

    logic snap_capture_pending_ctrl;

    logic [SNAP_WIDTH-1:0] snap_hold_data;
    logic [SNAP_WIDTH-1:0] snap_bus_async;

    assign snap_bus_async =
        snap_hold_data;

    assign ctrl_snapshot_busy =
        snap_busy_ctrl;

    /*
     * Snapshot request and returned atomic snapshot capture.
     */
    always_ff @(posedge ctrl_clk) begin

        if (!ctrl_aresetn) begin

            snap_req_toggle_ctrl <=
                1'b0;

            snap_busy_ctrl <=
                1'b0;

            snap_ack_sync1_ctrl <=
                1'b0;

            snap_ack_sync2_ctrl <=
                1'b0;

            snap_ack_seen_ctrl <=
                1'b0;

            snap_capture_pending_ctrl <=
                1'b0;

            ctrl_snapshot_valid <=
                1'b0;

            ctrl_snapshot_payload <=
                '0;

        end
        else begin

            ctrl_snapshot_valid <=
                1'b0;

            snap_ack_sync1_ctrl <=
                snap_ack_toggle_data;

            snap_ack_sync2_ctrl <=
                snap_ack_sync1_ctrl;

            if (ctrl_snapshot_req &&
                !snap_busy_ctrl) begin

                snap_req_toggle_ctrl <=
                    ~snap_req_toggle_ctrl;

                snap_busy_ctrl <=
                    1'b1;

            end

            /*
             * Acknowledgement transition means the packet domain
             * has already frozen the complete telemetry vector.
             */
            if (snap_busy_ctrl &&
                !snap_capture_pending_ctrl &&
                (snap_ack_sync2_ctrl !=
                 snap_ack_seen_ctrl)) begin

                snap_ack_seen_ctrl <=
                    snap_ack_sync2_ctrl;

                snap_capture_pending_ctrl <=
                    1'b1;

            end
            else if (snap_capture_pending_ctrl) begin

                ctrl_snapshot_payload <=
                    snap_bus_async;

                ctrl_snapshot_valid <=
                    1'b1;

                snap_busy_ctrl <=
                    1'b0;

                snap_capture_pending_ctrl <=
                    1'b0;

            end

        end

    end

    /*
     * Synchronize snapshot request into packet domain.
     */
    (* ASYNC_REG = "TRUE" *)
    logic snap_req_sync1_data;

    (* ASYNC_REG = "TRUE" *)
    logic snap_req_sync2_data;

    logic snap_req_seen_data;

    always_ff @(posedge data_clk) begin

        if (!data_aresetn) begin

            snap_req_sync1_data <=
                1'b0;

            snap_req_sync2_data <=
                1'b0;

            snap_req_seen_data <=
                1'b0;

            snap_ack_toggle_data <=
                1'b0;

            snap_hold_data <=
                '0;

        end
        else begin

            snap_req_sync1_data <=
                snap_req_toggle_ctrl;

            snap_req_sync2_data <=
                snap_req_sync1_data;

            if (snap_req_sync2_data !=
                snap_req_seen_data) begin

                /*
                 * All telemetry fields are captured on exactly
                 * this packet-domain clock edge.
                 */
                snap_hold_data <=
                    data_snapshot_payload;

                snap_req_seen_data <=
                    snap_req_sync2_data;

                snap_ack_toggle_data <=
                    snap_req_sync2_data;

            end

        end

    end

endmodule
