`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * Minimal ZCU104 physical bring-up shell.
 *
 * Purpose:
 *
 *   Gate 1 - A53 reads ID / VERSION
 *   Gate 2 - A53 writes and reads SCRATCH
 *   Gate 3 - prove PL -> PS interrupt path
 *
 * This shell intentionally does NOT instantiate dma_core.
 *
 * Bring-up-only IRQ stimulus:
 *
 *   each successful SCRATCH write produces a TX-completion
 *   event into the already-verified interrupt controller.
 *
 * This behavior is for physical infrastructure validation only
 * and is removed/replaced when the complete DMA core is attached.
 */

module dma_bringup_shell (

    /*
     * Clock/reset for AXI-Lite and CSR logic.
     */
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER =
       "XIL_INTERFACENAME aclk, ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET aresetn, FREQ_HZ 100000000" *)
    input  logic        aclk,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER =
       "XIL_INTERFACENAME aresetn, POLARITY ACTIVE_LOW" *)
    input  logic        aresetn,

    /*
     * ------------------------------------------------------------
     * AXI4-Lite slave
     * ------------------------------------------------------------
     */

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWADDR" *)
    (* X_INTERFACE_PARAMETER =
       "XIL_INTERFACENAME S_AXI, PROTOCOL AXI4LITE, DATA_WIDTH 32, ADDR_WIDTH 12, READ_WRITE_MODE READ_WRITE" *)
    input  logic [11:0] s_axi_awaddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWPROT" *)
    input  logic [2:0]  s_axi_awprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWVALID" *)
    input  logic        s_axi_awvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI AWREADY" *)
    output logic        s_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WDATA" *)
    input  logic [31:0] s_axi_wdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WSTRB" *)
    input  logic [3:0]  s_axi_wstrb,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WVALID" *)
    input  logic        s_axi_wvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI WREADY" *)
    output logic        s_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BRESP" *)
    output logic [1:0]  s_axi_bresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BVALID" *)
    output logic        s_axi_bvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI BREADY" *)
    input  logic        s_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARADDR" *)
    input  logic [11:0] s_axi_araddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARPROT" *)
    input  logic [2:0]  s_axi_arprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARVALID" *)
    input  logic        s_axi_arvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI ARREADY" *)
    output logic        s_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RDATA" *)
    output logic [31:0] s_axi_rdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RRESP" *)
    output logic [1:0]  s_axi_rresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RVALID" *)
    output logic        s_axi_rvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S_AXI RREADY" *)
    input  logic        s_axi_rready,

    /*
     * PL -> PS interrupt.
     */
    (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 irq INTERRUPT" *)
    (* X_INTERFACE_PARAMETER =
       "XIL_INTERFACENAME irq, SENSITIVITY LEVEL_HIGH" *)
    output logic        irq
);

    /*
     * CSR outputs.
     */
    logic        global_enable;
    logic        soft_reset_pulse;
    logic        counter_clear_pulse;

    logic [3:0]  irq_status;
    logic [3:0]  irq_enable;

    logic [31:0] error_status;

    logic        tx_enable;
    logic        tx_halt;
    logic [63:0] tx_ring_base;
    logic [15:0] tx_ring_size;
    logic [31:0] tx_tail;
    logic        tx_cfg_load_pulse;

    logic        rx_enable;
    logic        rx_halt;
    logic [63:0] rx_ring_base;
    logic [15:0] rx_ring_size;
    logic [31:0] rx_tail;
    logic        rx_cfg_load_pulse;

    logic [31:0] scratch;
    logic        scratch_write_pulse;

    /*
     * ------------------------------------------------------------
     * Bring-up CSR block
     * ------------------------------------------------------------
     *
     * All full-DMA status/counter inputs are tied inactive because
     * dma_core is intentionally absent from this first bitstream.
     *
     * scratch_write_pulse is fed back as a synthetic TX completion
     * event solely to prove the PL -> PS interrupt path.
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

        .global_status           (32'd0),

        /*
         * Bring-up-only synthetic event:
         * each SCRATCH write latches IRQ_STATUS[0].
         */
        .tx_completion_event     (scratch_write_pulse),
        .rx_completion_event     (1'b0),
        .tx_error_event          (1'b0),
        .rx_error_event          (1'b0),

        .irq_status              (irq_status),
        .irq_enable              (irq_enable),
        .irq                     (irq),

        .error_set               (32'd0),
        .error_info              (32'd0),
        .error_addr              (64'd0),
        .error_status            (error_status),

        .tx_enable               (tx_enable),
        .tx_halt                 (tx_halt),

        .tx_ring_base            (tx_ring_base),
        .tx_ring_size            (tx_ring_size),
        .tx_tail                 (tx_tail),
        .tx_cfg_load_pulse       (tx_cfg_load_pulse),

        .tx_status               (32'd0),
        .tx_head                 (32'd0),
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

        .rx_status               (32'd0),
        .rx_head                 (32'd0),
        .rx_bytes                (64'd0),
        .rx_desc_count           (32'd0),
        .rx_active_cycles        (64'd0),
        .rx_axi_stall            (64'd0),
        .rx_axis_stall           (64'd0),

        .scratch                 (scratch),
        .scratch_write_pulse     (scratch_write_pulse)
    );

endmodule
