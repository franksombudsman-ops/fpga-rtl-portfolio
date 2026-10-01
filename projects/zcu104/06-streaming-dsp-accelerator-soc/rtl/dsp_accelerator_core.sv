`timescale 1ns/1ps

// ============================================================================
// Project 06 - Streaming DSP Accelerator SoC
// Combined streaming compute core
//
// Author: Frank Ouma
//
// Datapath:
//
// AXI4-Stream input
//        |
//        v
// 32-tap Q1.15 FIR
//        |
//        v
// 64-sample moving-energy engine
//        |
//        v
// 64-bit AXI4-Stream result
//
// Result:
//   [15:0]  filtered FIR sample
//   [52:16] 37-bit moving energy
//   [53]     reserved for event flag
//   [63:54] reserved
//
// TLAST is transport metadata only.
// It does NOT reset FIR or moving-energy state.
// ============================================================================

module dsp_accelerator_core (

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

    logic [15:0] fir_tdata;
    logic        fir_tvalid;
    logic        fir_tready;
    logic        fir_tlast;

    // ------------------------------------------------------------------------
    // Stage 1 - 32-tap FIR
    // ------------------------------------------------------------------------

    fir32_axis u_fir32 (

        .aclk          (aclk),
        .aresetn       (aresetn),

        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .s_axis_tlast  (s_axis_tlast),

        .m_axis_tdata  (fir_tdata),
        .m_axis_tvalid (fir_tvalid),
        .m_axis_tready (fir_tready),
        .m_axis_tlast  (fir_tlast)
    );

    // ------------------------------------------------------------------------
    // Stage 2 - 64-sample moving energy
    // ------------------------------------------------------------------------

    moving_energy64_axis u_energy64 (

        .aclk          (aclk),
        .aresetn       (aresetn),

        .s_axis_tdata  (fir_tdata),
        .s_axis_tvalid (fir_tvalid),
        .s_axis_tready (fir_tready),
        .s_axis_tlast  (fir_tlast),

        .m_axis_tdata  (m_axis_tdata),
        .m_axis_tvalid (m_axis_tvalid),
        .m_axis_tready (m_axis_tready),
        .m_axis_tlast  (m_axis_tlast)
    );

endmodule
