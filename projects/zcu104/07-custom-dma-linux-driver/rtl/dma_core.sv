`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * Integrated bidirectional custom DMA core.
 *
 * Memory clients:
 *
 * READ
 *   0 - TX descriptor fetch
 *   1 - RX descriptor fetch
 *   2 - TX payload read
 *
 * WRITE
 *   0 - TX descriptor writeback
 *   1 - RX descriptor writeback
 *   2 - RX payload write
 *
 * The core owns the complete descriptor/data path but deliberately
 * does not yet contain the software-facing AXI-Lite CSR block.
 */

module dma_core #(
    parameter integer ADDR_WIDTH       = 40,
    parameter integer LEN_WIDTH        = 32,
    parameter integer AXI_ID_WIDTH     = 4,
    parameter integer MAX_BURST_BEATS  = 256
)(
    input  logic                       clk,
    input  logic                       aresetn,

    /*
     * ------------------------------------------------------------
     * TX descriptor ring control
     * ------------------------------------------------------------
     */
    input  logic                       tx_cfg_load,
    input  logic [63:0]                tx_ring_base,
    input  logic [15:0]                tx_ring_size,
    input  logic [31:0]                tx_sw_tail,

    output logic                       tx_config_valid,
    output logic [3:0]                 tx_config_error_code,
    output logic [31:0]                tx_hw_head,
    output logic [31:0]                tx_pending_count,
    output logic                       tx_ring_empty,
    output logic                       tx_ring_overrun,

    output logic                       tx_fault_valid,
    input  logic                       tx_fault_clear,
    output logic [3:0]                 tx_fault_code,

    output logic                       tx_completion_pulse,
    output logic                       tx_completion_irq_requested,
    output logic [63:0]                tx_completion_cookie,
    output logic [31:0]                tx_completion_status,
    output logic [31:0]                tx_completion_actual_length,

    /*
     * ------------------------------------------------------------
     * RX descriptor ring control
     * ------------------------------------------------------------
     */
    input  logic                       rx_cfg_load,
    input  logic [63:0]                rx_ring_base,
    input  logic [15:0]                rx_ring_size,
    input  logic [31:0]                rx_sw_tail,

    output logic                       rx_config_valid,
    output logic [3:0]                 rx_config_error_code,
    output logic [31:0]                rx_hw_head,
    output logic [31:0]                rx_pending_count,
    output logic                       rx_ring_empty,
    output logic                       rx_ring_overrun,

    output logic                       rx_fault_valid,
    input  logic                       rx_fault_clear,
    output logic [3:0]                 rx_fault_code,

    output logic                       rx_completion_pulse,
    output logic                       rx_completion_irq_requested,
    output logic [63:0]                rx_completion_cookie,
    output logic [31:0]                rx_completion_status,
    output logic [31:0]                rx_completion_actual_length,

    /*
     * ------------------------------------------------------------
     * TX stream: DDR -> PL stream
     * ------------------------------------------------------------
     */
    output logic [63:0]                m_axis_tx_tdata,
    output logic [7:0]                 m_axis_tx_tkeep,
    output logic                       m_axis_tx_tvalid,
    input  logic                       m_axis_tx_tready,
    output logic                       m_axis_tx_tlast,

    /*
     * ------------------------------------------------------------
     * RX stream: PL stream -> DDR
     * ------------------------------------------------------------
     */
    input  logic [63:0]                s_axis_rx_tdata,
    input  logic [7:0]                 s_axis_rx_tkeep,
    input  logic                       s_axis_rx_tvalid,
    output logic                       s_axis_rx_tready,
    input  logic                       s_axis_rx_tlast,

    /*
     * ------------------------------------------------------------
     * AXI4 memory master - READ
     * ------------------------------------------------------------
     */
    output logic [AXI_ID_WIDTH-1:0]    m_axi_arid,
    output logic [ADDR_WIDTH-1:0]      m_axi_araddr,
    output logic [7:0]                 m_axi_arlen,
    output logic [2:0]                 m_axi_arsize,
    output logic [1:0]                 m_axi_arburst,
    output logic                       m_axi_arlock,
    output logic [3:0]                 m_axi_arcache,
    output logic [2:0]                 m_axi_arprot,
    output logic [3:0]                 m_axi_arqos,
    output logic                       m_axi_arvalid,
    input  logic                       m_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0]    m_axi_rid,
    input  logic [63:0]                m_axi_rdata,
    input  logic [1:0]                 m_axi_rresp,
    input  logic                       m_axi_rlast,
    input  logic                       m_axi_rvalid,
    output logic                       m_axi_rready,

    /*
     * ------------------------------------------------------------
     * AXI4 memory master - WRITE
     * ------------------------------------------------------------
     */
    output logic [AXI_ID_WIDTH-1:0]    m_axi_awid,
    output logic [ADDR_WIDTH-1:0]      m_axi_awaddr,
    output logic [7:0]                 m_axi_awlen,
    output logic [2:0]                 m_axi_awsize,
    output logic [1:0]                 m_axi_awburst,
    output logic                       m_axi_awlock,
    output logic [3:0]                 m_axi_awcache,
    output logic [2:0]                 m_axi_awprot,
    output logic [3:0]                 m_axi_awqos,
    output logic                       m_axi_awvalid,
    input  logic                       m_axi_awready,

    output logic [63:0]                m_axi_wdata,
    output logic [7:0]                 m_axi_wstrb,
    output logic                       m_axi_wlast,
    output logic                       m_axi_wvalid,
    input  logic                       m_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0]    m_axi_bid,
    input  logic [1:0]                 m_axi_bresp,
    input  logic                       m_axi_bvalid,
    output logic                       m_axi_bready
);

    /*
     * ============================================================
     * TX descriptor <-> TX payload
     * ============================================================
     */

    logic        tx_work_valid;
    logic        tx_work_ready;
    logic [63:0] tx_work_buffer_addr;
    logic [31:0] tx_work_length;
    logic [31:0] tx_work_control;
    logic [63:0] tx_work_cookie;
    logic        tx_work_irq;
    logic        tx_work_eop;

    logic        tx_retire_valid;
    logic        tx_retire_ready;
    logic [31:0] tx_retire_status;
    logic [31:0] tx_retire_actual_length;

    /*
     * ============================================================
     * RX descriptor <-> RX payload
     * ============================================================
     */

    logic        rx_work_valid;
    logic        rx_work_ready;
    logic [63:0] rx_work_buffer_addr;
    logic [31:0] rx_work_length;
    logic [31:0] rx_work_control;
    logic [63:0] rx_work_cookie;
    logic        rx_work_irq;
    logic        rx_work_eop;

    logic        rx_retire_valid;
    logic        rx_retire_ready;
    logic [31:0] rx_retire_status;
    logic [31:0] rx_retire_actual_length;

    /*
     * ============================================================
     * READ CLIENT 0 - TX descriptor
     * ============================================================
     */

    logic                  txd_rd_req_valid;
    logic                  txd_rd_req_ready;
    logic [ADDR_WIDTH-1:0] txd_rd_req_addr;
    logic [LEN_WIDTH-1:0]  txd_rd_req_bytes;

    logic [63:0]           txd_rd_data;
    logic [7:0]            txd_rd_keep;
    logic                  txd_rd_data_valid;
    logic                  txd_rd_data_ready;
    logic                  txd_rd_data_last;

    logic                  txd_rd_cpl_valid;
    logic                  txd_rd_cpl_ready;
    logic                  txd_rd_cpl_error;
    logic [3:0]            txd_rd_cpl_error_code;
    logic [LEN_WIDTH-1:0]  txd_rd_cpl_bytes;

    /*
     * READ CLIENT 1 - RX descriptor
     */

    logic                  rxd_rd_req_valid;
    logic                  rxd_rd_req_ready;
    logic [ADDR_WIDTH-1:0] rxd_rd_req_addr;
    logic [LEN_WIDTH-1:0]  rxd_rd_req_bytes;

    logic [63:0]           rxd_rd_data;
    logic [7:0]            rxd_rd_keep;
    logic                  rxd_rd_data_valid;
    logic                  rxd_rd_data_ready;
    logic                  rxd_rd_data_last;

    logic                  rxd_rd_cpl_valid;
    logic                  rxd_rd_cpl_ready;
    logic                  rxd_rd_cpl_error;
    logic [3:0]            rxd_rd_cpl_error_code;
    logic [LEN_WIDTH-1:0]  rxd_rd_cpl_bytes;

    /*
     * READ CLIENT 2 - TX payload
     */

    logic                  txp_rd_req_valid;
    logic                  txp_rd_req_ready;
    logic [ADDR_WIDTH-1:0] txp_rd_req_addr;
    logic [LEN_WIDTH-1:0]  txp_rd_req_bytes;

    logic [63:0]           txp_rd_data;
    logic [7:0]            txp_rd_keep;
    logic                  txp_rd_data_valid;
    logic                  txp_rd_data_ready;
    logic                  txp_rd_data_last;

    logic                  txp_rd_cpl_valid;
    logic                  txp_rd_cpl_ready;
    logic                  txp_rd_cpl_error;
    logic [3:0]            txp_rd_cpl_error_code;
    logic [LEN_WIDTH-1:0]  txp_rd_cpl_bytes;

    /*
     * Shared internal read-master interface.
     */

    logic                  rdm_req_valid;
    logic                  rdm_req_ready;
    logic [ADDR_WIDTH-1:0] rdm_req_addr;
    logic [LEN_WIDTH-1:0]  rdm_req_bytes;

    logic [63:0]           rdm_data;
    logic [7:0]            rdm_keep;
    logic                  rdm_data_valid;
    logic                  rdm_data_ready;
    logic                  rdm_data_last;

    logic                  rdm_cpl_valid;
    logic                  rdm_cpl_ready;
    logic                  rdm_cpl_error;
    logic [3:0]            rdm_cpl_error_code;
    logic [LEN_WIDTH-1:0]  rdm_cpl_bytes;

    /*
     * ============================================================
     * WRITE CLIENT 0 - TX descriptor
     * ============================================================
     */

    logic                  txd_wr_req_valid;
    logic                  txd_wr_req_ready;
    logic [ADDR_WIDTH-1:0] txd_wr_req_addr;
    logic [LEN_WIDTH-1:0]  txd_wr_req_bytes;

    logic [63:0]           txd_wr_data;
    logic [7:0]            txd_wr_keep;
    logic                  txd_wr_data_valid;
    logic                  txd_wr_data_ready;

    logic                  txd_wr_cpl_valid;
    logic                  txd_wr_cpl_ready;
    logic                  txd_wr_cpl_error;
    logic [3:0]            txd_wr_cpl_error_code;
    logic [LEN_WIDTH-1:0]  txd_wr_cpl_bytes;

    /*
     * WRITE CLIENT 1 - RX descriptor
     */

    logic                  rxd_wr_req_valid;
    logic                  rxd_wr_req_ready;
    logic [ADDR_WIDTH-1:0] rxd_wr_req_addr;
    logic [LEN_WIDTH-1:0]  rxd_wr_req_bytes;

    logic [63:0]           rxd_wr_data;
    logic [7:0]            rxd_wr_keep;
    logic                  rxd_wr_data_valid;
    logic                  rxd_wr_data_ready;

    logic                  rxd_wr_cpl_valid;
    logic                  rxd_wr_cpl_ready;
    logic                  rxd_wr_cpl_error;
    logic [3:0]            rxd_wr_cpl_error_code;
    logic [LEN_WIDTH-1:0]  rxd_wr_cpl_bytes;

    /*
     * WRITE CLIENT 2 - RX payload
     */

    logic                  rxp_wr_req_valid;
    logic                  rxp_wr_req_ready;
    logic [ADDR_WIDTH-1:0] rxp_wr_req_addr;
    logic [LEN_WIDTH-1:0]  rxp_wr_req_bytes;

    logic [63:0]           rxp_wr_data;
    logic [7:0]            rxp_wr_keep;
    logic                  rxp_wr_data_valid;
    logic                  rxp_wr_data_ready;

    logic                  rxp_wr_cpl_valid;
    logic                  rxp_wr_cpl_ready;
    logic                  rxp_wr_cpl_error;
    logic [3:0]            rxp_wr_cpl_error_code;
    logic [LEN_WIDTH-1:0]  rxp_wr_cpl_bytes;

    /*
     * Shared internal write-master interface.
     */

    logic                  wrm_req_valid;
    logic                  wrm_req_ready;
    logic [ADDR_WIDTH-1:0] wrm_req_addr;
    logic [LEN_WIDTH-1:0]  wrm_req_bytes;

    logic [63:0]           wrm_data;
    logic [7:0]            wrm_keep;
    logic                  wrm_data_valid;
    logic                  wrm_data_ready;

    logic                  wrm_cpl_valid;
    logic                  wrm_cpl_ready;
    logic                  wrm_cpl_error;
    logic [3:0]            wrm_cpl_error_code;
    logic [LEN_WIDTH-1:0]  wrm_cpl_bytes;

    /*
     * ============================================================
     * TX DESCRIPTOR ENGINE
     * ============================================================
     */

    dma_descriptor_engine #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .LEN_WIDTH  (LEN_WIDTH)
    ) tx_descriptor_engine (
        .clk                      (clk),
        .aresetn                  (aresetn),

        .cfg_load                 (tx_cfg_load),
        .cfg_ring_base            (tx_ring_base),
        .cfg_ring_size            (tx_ring_size),
        .sw_tail                  (tx_sw_tail),

        .config_valid             (tx_config_valid),
        .config_error_code        (tx_config_error_code),
        .hw_head                  (tx_hw_head),
        .pending_count            (tx_pending_count),
        .ring_empty               (tx_ring_empty),
        .ring_overrun             (tx_ring_overrun),

        .work_valid               (tx_work_valid),
        .work_ready               (tx_work_ready),
        .work_buffer_addr         (tx_work_buffer_addr),
        .work_length              (tx_work_length),
        .work_control             (tx_work_control),
        .work_cookie              (tx_work_cookie),
        .work_irq_on_completion   (tx_work_irq),
        .work_end_of_packet       (tx_work_eop),

        .retire_valid             (tx_retire_valid),
        .retire_ready             (tx_retire_ready),
        .retire_status            (tx_retire_status),
        .retire_actual_length     (tx_retire_actual_length),

        .completion_pulse         (tx_completion_pulse),
        .completion_irq_requested (tx_completion_irq_requested),
        .completion_cookie        (tx_completion_cookie),
        .completion_status        (tx_completion_status),
        .completion_actual_length (tx_completion_actual_length),

        .fault_valid              (tx_fault_valid),
        .fault_clear              (tx_fault_clear),
        .fault_code               (tx_fault_code),

        .rd_req_valid             (txd_rd_req_valid),
        .rd_req_ready             (txd_rd_req_ready),
        .rd_req_addr              (txd_rd_req_addr),
        .rd_req_bytes             (txd_rd_req_bytes),

        .rd_data                  (txd_rd_data),
        .rd_data_keep             (txd_rd_keep),
        .rd_data_valid            (txd_rd_data_valid),
        .rd_data_ready            (txd_rd_data_ready),
        .rd_data_last             (txd_rd_data_last),

        .rd_cpl_valid             (txd_rd_cpl_valid),
        .rd_cpl_ready             (txd_rd_cpl_ready),
        .rd_cpl_error             (txd_rd_cpl_error),
        .rd_cpl_error_code        (txd_rd_cpl_error_code),
        .rd_cpl_bytes             (txd_rd_cpl_bytes),

        .wr_req_valid             (txd_wr_req_valid),
        .wr_req_ready             (txd_wr_req_ready),
        .wr_req_addr              (txd_wr_req_addr),
        .wr_req_bytes             (txd_wr_req_bytes),

        .wr_data                  (txd_wr_data),
        .wr_keep                  (txd_wr_keep),
        .wr_data_valid            (txd_wr_data_valid),
        .wr_data_ready            (txd_wr_data_ready),

        .wr_cpl_valid             (txd_wr_cpl_valid),
        .wr_cpl_ready             (txd_wr_cpl_ready),
        .wr_cpl_error             (txd_wr_cpl_error),
        .wr_cpl_error_code        (txd_wr_cpl_error_code),
        .wr_cpl_bytes             (txd_wr_cpl_bytes)
    );

    /*
     * ============================================================
     * RX DESCRIPTOR ENGINE
     * ============================================================
     */

    dma_descriptor_engine #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .LEN_WIDTH  (LEN_WIDTH)
    ) rx_descriptor_engine (
        .clk                      (clk),
        .aresetn                  (aresetn),

        .cfg_load                 (rx_cfg_load),
        .cfg_ring_base            (rx_ring_base),
        .cfg_ring_size            (rx_ring_size),
        .sw_tail                  (rx_sw_tail),

        .config_valid             (rx_config_valid),
        .config_error_code        (rx_config_error_code),
        .hw_head                  (rx_hw_head),
        .pending_count            (rx_pending_count),
        .ring_empty               (rx_ring_empty),
        .ring_overrun             (rx_ring_overrun),

        .work_valid               (rx_work_valid),
        .work_ready               (rx_work_ready),
        .work_buffer_addr         (rx_work_buffer_addr),
        .work_length              (rx_work_length),
        .work_control             (rx_work_control),
        .work_cookie              (rx_work_cookie),
        .work_irq_on_completion   (rx_work_irq),
        .work_end_of_packet       (rx_work_eop),

        .retire_valid             (rx_retire_valid),
        .retire_ready             (rx_retire_ready),
        .retire_status            (rx_retire_status),
        .retire_actual_length     (rx_retire_actual_length),

        .completion_pulse         (rx_completion_pulse),
        .completion_irq_requested (rx_completion_irq_requested),
        .completion_cookie        (rx_completion_cookie),
        .completion_status        (rx_completion_status),
        .completion_actual_length (rx_completion_actual_length),

        .fault_valid              (rx_fault_valid),
        .fault_clear              (rx_fault_clear),
        .fault_code               (rx_fault_code),

        .rd_req_valid             (rxd_rd_req_valid),
        .rd_req_ready             (rxd_rd_req_ready),
        .rd_req_addr              (rxd_rd_req_addr),
        .rd_req_bytes             (rxd_rd_req_bytes),

        .rd_data                  (rxd_rd_data),
        .rd_data_keep             (rxd_rd_keep),
        .rd_data_valid            (rxd_rd_data_valid),
        .rd_data_ready            (rxd_rd_data_ready),
        .rd_data_last             (rxd_rd_data_last),

        .rd_cpl_valid             (rxd_rd_cpl_valid),
        .rd_cpl_ready             (rxd_rd_cpl_ready),
        .rd_cpl_error             (rxd_rd_cpl_error),
        .rd_cpl_error_code        (rxd_rd_cpl_error_code),
        .rd_cpl_bytes             (rxd_rd_cpl_bytes),

        .wr_req_valid             (rxd_wr_req_valid),
        .wr_req_ready             (rxd_wr_req_ready),
        .wr_req_addr              (rxd_wr_req_addr),
        .wr_req_bytes             (rxd_wr_req_bytes),

        .wr_data                  (rxd_wr_data),
        .wr_keep                  (rxd_wr_keep),
        .wr_data_valid            (rxd_wr_data_valid),
        .wr_data_ready            (rxd_wr_data_ready),

        .wr_cpl_valid             (rxd_wr_cpl_valid),
        .wr_cpl_ready             (rxd_wr_cpl_ready),
        .wr_cpl_error             (rxd_wr_cpl_error),
        .wr_cpl_error_code        (rxd_wr_cpl_error_code),
        .wr_cpl_bytes             (rxd_wr_cpl_bytes)
    );

    /*
     * ============================================================
     * TX PAYLOAD ENGINE
     * ============================================================
     */

    dma_tx_engine #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .LEN_WIDTH  (LEN_WIDTH)
    ) tx_payload_engine (
        .clk                    (clk),
        .aresetn                (aresetn),

        .work_valid             (tx_work_valid),
        .work_ready             (tx_work_ready),
        .work_buffer_addr       (tx_work_buffer_addr),
        .work_length            (tx_work_length),
        .work_control           (tx_work_control),
        .work_cookie            (tx_work_cookie),
        .work_irq_on_completion (tx_work_irq),
        .work_end_of_packet     (tx_work_eop),

        .retire_valid           (tx_retire_valid),
        .retire_ready           (tx_retire_ready),
        .retire_status          (tx_retire_status),
        .retire_actual_length   (tx_retire_actual_length),

        .m_axis_tdata           (m_axis_tx_tdata),
        .m_axis_tkeep           (m_axis_tx_tkeep),
        .m_axis_tvalid          (m_axis_tx_tvalid),
        .m_axis_tready          (m_axis_tx_tready),
        .m_axis_tlast           (m_axis_tx_tlast),

        .rd_req_valid           (txp_rd_req_valid),
        .rd_req_ready           (txp_rd_req_ready),
        .rd_req_addr            (txp_rd_req_addr),
        .rd_req_bytes           (txp_rd_req_bytes),

        .rd_data                (txp_rd_data),
        .rd_data_keep           (txp_rd_keep),
        .rd_data_valid          (txp_rd_data_valid),
        .rd_data_ready          (txp_rd_data_ready),
        .rd_data_last           (txp_rd_data_last),

        .rd_cpl_valid           (txp_rd_cpl_valid),
        .rd_cpl_ready           (txp_rd_cpl_ready),
        .rd_cpl_error           (txp_rd_cpl_error),
        .rd_cpl_error_code      (txp_rd_cpl_error_code),
        .rd_cpl_bytes           (txp_rd_cpl_bytes)
    );

    /*
     * ============================================================
     * RX PAYLOAD ENGINE
     * ============================================================
     */

    dma_rx_engine #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .LEN_WIDTH  (LEN_WIDTH)
    ) rx_payload_engine (
        .clk                    (clk),
        .aresetn                (aresetn),

        .work_valid             (rx_work_valid),
        .work_ready             (rx_work_ready),
        .work_buffer_addr       (rx_work_buffer_addr),
        .work_length            (rx_work_length),
        .work_control           (rx_work_control),
        .work_cookie            (rx_work_cookie),
        .work_irq_on_completion (rx_work_irq),
        .work_end_of_packet     (rx_work_eop),

        .retire_valid           (rx_retire_valid),
        .retire_ready           (rx_retire_ready),
        .retire_status          (rx_retire_status),
        .retire_actual_length   (rx_retire_actual_length),

        .s_axis_tdata           (s_axis_rx_tdata),
        .s_axis_tkeep           (s_axis_rx_tkeep),
        .s_axis_tvalid          (s_axis_rx_tvalid),
        .s_axis_tready          (s_axis_rx_tready),
        .s_axis_tlast           (s_axis_rx_tlast),

        .wr_req_valid           (rxp_wr_req_valid),
        .wr_req_ready           (rxp_wr_req_ready),
        .wr_req_addr            (rxp_wr_req_addr),
        .wr_req_bytes           (rxp_wr_req_bytes),

        .wr_data                (rxp_wr_data),
        .wr_keep                (rxp_wr_keep),
        .wr_data_valid          (rxp_wr_data_valid),
        .wr_data_ready          (rxp_wr_data_ready),

        .wr_cpl_valid           (rxp_wr_cpl_valid),
        .wr_cpl_ready           (rxp_wr_cpl_ready),
        .wr_cpl_error           (rxp_wr_cpl_error),
        .wr_cpl_error_code      (rxp_wr_cpl_error_code),
        .wr_cpl_bytes           (rxp_wr_cpl_bytes)
    );

    /*
     * ============================================================
     * READ ARBITER
     * ============================================================
     */

    dma_read_arbiter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .LEN_WIDTH  (LEN_WIDTH)
    ) read_arbiter (
        .clk               (clk),
        .aresetn           (aresetn),

        .c0_req_valid      (txd_rd_req_valid),
        .c0_req_ready      (txd_rd_req_ready),
        .c0_req_addr       (txd_rd_req_addr),
        .c0_req_bytes      (txd_rd_req_bytes),
        .c0_data           (txd_rd_data),
        .c0_keep           (txd_rd_keep),
        .c0_data_valid     (txd_rd_data_valid),
        .c0_data_ready     (txd_rd_data_ready),
        .c0_data_last      (txd_rd_data_last),
        .c0_cpl_valid      (txd_rd_cpl_valid),
        .c0_cpl_ready      (txd_rd_cpl_ready),
        .c0_cpl_error      (txd_rd_cpl_error),
        .c0_cpl_error_code (txd_rd_cpl_error_code),
        .c0_cpl_bytes      (txd_rd_cpl_bytes),

        .c1_req_valid      (rxd_rd_req_valid),
        .c1_req_ready      (rxd_rd_req_ready),
        .c1_req_addr       (rxd_rd_req_addr),
        .c1_req_bytes      (rxd_rd_req_bytes),
        .c1_data           (rxd_rd_data),
        .c1_keep           (rxd_rd_keep),
        .c1_data_valid     (rxd_rd_data_valid),
        .c1_data_ready     (rxd_rd_data_ready),
        .c1_data_last      (rxd_rd_data_last),
        .c1_cpl_valid      (rxd_rd_cpl_valid),
        .c1_cpl_ready      (rxd_rd_cpl_ready),
        .c1_cpl_error      (rxd_rd_cpl_error),
        .c1_cpl_error_code (rxd_rd_cpl_error_code),
        .c1_cpl_bytes      (rxd_rd_cpl_bytes),

        .c2_req_valid      (txp_rd_req_valid),
        .c2_req_ready      (txp_rd_req_ready),
        .c2_req_addr       (txp_rd_req_addr),
        .c2_req_bytes      (txp_rd_req_bytes),
        .c2_data           (txp_rd_data),
        .c2_keep           (txp_rd_keep),
        .c2_data_valid     (txp_rd_data_valid),
        .c2_data_ready     (txp_rd_data_ready),
        .c2_data_last      (txp_rd_data_last),
        .c2_cpl_valid      (txp_rd_cpl_valid),
        .c2_cpl_ready      (txp_rd_cpl_ready),
        .c2_cpl_error      (txp_rd_cpl_error),
        .c2_cpl_error_code (txp_rd_cpl_error_code),
        .c2_cpl_bytes      (txp_rd_cpl_bytes),

        .m_req_valid       (rdm_req_valid),
        .m_req_ready       (rdm_req_ready),
        .m_req_addr        (rdm_req_addr),
        .m_req_bytes       (rdm_req_bytes),

        .m_data            (rdm_data),
        .m_keep            (rdm_keep),
        .m_data_valid      (rdm_data_valid),
        .m_data_ready      (rdm_data_ready),
        .m_data_last       (rdm_data_last),

        .m_cpl_valid       (rdm_cpl_valid),
        .m_cpl_ready       (rdm_cpl_ready),
        .m_cpl_error       (rdm_cpl_error),
        .m_cpl_error_code  (rdm_cpl_error_code),
        .m_cpl_bytes       (rdm_cpl_bytes)
    );

    /*
     * ============================================================
     * WRITE ARBITER
     * ============================================================
     */

    dma_write_arbiter #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .LEN_WIDTH  (LEN_WIDTH)
    ) write_arbiter (
        .clk               (clk),
        .aresetn           (aresetn),

        .c0_req_valid      (txd_wr_req_valid),
        .c0_req_ready      (txd_wr_req_ready),
        .c0_req_addr       (txd_wr_req_addr),
        .c0_req_bytes      (txd_wr_req_bytes),
        .c0_data           (txd_wr_data),
        .c0_keep           (txd_wr_keep),
        .c0_data_valid     (txd_wr_data_valid),
        .c0_data_ready     (txd_wr_data_ready),
        .c0_cpl_valid      (txd_wr_cpl_valid),
        .c0_cpl_ready      (txd_wr_cpl_ready),
        .c0_cpl_error      (txd_wr_cpl_error),
        .c0_cpl_error_code (txd_wr_cpl_error_code),
        .c0_cpl_bytes      (txd_wr_cpl_bytes),

        .c1_req_valid      (rxd_wr_req_valid),
        .c1_req_ready      (rxd_wr_req_ready),
        .c1_req_addr       (rxd_wr_req_addr),
        .c1_req_bytes      (rxd_wr_req_bytes),
        .c1_data           (rxd_wr_data),
        .c1_keep           (rxd_wr_keep),
        .c1_data_valid     (rxd_wr_data_valid),
        .c1_data_ready     (rxd_wr_data_ready),
        .c1_cpl_valid      (rxd_wr_cpl_valid),
        .c1_cpl_ready      (rxd_wr_cpl_ready),
        .c1_cpl_error      (rxd_wr_cpl_error),
        .c1_cpl_error_code (rxd_wr_cpl_error_code),
        .c1_cpl_bytes      (rxd_wr_cpl_bytes),

        .c2_req_valid      (rxp_wr_req_valid),
        .c2_req_ready      (rxp_wr_req_ready),
        .c2_req_addr       (rxp_wr_req_addr),
        .c2_req_bytes      (rxp_wr_req_bytes),
        .c2_data           (rxp_wr_data),
        .c2_keep           (rxp_wr_keep),
        .c2_data_valid     (rxp_wr_data_valid),
        .c2_data_ready     (rxp_wr_data_ready),
        .c2_cpl_valid      (rxp_wr_cpl_valid),
        .c2_cpl_ready      (rxp_wr_cpl_ready),
        .c2_cpl_error      (rxp_wr_cpl_error),
        .c2_cpl_error_code (rxp_wr_cpl_error_code),
        .c2_cpl_bytes      (rxp_wr_cpl_bytes),

        .m_req_valid       (wrm_req_valid),
        .m_req_ready       (wrm_req_ready),
        .m_req_addr        (wrm_req_addr),
        .m_req_bytes       (wrm_req_bytes),

        .m_data            (wrm_data),
        .m_keep            (wrm_keep),
        .m_data_valid      (wrm_data_valid),
        .m_data_ready      (wrm_data_ready),

        .m_cpl_valid       (wrm_cpl_valid),
        .m_cpl_ready       (wrm_cpl_ready),
        .m_cpl_error       (wrm_cpl_error),
        .m_cpl_error_code  (wrm_cpl_error_code),
        .m_cpl_bytes       (wrm_cpl_bytes)
    );

    /*
     * ============================================================
     * SHARED AXI READ MASTER
     * ============================================================
     */

    dma_axi_read_master #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .LEN_WIDTH       (LEN_WIDTH),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .MAX_BURST_BEATS (MAX_BURST_BEATS)
    ) read_master (
        .clk              (clk),
        .aresetn          (aresetn),

        .req_valid        (rdm_req_valid),
        .req_ready        (rdm_req_ready),
        .req_addr         (rdm_req_addr),
        .req_bytes        (rdm_req_bytes),

        .m_data           (rdm_data),
        .m_keep           (rdm_keep),
        .m_valid          (rdm_data_valid),
        .m_ready          (rdm_data_ready),
        .m_last           (rdm_data_last),

        .cpl_valid        (rdm_cpl_valid),
        .cpl_ready        (rdm_cpl_ready),
        .cpl_error        (rdm_cpl_error),
        .cpl_error_code   (rdm_cpl_error_code),
        .cpl_bytes        (rdm_cpl_bytes),

        .m_axi_arid       (m_axi_arid),
        .m_axi_araddr     (m_axi_araddr),
        .m_axi_arlen      (m_axi_arlen),
        .m_axi_arsize     (m_axi_arsize),
        .m_axi_arburst    (m_axi_arburst),
        .m_axi_arlock     (m_axi_arlock),
        .m_axi_arcache    (m_axi_arcache),
        .m_axi_arprot     (m_axi_arprot),
        .m_axi_arqos      (m_axi_arqos),
        .m_axi_arvalid    (m_axi_arvalid),
        .m_axi_arready    (m_axi_arready),

        .m_axi_rid        (m_axi_rid),
        .m_axi_rdata      (m_axi_rdata),
        .m_axi_rresp      (m_axi_rresp),
        .m_axi_rlast      (m_axi_rlast),
        .m_axi_rvalid     (m_axi_rvalid),
        .m_axi_rready     (m_axi_rready)
    );

    /*
     * ============================================================
     * SHARED AXI WRITE MASTER
     * ============================================================
     */

    dma_axi_write_master #(
        .ADDR_WIDTH      (ADDR_WIDTH),
        .LEN_WIDTH       (LEN_WIDTH),
        .AXI_ID_WIDTH    (AXI_ID_WIDTH),
        .MAX_BURST_BEATS (MAX_BURST_BEATS)
    ) write_master (
        .clk              (clk),
        .aresetn          (aresetn),

        .req_valid        (wrm_req_valid),
        .req_ready        (wrm_req_ready),
        .req_addr         (wrm_req_addr),
        .req_bytes        (wrm_req_bytes),

        .s_data           (wrm_data),
        .s_keep           (wrm_keep),
        .s_valid          (wrm_data_valid),
        .s_ready          (wrm_data_ready),

        .cpl_valid        (wrm_cpl_valid),
        .cpl_ready        (wrm_cpl_ready),
        .cpl_error        (wrm_cpl_error),
        .cpl_error_code   (wrm_cpl_error_code),
        .cpl_bytes        (wrm_cpl_bytes),

        .m_axi_awid       (m_axi_awid),
        .m_axi_awaddr     (m_axi_awaddr),
        .m_axi_awlen      (m_axi_awlen),
        .m_axi_awsize     (m_axi_awsize),
        .m_axi_awburst    (m_axi_awburst),
        .m_axi_awlock     (m_axi_awlock),
        .m_axi_awcache    (m_axi_awcache),
        .m_axi_awprot     (m_axi_awprot),
        .m_axi_awqos      (m_axi_awqos),
        .m_axi_awvalid    (m_axi_awvalid),
        .m_axi_awready    (m_axi_awready),

        .m_axi_wdata      (m_axi_wdata),
        .m_axi_wstrb      (m_axi_wstrb),
        .m_axi_wlast      (m_axi_wlast),
        .m_axi_wvalid     (m_axi_wvalid),
        .m_axi_wready     (m_axi_wready),

        .m_axi_bid        (m_axi_bid),
        .m_axi_bresp      (m_axi_bresp),
        .m_axi_bvalid     (m_axi_bvalid),
        .m_axi_bready     (m_axi_bready)
    );

endmodule
