`timescale 1ns/1ps

// ============================================================================
// Project 06 - Streaming DSP Accelerator SoC
// Software-controlled accelerator top
//
// Author: Frank Ouma
//
// AXI4-Lite:
//   control / configuration / telemetry
//
// AXI4-Stream:
//   16-bit sample input
//   64-bit processed result output
//
// Datapath:
//
// AXIS input
//    |
//    | ENABLE gating
//    v
// FIR32
//    |
//    v
// ENERGY64
//    |
//    v
// programmable event detector
//    |
//    v
// AXIS result
//
// Disable semantics:
//   ENABLE 1 -> 0 stops NEW input acceptance.
//   Already-accepted samples continue draining.
//   IDLE asserts only after all accepted samples have produced results.
//
// STATE_CLEAR is allowed only disabled + idle and resets DSP history without
// resetting AXI-Lite configuration or telemetry counters.
// ============================================================================

module dsp_accelerator_controlled (

    input logic aclk,
    input logic aresetn,

    // ========================================================================
    // AXI4-Lite control slave
    // ========================================================================

    input  logic [5:0]  s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [5:0]  s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // ========================================================================
    // AXI4-Stream input
    // ========================================================================

    input  logic [15:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    // ========================================================================
    // AXI4-Stream output
    // ========================================================================

    output logic [63:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);

    // ========================================================================
    // Configuration
    // ========================================================================

    logic        cfg_enable;
    logic [36:0] cfg_energy_threshold;

    logic cfg_state_clear_pulse;
    logic cfg_counter_clear_pulse;

    // ========================================================================
    // Status / telemetry
    // ========================================================================

    logic status_idle;
    logic status_input_active;
    logic status_output_active;

    logic sample_accepted;
    logic result_accepted;
    logic event_accepted;

    logic input_stall_cycle;
    logic output_stall_cycle;

    // ========================================================================
    // Drain tracking
    // ========================================================================

    logic [31:0] inflight_count;

    // ========================================================================
    // Compute-stream interconnect
    // ========================================================================

    logic        compute_aresetn;

    logic        compute_s_ready;

    logic [63:0] core_tdata;
    logic        core_tvalid;
    logic        core_tready;
    logic        core_tlast;

    // ------------------------------------------------------------------------
    // STATE_CLEAR resets only datapath state.
    //
    // AXI-Lite registers remain alive because they use global aresetn.
    // ------------------------------------------------------------------------

    assign compute_aresetn =
        aresetn &&
        !cfg_state_clear_pulse;

    // ------------------------------------------------------------------------
    // ENABLE gates NEW sample acceptance.
    //
    // Existing samples continue through the internal datapath after disable.
    // ------------------------------------------------------------------------

    assign s_axis_tready =
        cfg_enable &&
        compute_s_ready;

    // ------------------------------------------------------------------------
    // Handshake / telemetry definitions
    // ------------------------------------------------------------------------

    assign sample_accepted =
        s_axis_tvalid &&
        s_axis_tready;

    assign result_accepted =
        m_axis_tvalid &&
        m_axis_tready;

    assign event_accepted =
        result_accepted &&
        m_axis_tdata[53];

    assign input_stall_cycle =
        s_axis_tvalid &&
        !s_axis_tready;

    assign output_stall_cycle =
        m_axis_tvalid &&
        !m_axis_tready;

    assign status_input_active =
        sample_accepted;

    assign status_output_active =
        result_accepted;

    // IDLE is intentionally meaningful only when disabled.
    assign status_idle =
        !cfg_enable &&
        (inflight_count == 32'd0);

    // ========================================================================
    // Accepted-input / accepted-output accounting
    //
    // One accepted input must eventually correspond to one accepted result.
    // ========================================================================

    always_ff @(posedge aclk) begin

        if (!aresetn) begin

            inflight_count <= 32'd0;

        end
        else if (cfg_state_clear_pulse) begin

            // STATE_CLEAR can only occur disabled + idle.
            inflight_count <= 32'd0;

        end
        else begin

            case ({
                sample_accepted,
                result_accepted
            })

                2'b10:
                    inflight_count <=
                        inflight_count + 32'd1;

                2'b01: begin

                    if (inflight_count != 32'd0)
                        inflight_count <=
                            inflight_count - 32'd1;

                end

                default:
                    inflight_count <=
                        inflight_count;

            endcase
        end
    end

    // ========================================================================
    // AXI4-Lite register bank
    // ========================================================================

    accelerator_axil_regs u_axil_regs (

        .aclk                    (aclk),
        .aresetn                 (aresetn),

        .s_axi_awaddr            (s_axi_awaddr),
        .s_axi_awvalid           (s_axi_awvalid),
        .s_axi_awready           (s_axi_awready),

        .s_axi_wdata             (s_axi_wdata),
        .s_axi_wstrb             (s_axi_wstrb),
        .s_axi_wvalid            (s_axi_wvalid),
        .s_axi_wready            (s_axi_wready),

        .s_axi_bresp             (s_axi_bresp),
        .s_axi_bvalid            (s_axi_bvalid),
        .s_axi_bready            (s_axi_bready),

        .s_axi_araddr            (s_axi_araddr),
        .s_axi_arvalid           (s_axi_arvalid),
        .s_axi_arready           (s_axi_arready),

        .s_axi_rdata             (s_axi_rdata),
        .s_axi_rresp             (s_axi_rresp),
        .s_axi_rvalid            (s_axi_rvalid),
        .s_axi_rready            (s_axi_rready),

        .status_idle             (status_idle),
        .status_input_active     (status_input_active),
        .status_output_active    (status_output_active),

        .sample_accepted         (sample_accepted),
        .result_accepted         (result_accepted),
        .event_accepted          (event_accepted),
        .input_stall_cycle       (input_stall_cycle),
        .output_stall_cycle      (output_stall_cycle),

        .cfg_enable              (cfg_enable),
        .cfg_energy_threshold    (cfg_energy_threshold),

        .cfg_state_clear_pulse   (cfg_state_clear_pulse),
        .cfg_counter_clear_pulse (cfg_counter_clear_pulse)
    );

    // ========================================================================
    // Verified FIR + moving-energy compute core
    // ========================================================================

    dsp_accelerator_core u_compute_core (

        .aclk          (aclk),
        .aresetn       (compute_aresetn),

        .s_axis_tdata  (s_axis_tdata),

        .s_axis_tvalid (
            s_axis_tvalid &&
            cfg_enable
        ),

        .s_axis_tready (compute_s_ready),

        .s_axis_tlast  (s_axis_tlast),

        .m_axis_tdata  (core_tdata),
        .m_axis_tvalid (core_tvalid),
        .m_axis_tready (core_tready),
        .m_axis_tlast  (core_tlast)
    );

    // ========================================================================
    // Programmable event stage
    // ========================================================================

    energy_event_axis_cfg u_event_cfg (

        .aclk             (aclk),
        .aresetn          (compute_aresetn),

        .energy_threshold (cfg_energy_threshold),

        .s_axis_tdata     (core_tdata),
        .s_axis_tvalid    (core_tvalid),
        .s_axis_tready    (core_tready),
        .s_axis_tlast     (core_tlast),

        .m_axis_tdata     (m_axis_tdata),
        .m_axis_tvalid    (m_axis_tvalid),
        .m_axis_tready    (m_axis_tready),
        .m_axis_tlast     (m_axis_tlast)
    );

endmodule
