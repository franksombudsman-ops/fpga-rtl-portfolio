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
 * Two-source AXI4-Stream packet arbiter.
 *
 * Arbitration occurs only at packet boundaries.
 * Once a source is granted, ownership is retained until
 * a successful TLAST transfer completes the packet.
 */

module axis_packet_arbiter_2to1 (
    input  wire        aclk,
    input  wire        aresetn,

    // Source 0
    input  wire [31:0] s0_axis_tdata,
    input  wire [3:0]  s0_axis_tkeep,
    input  wire        s0_axis_tvalid,
    output wire        s0_axis_tready,
    input  wire        s0_axis_tlast,

    // Source 1
    input  wire [31:0] s1_axis_tdata,
    input  wire [3:0]  s1_axis_tkeep,
    input  wire        s1_axis_tvalid,
    output wire        s1_axis_tready,
    input  wire        s1_axis_tlast,

    // Shared output
    output reg  [31:0] m_axis_tdata,
    output reg  [3:0]  m_axis_tkeep,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast
);

    reg grant_active;
    reg grant_select;
    reg last_grant;

    wire selected_valid;
    wire selected_last;
    wire transfer;

    assign selected_valid =
        grant_select ? s1_axis_tvalid : s0_axis_tvalid;

    assign selected_last =
        grant_select ? s1_axis_tlast : s0_axis_tlast;

    assign transfer =
        grant_active &&
        selected_valid &&
        m_axis_tready;

    assign s0_axis_tready =
        grant_active &&
        !grant_select &&
        m_axis_tready;

    assign s1_axis_tready =
        grant_active &&
        grant_select &&
        m_axis_tready;


    always @(*) begin

        m_axis_tdata  = 32'd0;
        m_axis_tkeep  = 4'd0;
        m_axis_tvalid = 1'b0;
        m_axis_tlast  = 1'b0;

        if (grant_active) begin

            if (!grant_select) begin
                m_axis_tdata  = s0_axis_tdata;
                m_axis_tkeep  = s0_axis_tkeep;
                m_axis_tvalid = s0_axis_tvalid;
                m_axis_tlast  = s0_axis_tlast;
            end
            else begin
                m_axis_tdata  = s1_axis_tdata;
                m_axis_tkeep  = s1_axis_tkeep;
                m_axis_tvalid = s1_axis_tvalid;
                m_axis_tlast  = s1_axis_tlast;
            end

        end

    end


    always @(posedge aclk) begin

        if (!aresetn) begin

            grant_active <= 1'b0;
            grant_select <= 1'b0;
            last_grant   <= 1'b1;

        end
        else begin

            /*
             * Acquire a source only when no packet currently
             * owns the output.
             *
             * If both sources are valid, alternate priority
             * using the previous completed grant.
             */
            if (!grant_active) begin

                if (s0_axis_tvalid && s1_axis_tvalid) begin

                    grant_select <= !last_grant;
                    grant_active <= 1'b1;

                end
                else if (s0_axis_tvalid) begin

                    grant_select <= 1'b0;
                    grant_active <= 1'b1;

                end
                else if (s1_axis_tvalid) begin

                    grant_select <= 1'b1;
                    grant_active <= 1'b1;

                end

            end
            else if (transfer && selected_last) begin

                last_grant   <= grant_select;
                grant_active <= 1'b0;

            end

        end
    end

endmodule
