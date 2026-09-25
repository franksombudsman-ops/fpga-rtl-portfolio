`timescale 1ns/1ps

/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 *
 * MPU6050 motion-frame to AXI4-Stream packetizer.
 *
 * Packet:
 *   W0 = 0x60500001                  header/version
 *   W1 = {Accel X, Accel Y}
 *   W2 = {Accel Z, Temperature}
 *   W3 = {Gyro X, Gyro Y}
 *   W4 = {Gyro Z, 16'h0000}
 *   W5 = sequence number
 *   W6 = 0x5B000000 | sequence[23:0]   TLAST
 */

module mpu6050_axis_packetizer (
    input  wire         aclk,
    input  wire         aresetn,

    input  wire [111:0] motion_frame,
    input  wire         motion_valid,

    output reg  [31:0]  m_axis_tdata,
    output wire [3:0]   m_axis_tkeep,
    output wire         m_axis_tvalid,
    input  wire         m_axis_tready,
    output wire         m_axis_tlast,

    output reg  [31:0]  frame_drop_count,
    output reg          overflow_sticky
);

    reg [111:0] frame_latched;
    reg [31:0]  sequence_number;
    reg [2:0]   word_index;
    reg         active;

    assign m_axis_tkeep  = 4'b1111;
    assign m_axis_tvalid = active;
    assign m_axis_tlast  = active && (word_index == 3'd6);

    always @(*) begin
        case (word_index)

            3'd0:
                m_axis_tdata = 32'h6050_0001;

            3'd1:
                m_axis_tdata = {
                    frame_latched[111:96],
                    frame_latched[95:80]
                };

            3'd2:
                m_axis_tdata = {
                    frame_latched[79:64],
                    frame_latched[63:48]
                };

            3'd3:
                m_axis_tdata = {
                    frame_latched[47:32],
                    frame_latched[31:16]
                };

            3'd4:
                m_axis_tdata = {
                    frame_latched[15:0],
                    16'h0000
                };

            3'd5:
                m_axis_tdata = sequence_number;

            3'd6:
                m_axis_tdata =
                    32'h5B00_0000 |
                    {8'h00, sequence_number[23:0]};

            default:
                m_axis_tdata = 32'h0000_0000;

        endcase
    end

    always @(posedge aclk) begin

        if (!aresetn) begin

            frame_latched    <= 112'd0;
            sequence_number  <= 32'd0;
            word_index       <= 3'd0;
            active           <= 1'b0;

            frame_drop_count <= 32'd0;
            overflow_sticky  <= 1'b0;

        end
        else begin

            /*
             * Producer has no backpressure input.
             * A new frame arriving while a packet is active
             * cannot be accepted.
             */
            if (motion_valid && active) begin
                frame_drop_count <= frame_drop_count + 32'd1;
                overflow_sticky  <= 1'b1;
            end

            if (!active) begin

                if (motion_valid) begin
                    frame_latched <= motion_frame;
                    word_index    <= 3'd0;
                    active        <= 1'b1;
                end

            end
            else if (m_axis_tvalid && m_axis_tready) begin

                if (word_index == 3'd6) begin
                    sequence_number <= sequence_number + 32'd1;
                    word_index      <= 3'd0;
                    active          <= 1'b0;
                end
                else begin
                    word_index <= word_index + 3'd1;
                end

            end

        end
    end

endmodule
