`timescale 1ns/1ps

/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 * Pmod AD1 to AXI4-Stream packetizer.
 *
 * A new ADC sample is accepted only while the packetizer is idle.
 * If a sample arrives while an existing packet is still active,
 * the sample cannot be accepted and is recorded as a dropped sample.
 */

module ad1_axis_packetizer (
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [11:0] sample_a,
    input  wire [11:0] sample_b,
    input  wire        sample_valid,

    output reg  [31:0] m_axis_tdata,
    output wire [3:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast,

    output reg  [31:0] sample_drop_count,
    output reg         overflow_sticky
);

    reg [11:0] sample_a_latched;
    reg [11:0] sample_b_latched;

    reg [31:0] sequence_number;
    reg [1:0]  word_index;
    reg        active;

    assign m_axis_tkeep  = 4'b1111;
    assign m_axis_tvalid = active;
    assign m_axis_tlast  = active && (word_index == 2'd3);

    always @(*) begin
        case (word_index)

            2'd0:
                m_axis_tdata = 32'hAD10_0001;

            2'd1:
                m_axis_tdata = {
                    8'h00,
                    sample_a_latched,
                    sample_b_latched
                };

            2'd2:
                m_axis_tdata = sequence_number;

            2'd3:
                m_axis_tdata =
                    32'h5A00_0000 |
                    {8'h00, sequence_number[23:0]};

            default:
                m_axis_tdata = 32'h0000_0000;

        endcase
    end

    always @(posedge aclk) begin

        if (!aresetn) begin

            sample_a_latched <= 12'd0;
            sample_b_latched <= 12'd0;

            sequence_number  <= 32'd0;
            word_index       <= 2'd0;
            active           <= 1'b0;

            sample_drop_count <= 32'd0;
            overflow_sticky   <= 1'b0;

        end
        else begin

            /*
             * A sample arriving while active cannot be accepted.
             * Count the loss and permanently record that an
             * overflow/drop condition has occurred.
             */
            if (sample_valid && active) begin
                sample_drop_count <= sample_drop_count + 32'd1;
                overflow_sticky   <= 1'b1;
            end

            /*
             * Idle packetizer:
             * capture the next ADC sample and start a packet.
             */
            if (!active) begin

                if (sample_valid) begin

                    sample_a_latched <= sample_a;
                    sample_b_latched <= sample_b;

                    word_index <= 2'd0;
                    active     <= 1'b1;

                end

            end

            /*
             * Active packet:
             * advance only when AXI performs a real transfer.
             */
            else if (m_axis_tvalid && m_axis_tready) begin

                if (word_index == 2'd3) begin

                    sequence_number <= sequence_number + 32'd1;
                    word_index      <= 2'd0;
                    active          <= 1'b0;

                end
                else begin

                    word_index <= word_index + 2'd1;

                end

            end

        end
    end

endmodule
