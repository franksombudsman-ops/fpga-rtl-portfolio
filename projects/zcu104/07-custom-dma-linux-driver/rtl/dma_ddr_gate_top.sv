`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Physical Gate 2
 *
 * Integrates:
 *
 *   AXI-Lite CSR block
 *          +
 *   full authored dma_core
 *          +
 *   external AXI4-MM DDR master
 *
 * Gate-2 purpose:
 * physically prove descriptor fetch from ZCU104 DDR.
 *
 * TX stream is consumed locally and RX stream is held inactive.
 * Payload-stream validation is explicitly deferred to later gates.
 */

module dma_ddr_gate_top (
    input  logic        aclk,
    input  logic        aresetn,

    /*
     * AXI4-Lite slave
     */
    input  logic [11:0] s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    input  logic [11:0] s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    output logic        irq,

    /*
     * Gate 3B observation-only TX AXI4-Stream probes.
     *
     * These outputs do not participate in control or datapath behavior.
     * They expose the existing internal TX stream for physical ILA capture.
     */
    output logic [63:0] dbg_tx_data,
    output logic [7:0]  dbg_tx_keep,
    output logic        dbg_tx_valid,
    output logic        dbg_tx_ready,
    output logic        dbg_tx_last,

    /*
     * AXI4-MM DDR master
     */
    output logic [3:0]  m_axi_arid,
    output logic [39:0] m_axi_araddr,
    output logic [7:0]  m_axi_arlen,
    output logic [2:0]  m_axi_arsize,
    output logic [1:0]  m_axi_arburst,
    output logic        m_axi_arlock,
    output logic [3:0]  m_axi_arcache,
    output logic [2:0]  m_axi_arprot,
    output logic [3:0]  m_axi_arqos,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,

    input  logic [3:0]  m_axi_rid,
    input  logic [63:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rlast,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready,

    output logic [3:0]  m_axi_awid,
    output logic [39:0] m_axi_awaddr,
    output logic [7:0]  m_axi_awlen,
    output logic [2:0]  m_axi_awsize,
    output logic [1:0]  m_axi_awburst,
    output logic        m_axi_awlock,
    output logic [3:0]  m_axi_awcache,
    output logic [2:0]  m_axi_awprot,
    output logic [3:0]  m_axi_awqos,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,

    output logic [63:0] m_axi_wdata,
    output logic [7:0]  m_axi_wstrb,
    output logic        m_axi_wlast,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,

    input  logic [3:0]  m_axi_bid,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready
);

    logic global_enable;
    logic soft_reset_pulse;
    logic counter_clear_pulse;

    logic tx_enable;
    logic tx_halt;
    logic [63:0] tx_ring_base;
    logic [15:0] tx_ring_size;
    logic [31:0] tx_tail;
    logic tx_cfg_load_pulse;

    logic rx_enable;
    logic rx_halt;
    logic [63:0] rx_ring_base;
    logic [15:0] rx_ring_size;
    logic [31:0] rx_tail;
    logic rx_cfg_load_pulse;

    logic [31:0] scratch;
    logic scratch_write_pulse;

    logic [3:0] irq_status;
    logic [3:0] irq_enable;
    logic [31:0] error_status;

    logic tx_config_valid;
    logic [3:0] tx_config_error_code;
    logic [31:0] tx_hw_head;
    logic [31:0] tx_pending_count;
    logic tx_ring_empty;
    logic tx_ring_overrun;
    logic tx_fault_valid;
    logic [3:0] tx_fault_code;

    logic tx_completion_pulse;
    logic tx_completion_irq_requested;
    logic [63:0] tx_completion_cookie;
    logic [31:0] tx_completion_status;
    logic [31:0] tx_completion_actual_length;

    logic rx_config_valid;
    logic [3:0] rx_config_error_code;
    logic [31:0] rx_hw_head;
    logic [31:0] rx_pending_count;
    logic rx_ring_empty;
    logic rx_ring_overrun;
    logic rx_fault_valid;
    logic [3:0] rx_fault_code;

    logic rx_completion_pulse;
    logic rx_completion_irq_requested;
    logic [63:0] rx_completion_cookie;
    logic [31:0] rx_completion_status;
    logic [31:0] rx_completion_actual_length;

    logic [31:0] tx_status;
    logic [31:0] rx_status;
    logic [31:0] global_status;

    logic [31:0] error_set;
    logic [31:0] error_info;

    logic tx_fault_prev;
    logic rx_fault_prev;
    logic tx_error_event;
    logic rx_error_event;

    logic [31:0] tx_sw_tail_effective;
    logic [31:0] rx_sw_tail_effective;

    logic core_aresetn;

    /*
     * Software may configure rings while disabled.
     * Publishing TAIL to dma_core requires the global/channel enables.
     */
    assign tx_sw_tail_effective =
        (global_enable && tx_enable && !tx_halt) ?
            tx_tail : tx_hw_head;

    assign rx_sw_tail_effective =
        (global_enable && rx_enable && !rx_halt) ?
            rx_tail : rx_hw_head;

    assign core_aresetn =
        aresetn && !soft_reset_pulse;

    /*
     * Temporary Gate-2 stream policy.
     *
     * TX sink is always ready.
     * RX source remains inactive.
     *
     * Gate 2 intentionally uses OWN=0 descriptors, so neither payload
     * path should become active.
     */

    logic [63:0] unused_tx_tdata;
    logic [7:0]  unused_tx_tkeep;
    logic        unused_tx_tvalid;
    logic        unused_tx_tlast;
    logic        unused_rx_tready;

    /*
     * Observation-only Gate-3B taps.
     *
     * TX sink behavior remains exactly the same as Gate 3A:
     * TREADY is permanently asserted.
     */
    assign dbg_tx_data  = unused_tx_tdata;
    assign dbg_tx_keep  = unused_tx_tkeep;
    assign dbg_tx_valid = unused_tx_tvalid;
    assign dbg_tx_ready = 1'b1;
    assign dbg_tx_last  = unused_tx_tlast;

    /*
     * Software-visible status packing for physical integration.
     *
     * [0]    config_valid
     * [1]    ring_empty
     * [2]    ring_overrun
     * [3]    fault_valid
     * [7:4]  fault_code
     * [11:8] config_error_code
     */

    assign tx_status = {
        20'd0,
        tx_config_error_code,
        tx_fault_code,
        tx_fault_valid,
        tx_ring_overrun,
        tx_ring_empty,
        tx_config_valid
    };

    assign rx_status = {
        20'd0,
        rx_config_error_code,
        rx_fault_code,
        rx_fault_valid,
        rx_ring_overrun,
        rx_ring_empty,
        rx_config_valid
    };

    assign global_status = {
        28'd0,
        rx_fault_valid,
        tx_fault_valid,
        rx_config_valid,
        tx_config_valid
    };

    /*
     * Convert sticky core fault state into one-cycle CSR events.
     */
    always_ff @(posedge aclk) begin
        if (!aresetn) begin
            tx_fault_prev <= 1'b0;
            rx_fault_prev <= 1'b0;
        end
        else begin
            tx_fault_prev <= tx_fault_valid;
            rx_fault_prev <= rx_fault_valid;
        end
    end

    assign tx_error_event =
        tx_fault_valid && !tx_fault_prev;

    assign rx_error_event =
        rx_fault_valid && !rx_fault_prev;

    assign error_set = {
        30'd0,
        rx_error_event,
        tx_error_event
    };

    assign error_info = {
        24'd0,
        rx_fault_code,
        tx_fault_code
    };

    /*
     * Software-facing CSR bank.
     */
    dma_axil_regs csr (
        .clk                     (aclk),
        .aresetn                 (aresetn),

        .s_axil_awaddr           (s_axi_awaddr),
        .s_axil_awprot           (s_axi_awprot),
        .s_axil_awvalid          (s_axi_awvalid),
        .s_axil_awready          (s_axi_awready),

        .s_axil_wdata            (s_axi_wdata),
        .s_axil_wstrb            (s_axi_wstrb),
        .s_axil_wvalid           (s_axi_wvalid),
        .s_axil_wready           (s_axi_wready),

        .s_axil_bresp            (s_axi_bresp),
        .s_axil_bvalid           (s_axi_bvalid),
        .s_axil_bready           (s_axi_bready),

        .s_axil_araddr           (s_axi_araddr),
        .s_axil_arprot           (s_axi_arprot),
        .s_axil_arvalid          (s_axi_arvalid),
        .s_axil_arready          (s_axi_arready),

        .s_axil_rdata            (s_axi_rdata),
        .s_axil_rresp            (s_axi_rresp),
        .s_axil_rvalid           (s_axi_rvalid),
        .s_axil_rready           (s_axi_rready),

        .global_enable           (global_enable),
        .soft_reset_pulse        (soft_reset_pulse),
        .counter_clear_pulse     (counter_clear_pulse),
        .global_status           (global_status),

        .tx_completion_event     (
            tx_completion_pulse &&
            tx_completion_irq_requested
        ),
        .rx_completion_event     (
            rx_completion_pulse &&
            rx_completion_irq_requested
        ),

        .tx_error_event          (tx_error_event),
        .rx_error_event          (rx_error_event),

        .irq_status              (irq_status),
        .irq_enable              (irq_enable),
        .irq                     (irq),

        .error_set               (error_set),
        .error_info              (error_info),
        .error_addr              (64'd0),
        .error_status            (error_status),

        .tx_enable               (tx_enable),
        .tx_halt                 (tx_halt),
        .tx_ring_base            (tx_ring_base),
        .tx_ring_size            (tx_ring_size),
        .tx_tail                 (tx_tail),
        .tx_cfg_load_pulse       (tx_cfg_load_pulse),
        .tx_status               (tx_status),
        .tx_head                 (tx_hw_head),

        .tx_bytes                (64'd0),
        .tx_desc_count           (32'd0),
        .tx_active_cycles        (64'd0),
        .tx_axi_stall            (64'd0),
        .tx_axis_stall           (64'd0),

        .rx_enable               (rx_enable),
        .rx_halt                 (rx_halt),
        .rx_ring_base            (rx_ring_base),
        .rx_ring_size            (rx_ring_size),
        .rx_tail                 (rx_tail),
        .rx_cfg_load_pulse       (rx_cfg_load_pulse),
        .rx_status               (rx_status),
        .rx_head                 (rx_hw_head),

        .rx_bytes                (64'd0),
        .rx_desc_count           (32'd0),
        .rx_active_cycles        (64'd0),
        .rx_axi_stall            (64'd0),
        .rx_axis_stall           (64'd0),

        .scratch                 (scratch),
        .scratch_write_pulse     (scratch_write_pulse)
    );

    /*
     * Full authored custom DMA.
     */
    dma_core #(
        .ADDR_WIDTH       (40),
        .LEN_WIDTH        (32),
        .AXI_ID_WIDTH     (4),
        .MAX_BURST_BEATS  (256)
    ) core (
        .clk                       (aclk),
        .aresetn                   (core_aresetn),

        .tx_cfg_load               (tx_cfg_load_pulse),
        .tx_ring_base              (tx_ring_base),
        .tx_ring_size              (tx_ring_size),
        .tx_sw_tail                (tx_sw_tail_effective),

        .tx_config_valid           (tx_config_valid),
        .tx_config_error_code      (tx_config_error_code),
        .tx_hw_head                (tx_hw_head),
        .tx_pending_count          (tx_pending_count),
        .tx_ring_empty             (tx_ring_empty),
        .tx_ring_overrun           (tx_ring_overrun),

        .tx_fault_valid            (tx_fault_valid),
        .tx_fault_clear            (soft_reset_pulse),
        .tx_fault_code             (tx_fault_code),

        .tx_completion_pulse       (tx_completion_pulse),
        .tx_completion_irq_requested
                                     (tx_completion_irq_requested),
        .tx_completion_cookie      (tx_completion_cookie),
        .tx_completion_status      (tx_completion_status),
        .tx_completion_actual_length
                                     (tx_completion_actual_length),

        .rx_cfg_load               (rx_cfg_load_pulse),
        .rx_ring_base              (rx_ring_base),
        .rx_ring_size              (rx_ring_size),
        .rx_sw_tail                (rx_sw_tail_effective),

        .rx_config_valid           (rx_config_valid),
        .rx_config_error_code      (rx_config_error_code),
        .rx_hw_head                (rx_hw_head),
        .rx_pending_count          (rx_pending_count),
        .rx_ring_empty             (rx_ring_empty),
        .rx_ring_overrun           (rx_ring_overrun),

        .rx_fault_valid            (rx_fault_valid),
        .rx_fault_clear            (soft_reset_pulse),
        .rx_fault_code             (rx_fault_code),

        .rx_completion_pulse       (rx_completion_pulse),
        .rx_completion_irq_requested
                                     (rx_completion_irq_requested),
        .rx_completion_cookie      (rx_completion_cookie),
        .rx_completion_status      (rx_completion_status),
        .rx_completion_actual_length
                                     (rx_completion_actual_length),

        .m_axis_tx_tdata           (unused_tx_tdata),
        .m_axis_tx_tkeep           (unused_tx_tkeep),
        .m_axis_tx_tvalid          (unused_tx_tvalid),
        .m_axis_tx_tready          (1'b1),
        .m_axis_tx_tlast           (unused_tx_tlast),

        .s_axis_rx_tdata           (64'd0),
        .s_axis_rx_tkeep           (8'd0),
        .s_axis_rx_tvalid          (1'b0),
        .s_axis_rx_tready          (unused_rx_tready),
        .s_axis_rx_tlast           (1'b0),

        .m_axi_arid                (m_axi_arid),
        .m_axi_araddr              (m_axi_araddr),
        .m_axi_arlen               (m_axi_arlen),
        .m_axi_arsize              (m_axi_arsize),
        .m_axi_arburst             (m_axi_arburst),
        .m_axi_arlock              (m_axi_arlock),
        .m_axi_arcache             (m_axi_arcache),
        .m_axi_arprot              (m_axi_arprot),
        .m_axi_arqos               (m_axi_arqos),
        .m_axi_arvalid             (m_axi_arvalid),
        .m_axi_arready             (m_axi_arready),

        .m_axi_rid                 (m_axi_rid),
        .m_axi_rdata               (m_axi_rdata),
        .m_axi_rresp               (m_axi_rresp),
        .m_axi_rlast               (m_axi_rlast),
        .m_axi_rvalid              (m_axi_rvalid),
        .m_axi_rready              (m_axi_rready),

        .m_axi_awid                (m_axi_awid),
        .m_axi_awaddr              (m_axi_awaddr),
        .m_axi_awlen               (m_axi_awlen),
        .m_axi_awsize              (m_axi_awsize),
        .m_axi_awburst             (m_axi_awburst),
        .m_axi_awlock              (m_axi_awlock),
        .m_axi_awcache             (m_axi_awcache),
        .m_axi_awprot              (m_axi_awprot),
        .m_axi_awqos               (m_axi_awqos),
        .m_axi_awvalid             (m_axi_awvalid),
        .m_axi_awready             (m_axi_awready),

        .m_axi_wdata               (m_axi_wdata),
        .m_axi_wstrb               (m_axi_wstrb),
        .m_axi_wlast               (m_axi_wlast),
        .m_axi_wvalid              (m_axi_wvalid),
        .m_axi_wready              (m_axi_wready),

        .m_axi_bid                 (m_axi_bid),
        .m_axi_bresp               (m_axi_bresp),
        .m_axi_bvalid              (m_axi_bvalid),
        .m_axi_bready              (m_axi_bready)
    );

endmodule
