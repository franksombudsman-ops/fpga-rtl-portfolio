`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Module:
 *   Dual-Bank Packet Buffer + Match/Action Synchronizer
 *
 * Purpose:
 *   Hold complete packets until the corresponding hardware policy
 *   decision becomes authoritative.
 *
 *   DROP packets are discarded without appearing at the output.
 *   FORWARD / REDIRECT / MODIFY / COUNT packets are replayed through
 *   the AXI4-Stream output with their action and queue metadata.
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module p08_packet_action_buffer #(
    parameter integer MAX_PACKET_BEATS = 256
)(
    input  logic         clk,
    input  logic         aresetn,

    /*
     * Packet input.
     */
    input  logic [63:0]  s_axis_tdata,
    input  logic [7:0]   s_axis_tkeep,
    input  logic         s_axis_tvalid,
    output logic         s_axis_tready,
    input  logic         s_axis_tlast,

    /*
     * Ordered decision input from the match/action engine.
     */
    input  logic         decision_valid,
    input  logic [2:0]   decision_action,
    input  logic [1:0]   decision_queue,

    /*
     * Packet output.
     */
    output logic [63:0]  m_axis_tdata,
    output logic [7:0]   m_axis_tkeep,
    output logic         m_axis_tvalid,
    input  logic         m_axis_tready,
    output logic         m_axis_tlast,

    /*
     * Disposition accompanying every forwarded output packet.
     */
    output logic [2:0]   m_packet_action,
    output logic [1:0]   m_packet_queue,

    /*
     * One-cycle disposition events.
     */
    output logic         forward_event,
    output logic         drop_event,
    output logic         redirect_event,
    output logic         modify_event,
    output logic         count_event,

    /*
     * Diagnostics.
     */
    output logic [31:0]  packets_accepted,
    output logic [31:0]  packets_forwarded,
    output logic [31:0]  packets_dropped
);

    localparam logic [2:0] ACTION_FORWARD  = 3'd0;
    localparam logic [2:0] ACTION_DROP     = 3'd1;
    localparam logic [2:0] ACTION_REDIRECT = 3'd2;
    localparam logic [2:0] ACTION_MODIFY   = 3'd3;
    localparam logic [2:0] ACTION_COUNT    = 3'd4;

    localparam logic [1:0] BANK_FREE = 2'd0;
    localparam logic [1:0] BANK_FILL = 2'd1;
    localparam logic [1:0] BANK_WAIT = 2'd2;
    localparam logic [1:0] BANK_READY = 2'd3;

    logic [63:0] bank_data [0:1][0:MAX_PACKET_BEATS-1];
    logic [7:0]  bank_keep [0:1][0:MAX_PACKET_BEATS-1];
    logic        bank_last [0:1][0:MAX_PACKET_BEATS-1];

    logic [1:0] bank_state [0:1];

    logic [2:0] bank_action [0:1];
    logic [1:0] bank_queue  [0:1];

    /*
     * Capture state.
     */
    logic       capture_active;
    logic       capture_bank;
    logic [$clog2(MAX_PACKET_BEATS):0] capture_index;

    /*
     * Queue of completed packets waiting for their policy decision.
     * Depth two because there are two packet banks.
     */
    logic wait_fifo [0:1];
    logic wait_rd;
    logic wait_wr;
    logic [1:0] wait_count;

    /*
     * Queue of packets approved for output.
     */
    logic out_fifo [0:1];
    logic out_rd;
    logic out_wr;
    logic [1:0] out_count;

    /*
     * Output replay state.
     */
    logic       output_active;
    logic       output_bank;
    logic [$clog2(MAX_PACKET_BEATS):0] output_index;

    logic free_valid;
    logic free_bank;

    logic wait_push;
    logic wait_pop;

    logic out_push;
    logic out_pop;

    logic completed_bank;
    logic decision_bank;

    /*
     * A packet bank is selected only when FREE.
     */
    always_comb begin

        free_valid = 1'b0;
        free_bank  = 1'b0;

        if (bank_state[0] == BANK_FREE) begin

            free_valid = 1'b1;
            free_bank  = 1'b0;

        end
        else if (bank_state[1] == BANK_FREE) begin

            free_valid = 1'b1;
            free_bank  = 1'b1;

        end

    end

    /*
     * Ingress can continue while one bank is being replayed,
     * provided the other bank is free.
     */
    always_comb begin

        if (!aresetn) begin

            s_axis_tready = 1'b0;

        end
        else if (capture_active) begin

            s_axis_tready =
                (capture_index <
                 MAX_PACKET_BEATS);

        end
        else begin

            s_axis_tready =
                free_valid;

        end

    end

    /*
     * Output stream is driven directly from the selected replay bank.
     */
    always_comb begin

        m_axis_tvalid = output_active;

        m_axis_tdata = 64'd0;
        m_axis_tkeep = 8'd0;
        m_axis_tlast = 1'b0;

        m_packet_action = ACTION_DROP;
        m_packet_queue  = 2'd0;

        if (output_active) begin

            m_axis_tdata =
                bank_data[
                    output_bank
                ][
                    output_index
                ];

            m_axis_tkeep =
                bank_keep[
                    output_bank
                ][
                    output_index
                ];

            m_axis_tlast =
                bank_last[
                    output_bank
                ][
                    output_index
                ];

            m_packet_action =
                bank_action[
                    output_bank
                ];

            m_packet_queue =
                bank_queue[
                    output_bank
                ];

        end

    end

    /*
     * Main control.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            bank_state[0] <= BANK_FREE;
            bank_state[1] <= BANK_FREE;

            bank_action[0] <= ACTION_DROP;
            bank_action[1] <= ACTION_DROP;

            bank_queue[0] <= 2'd0;
            bank_queue[1] <= 2'd0;

            capture_active <= 1'b0;
            capture_bank   <= 1'b0;
            capture_index  <= '0;

            wait_rd    <= 1'b0;
            wait_wr    <= 1'b0;
            wait_count <= 2'd0;

            out_rd    <= 1'b0;
            out_wr    <= 1'b0;
            out_count <= 2'd0;

            output_active <= 1'b0;
            output_bank   <= 1'b0;
            output_index  <= '0;

            forward_event  <= 1'b0;
            drop_event     <= 1'b0;
            redirect_event <= 1'b0;
            modify_event   <= 1'b0;
            count_event    <= 1'b0;

            packets_accepted  <= 32'd0;
            packets_forwarded <= 32'd0;
            packets_dropped   <= 32'd0;

        end
        else begin

            forward_event  <= 1'b0;
            drop_event     <= 1'b0;
            redirect_event <= 1'b0;
            modify_event   <= 1'b0;
            count_event    <= 1'b0;

            wait_push = 1'b0;
            wait_pop  = 1'b0;

            out_push = 1'b0;
            out_pop  = 1'b0;

            completed_bank = 1'b0;
            decision_bank  = 1'b0;

            /*
             * -------------------------------------------------
             * PACKET CAPTURE
             * -------------------------------------------------
             */
            if (s_axis_tvalid &&
                s_axis_tready) begin

                if (!capture_active) begin

                    bank_state[
                        free_bank
                    ] <= BANK_FILL;

                    bank_data[
                        free_bank
                    ][0] <=
                        s_axis_tdata;

                    bank_keep[
                        free_bank
                    ][0] <=
                        s_axis_tkeep;

                    bank_last[
                        free_bank
                    ][0] <=
                        s_axis_tlast;

                    if (s_axis_tlast) begin

                        completed_bank =
                            free_bank;

                        bank_state[
                            free_bank
                        ] <= BANK_WAIT;

                        packets_accepted <=
                            packets_accepted +
                            1'b1;

                        wait_fifo[
                            wait_wr
                        ] <=
                            free_bank;

                        wait_wr <=
                            wait_wr + 1'b1;

                        wait_push =
                            1'b1;

                        capture_active <=
                            1'b0;

                        capture_index <=
                            '0;

                    end
                    else begin

                        capture_active <=
                            1'b1;

                        capture_bank <=
                            free_bank;

                        capture_index <=
                            1;

                    end

                end
                else begin

                    bank_data[
                        capture_bank
                    ][
                        capture_index
                    ] <=
                        s_axis_tdata;

                    bank_keep[
                        capture_bank
                    ][
                        capture_index
                    ] <=
                        s_axis_tkeep;

                    bank_last[
                        capture_bank
                    ][
                        capture_index
                    ] <=
                        s_axis_tlast;

                    if (s_axis_tlast) begin

                        completed_bank =
                            capture_bank;

                        bank_state[
                            capture_bank
                        ] <= BANK_WAIT;

                        packets_accepted <=
                            packets_accepted +
                            1'b1;

                        wait_fifo[
                            wait_wr
                        ] <=
                            capture_bank;

                        wait_wr <=
                            wait_wr + 1'b1;

                        wait_push =
                            1'b1;

                        capture_active <=
                            1'b0;

                        capture_index <=
                            '0;

                    end
                    else begin

                        capture_index <=
                            capture_index +
                            1'b1;

                    end

                end

            end

            /*
             * -------------------------------------------------
             * DECISION ASSOCIATION
             * -------------------------------------------------
             *
             * Decisions are consumed in the same packet order in
             * which packets completed capture.
             */
            if (decision_valid &&
                (wait_count != 0)) begin

                decision_bank =
                    wait_fifo[
                        wait_rd
                    ];

                wait_rd <=
                    wait_rd + 1'b1;

                wait_pop =
                    1'b1;

                bank_action[
                    decision_bank
                ] <=
                    decision_action;

                bank_queue[
                    decision_bank
                ] <=
                    decision_queue;

                case (decision_action)

                    ACTION_DROP: begin

                        bank_state[
                            decision_bank
                        ] <= BANK_FREE;

                        drop_event <=
                            1'b1;

                        packets_dropped <=
                            packets_dropped +
                            1'b1;

                    end

                    ACTION_REDIRECT: begin

                        bank_state[
                            decision_bank
                        ] <= BANK_READY;

                        redirect_event <=
                            1'b1;

                        out_fifo[
                            out_wr
                        ] <=
                            decision_bank;

                        out_wr <=
                            out_wr + 1'b1;

                        out_push =
                            1'b1;

                    end

                    ACTION_MODIFY: begin

                        /*
                         * 08E proves synchronization and action
                         * transport. Actual byte modification is
                         * introduced in the packet editor gate.
                         */
                        bank_state[
                            decision_bank
                        ] <= BANK_READY;

                        modify_event <=
                            1'b1;

                        out_fifo[
                            out_wr
                        ] <=
                            decision_bank;

                        out_wr <=
                            out_wr + 1'b1;

                        out_push =
                            1'b1;

                    end

                    ACTION_COUNT: begin

                        bank_state[
                            decision_bank
                        ] <= BANK_READY;

                        count_event <=
                            1'b1;

                        out_fifo[
                            out_wr
                        ] <=
                            decision_bank;

                        out_wr <=
                            out_wr + 1'b1;

                        out_push =
                            1'b1;

                    end

                    default: begin

                        bank_state[
                            decision_bank
                        ] <= BANK_READY;

                        forward_event <=
                            1'b1;

                        out_fifo[
                            out_wr
                        ] <=
                            decision_bank;

                        out_wr <=
                            out_wr + 1'b1;

                        out_push =
                            1'b1;

                    end

                endcase

            end

            /*
             * -------------------------------------------------
             * START OUTPUT REPLAY
             * -------------------------------------------------
             */
            if (!output_active &&
                (out_count != 0)) begin

                output_bank <=
                    out_fifo[
                        out_rd
                    ];

                output_index <=
                    '0;

                output_active <=
                    1'b1;

                out_rd <=
                    out_rd + 1'b1;

                out_pop =
                    1'b1;

            end

            /*
             * -------------------------------------------------
             * OUTPUT REPLAY
             * -------------------------------------------------
             */
            if (output_active &&
                m_axis_tvalid &&
                m_axis_tready) begin

                if (m_axis_tlast) begin

                    bank_state[
                        output_bank
                    ] <= BANK_FREE;

                    output_active <=
                        1'b0;

                    output_index <=
                        '0;

                    packets_forwarded <=
                        packets_forwarded +
                        1'b1;

                end
                else begin

                    output_index <=
                        output_index +
                        1'b1;

                end

            end

            /*
             * -------------------------------------------------
             * FIFO COUNTS
             * -------------------------------------------------
             */
            case ({
                wait_push,
                wait_pop
            })

                2'b10:
                    wait_count <=
                        wait_count + 1'b1;

                2'b01:
                    wait_count <=
                        wait_count - 1'b1;

                default:
                    wait_count <=
                        wait_count;

            endcase

            case ({
                out_push,
                out_pop
            })

                2'b10:
                    out_count <=
                        out_count + 1'b1;

                2'b01:
                    out_count <=
                        out_count - 1'b1;

                default:
                    out_count <=
                        out_count;

            endcase

        end

    end

endmodule
