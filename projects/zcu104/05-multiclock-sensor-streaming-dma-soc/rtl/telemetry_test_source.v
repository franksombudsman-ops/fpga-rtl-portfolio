/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 */

module telemetry_test_source (
    input  wire        aclk,
    input  wire        aresetn,
    input  wire        enable,

    output reg  [31:0] m_axis_tdata,
    output wire [3:0]  m_axis_tkeep,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tlast
);

    reg [1:0]  word_index;
    reg [31:0] sequence_number;
    reg [31:0] timestamp_counter;
    reg [31:0] packet_timestamp;
    reg        active;

    assign m_axis_tkeep  = 4'b1111;
    assign m_axis_tvalid = active;
    assign m_axis_tlast  = active && (word_index == 2'd3);

    always @(*) begin
        case (word_index)
            2'd0: m_axis_tdata = 32'hA500_0001;
            2'd1: m_axis_tdata = sequence_number;
            2'd2: m_axis_tdata = packet_timestamp;
            2'd3: m_axis_tdata = 32'h5A00_0000 |
                                  {8'h00, sequence_number[23:0]};
            default: m_axis_tdata = 32'h0000_0000;
        endcase
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            word_index        <= 2'd0;
            sequence_number   <= 32'd0;
            timestamp_counter <= 32'd0;
            packet_timestamp  <= 32'd0;
            active            <= 1'b0;
        end else begin
            timestamp_counter <= timestamp_counter + 1'b1;

            if (!active) begin
                if (enable) begin
                    active           <= 1'b1;
                    word_index       <= 2'd0;
                    packet_timestamp <= timestamp_counter;
                end
            end else if (m_axis_tvalid && m_axis_tready) begin
                if (word_index == 2'd3) begin
                    sequence_number <= sequence_number + 1'b1;

                    if (enable) begin
                        word_index       <= 2'd0;
                        packet_timestamp <= timestamp_counter;
                        active           <= 1'b1;
                    end else begin
                        word_index <= 2'd0;
                        active     <= 1'b0;
                    end
                end else begin
                    word_index <= word_index + 1'b1;
                end
            end
        end
    end

endmodule
