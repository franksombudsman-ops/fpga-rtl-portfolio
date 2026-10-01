`timescale 1ns/1ps

// ============================================================================
// Project 06 - Streaming DSP Accelerator SoC
// Complete compute accelerator
//
// Author: Frank Ouma
//
// AXI input
//    |
//    v
// FIR32
//    |
//    v
// ENERGY64
//    |
//    v
// EVENT DETECTOR
//    |
//    v
// 64-bit AXI result
// ============================================================================

module dsp_accelerator_full (

    input  logic        aclk,
    input  logic        aresetn,

    input  logic [15:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output logic [63:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);

    logic [63:0] core_tdata;
    logic        core_tvalid;
    logic        core_tready;
    logic        core_tlast;

    dsp_accelerator_core u_compute_core (

        .aclk          (aclk),
        .aresetn       (aresetn),

        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),

        .m_axis_tdata  (core_tdata),
        .m_axis_tvalid (core_tvalid),
        .m_axis_tready (core_tready),
        .m_axis_tlast  (core_tlast)
    );

    energy_event_axis u_event (

        .aclk          (aclk),
        .aresetn       (aresetn),

        .s_axis_tdata  (core_tdata),
        .s_axis_tvalid (core_tvalid),
        .s_axis_tready (core_tready),
        .s_axis_tlast  (core_tlast),

        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast)
    );

endmodule
