`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * AXI4-Lite software-visible CSR block.
 *
 * Aperture: 4 KiB
 * Data width: 32 bits
 *
 * Important implementation rule:
 *
 * AXI-Lite AW and W channels are independent. Address and data are
 * captured separately and a write is executed only after both have
 * been accepted.
 */

module dma_axil_regs (
    input  logic        clk,
    input  logic        aresetn,

    /*
     * AXI4-Lite slave write address channel.
     */
    input  logic [11:0] s_axil_awaddr,
    input  logic [2:0]  s_axil_awprot,
    input  logic        s_axil_awvalid,
    output logic        s_axil_awready,

    /*
     * AXI4-Lite slave write data channel.
     */
    input  logic [31:0] s_axil_wdata,
    input  logic [3:0]  s_axil_wstrb,
    input  logic        s_axil_wvalid,
    output logic        s_axil_wready,

    /*
     * AXI4-Lite slave write response channel.
     */
    output logic [1:0]  s_axil_bresp,
    output logic        s_axil_bvalid,
    input  logic        s_axil_bready,

    /*
     * AXI4-Lite slave read address channel.
     */
    input  logic [11:0] s_axil_araddr,
    input  logic [2:0]  s_axil_arprot,
    input  logic        s_axil_arvalid,
    output logic        s_axil_arready,

    /*
     * AXI4-Lite slave read data channel.
     */
    output logic [31:0] s_axil_rdata,
    output logic [1:0]  s_axil_rresp,
    output logic        s_axil_rvalid,
    input  logic        s_axil_rready,

    /*
     * Global control/status.
     */
    output logic        global_enable,
    output logic        soft_reset_pulse,
    output logic        counter_clear_pulse,

    input  logic [31:0] global_status,

    /*
     * Interrupt event sources.
     */
    input  logic        tx_completion_event,
    input  logic        rx_completion_event,
    input  logic        tx_error_event,
    input  logic        rx_error_event,

    output logic [3:0]  irq_status,
    output logic [3:0]  irq_enable,
    output logic        irq,

    /*
     * Global error information.
     *
     * error_set is set-dominant against software RW1C clears.
     */
    input  logic [31:0] error_set,
    input  logic [31:0] error_info,
    input  logic [63:0] error_addr,

    output logic [31:0] error_status,

    /*
     * TX software configuration.
     */
    output logic        tx_enable,
    output logic        tx_halt,

    output logic [63:0] tx_ring_base,
    output logic [15:0] tx_ring_size,
    output logic [31:0] tx_tail,

    /*
     * Pulses when software commits TX/RX ring size.
     * Software shall program BASE before SIZE.
     */
    output logic        tx_cfg_load_pulse,

    input  logic [31:0] tx_status,
    input  logic [31:0] tx_head,

    input  logic [63:0] tx_bytes,
    input  logic [31:0] tx_desc_count,
    input  logic [63:0] tx_active_cycles,
    input  logic [63:0] tx_axi_stall,
    input  logic [63:0] tx_axis_stall,

    /*
     * RX software configuration.
     */
    output logic        rx_enable,
    output logic        rx_halt,

    output logic [63:0] rx_ring_base,
    output logic [15:0] rx_ring_size,
    output logic [31:0] rx_tail,

    output logic        rx_cfg_load_pulse,

    input  logic [31:0] rx_status,
    input  logic [31:0] rx_head,

    input  logic [63:0] rx_bytes,
    input  logic [31:0] rx_desc_count,
    input  logic [63:0] rx_active_cycles,
    input  logic [63:0] rx_axi_stall,
    input  logic [63:0] rx_axis_stall,

    /*
     * Physical bring-up scratch register.
     */
    output logic [31:0] scratch,
    output logic        scratch_write_pulse
);

    localparam logic [31:0] ID_VALUE =
        32'h4344_4D41;

    localparam logic [31:0] VERSION_VALUE =
        32'h0001_0000;

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;
    localparam logic [1:0] RESP_DECERR = 2'b11;

    /*
     * ------------------------------------------------------------
     * AXI-Lite write-channel capture
     * ------------------------------------------------------------
     */

    logic        aw_pending;
    logic [11:0] awaddr_reg;

    logic        w_pending;
    logic [31:0] wdata_reg;
    logic [3:0]  wstrb_reg;

    logic        bvalid_reg;
    logic [1:0]  bresp_reg;

    assign s_axil_awready =
        !aw_pending &&
        !bvalid_reg;

    assign s_axil_wready =
        !w_pending &&
        !bvalid_reg;

    assign s_axil_bvalid =
        bvalid_reg;

    assign s_axil_bresp =
        bresp_reg;

    /*
     * ------------------------------------------------------------
     * AXI-Lite read response holding register
     * ------------------------------------------------------------
     */

    logic        rvalid_reg;
    logic [31:0] rdata_reg;
    logic [1:0]  rresp_reg;

    assign s_axil_arready =
        !rvalid_reg;

    assign s_axil_rvalid =
        rvalid_reg;

    assign s_axil_rdata =
        rdata_reg;

    assign s_axil_rresp =
        rresp_reg;

    /*
     * ------------------------------------------------------------
     * Interrupt controller
     * ------------------------------------------------------------
     */

    logic [3:0] irq_enable_reg;
    logic [3:0] irq_clear_pulse;
    logic [3:0] irq_status_internal;

    dma_irq_controller irq_controller (
        .clk                 (clk),
        .aresetn             (aresetn),

        .tx_completion_event (tx_completion_event),
        .rx_completion_event (rx_completion_event),
        .tx_error_event      (tx_error_event),
        .rx_error_event      (rx_error_event),

        .irq_enable          (irq_enable_reg),
        .irq_clear           (irq_clear_pulse),

        .irq_status          (irq_status_internal),
        .irq                 (irq)
    );

    always_comb begin

        irq_enable =
            irq_enable_reg;

        irq_status =
            irq_status_internal;

    end

    /*
     * ------------------------------------------------------------
     * Global error latch
     * ------------------------------------------------------------
     */

    logic [31:0] error_clear_pulse;

    /*
     * ------------------------------------------------------------
     * Read decoder
     * ------------------------------------------------------------
     */

    logic [31:0] read_decode_data;
    logic [1:0]  read_decode_resp;

    always_comb begin

        read_decode_data =
            32'd0;

        read_decode_resp =
            RESP_OKAY;

        case (s_axil_araddr)

            12'h000:
                read_decode_data =
                    ID_VALUE;

            12'h004:
                read_decode_data =
                    VERSION_VALUE;

            12'h008:
                read_decode_data =
                    {
                        29'd0,
                        2'b00,
                        global_enable
                    };

            12'h00C:
                read_decode_data =
                    global_status;

            12'h010:
                read_decode_data =
                    {28'd0, irq_status_internal};

            12'h014:
                read_decode_data =
                    {28'd0, irq_enable_reg};

            12'h018:
                read_decode_data =
                    error_status;

            12'h01C:
                read_decode_data =
                    error_info;

            12'h020:
                read_decode_data =
                    error_addr[31:0];

            12'h024:
                read_decode_data =
                    error_addr[63:32];

            /*
             * TX
             */

            12'h100:
                read_decode_data =
                    {
                        30'd0,
                        tx_halt,
                        tx_enable
                    };

            12'h104:
                read_decode_data =
                    tx_status;

            12'h108:
                read_decode_data =
                    tx_ring_base[31:0];

            12'h10C:
                read_decode_data =
                    tx_ring_base[63:32];

            12'h110:
                read_decode_data =
                    {16'd0, tx_ring_size};

            12'h114:
                read_decode_data =
                    tx_tail;

            12'h118:
                read_decode_data =
                    tx_head;

            12'h11C:
                read_decode_data =
                    tx_bytes[31:0];

            12'h120:
                read_decode_data =
                    tx_bytes[63:32];

            12'h124:
                read_decode_data =
                    tx_desc_count;

            12'h128:
                read_decode_data =
                    tx_active_cycles[31:0];

            12'h12C:
                read_decode_data =
                    tx_active_cycles[63:32];

            12'h130:
                read_decode_data =
                    tx_axi_stall[31:0];

            12'h134:
                read_decode_data =
                    tx_axi_stall[63:32];

            12'h138:
                read_decode_data =
                    tx_axis_stall[31:0];

            12'h13C:
                read_decode_data =
                    tx_axis_stall[63:32];

            /*
             * RX
             */

            12'h200:
                read_decode_data =
                    {
                        30'd0,
                        rx_halt,
                        rx_enable
                    };

            12'h204:
                read_decode_data =
                    rx_status;

            12'h208:
                read_decode_data =
                    rx_ring_base[31:0];

            12'h20C:
                read_decode_data =
                    rx_ring_base[63:32];

            12'h210:
                read_decode_data =
                    {16'd0, rx_ring_size};

            12'h214:
                read_decode_data =
                    rx_tail;

            12'h218:
                read_decode_data =
                    rx_head;

            12'h21C:
                read_decode_data =
                    rx_bytes[31:0];

            12'h220:
                read_decode_data =
                    rx_bytes[63:32];

            12'h224:
                read_decode_data =
                    rx_desc_count;

            12'h228:
                read_decode_data =
                    rx_active_cycles[31:0];

            12'h22C:
                read_decode_data =
                    rx_active_cycles[63:32];

            12'h230:
                read_decode_data =
                    rx_axi_stall[31:0];

            12'h234:
                read_decode_data =
                    rx_axi_stall[63:32];

            12'h238:
                read_decode_data =
                    rx_axis_stall[31:0];

            12'h23C:
                read_decode_data =
                    rx_axis_stall[63:32];

            /*
             * Physical bring-up scratch.
             */
            12'h3FC:
                read_decode_data =
                    scratch;

            default: begin

                read_decode_data =
                    32'd0;

                read_decode_resp =
                    RESP_DECERR;

            end

        endcase

    end

    /*
     * Apply AXI byte write strobes to a 32-bit persistent register.
     */
    function automatic [31:0] apply_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strb
    );

        integer byte_number;
        logic [31:0] value;

        begin

            value =
                old_value;

            for (byte_number = 0;
                 byte_number < 4;
                 byte_number = byte_number + 1) begin

                if (strb[byte_number])
                    value[
                        byte_number*8 +: 8
                    ] =
                        new_value[
                            byte_number*8 +: 8
                        ];

            end

            apply_wstrb =
                value;

        end

    endfunction

    /*
     * ------------------------------------------------------------
     * Sequential control
     * ------------------------------------------------------------
     */

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            aw_pending <=
                1'b0;

            awaddr_reg <=
                12'd0;

            w_pending <=
                1'b0;

            wdata_reg <=
                32'd0;

            wstrb_reg <=
                4'd0;

            bvalid_reg <=
                1'b0;

            bresp_reg <=
                RESP_OKAY;

            rvalid_reg <=
                1'b0;

            rdata_reg <=
                32'd0;

            rresp_reg <=
                RESP_OKAY;

            global_enable <=
                1'b0;

            soft_reset_pulse <=
                1'b0;

            counter_clear_pulse <=
                1'b0;

            irq_enable_reg <=
                4'b0000;

            irq_clear_pulse <=
                4'b0000;

            error_status <=
                32'd0;

            error_clear_pulse <=
                32'd0;

            tx_enable <=
                1'b0;

            tx_halt <=
                1'b0;

            tx_ring_base <=
                64'd0;

            tx_ring_size <=
                16'd0;

            tx_tail <=
                32'd0;

            tx_cfg_load_pulse <=
                1'b0;

            rx_enable <=
                1'b0;

            rx_halt <=
                1'b0;

            rx_ring_base <=
                64'd0;

            rx_ring_size <=
                16'd0;

            rx_tail <=
                32'd0;

            rx_cfg_load_pulse <=
                1'b0;

            scratch <=
                32'd0;

            scratch_write_pulse <=
                1'b0;

        end
        else begin

            /*
             * One-cycle pulse defaults.
             */
            soft_reset_pulse <=
                1'b0;

            counter_clear_pulse <=
                1'b0;

            irq_clear_pulse <=
                4'b0000;

            error_clear_pulse <=
                32'd0;

            tx_cfg_load_pulse <=
                1'b0;

            rx_cfg_load_pulse <=
                1'b0;

            scratch_write_pulse <=
                1'b0;

            /*
             * Set-dominant global error status.
             *
             * error_clear_pulse was generated during the preceding
             * AXI-Lite write cycle.
             */
            error_status <=
                (error_status &
                 ~error_clear_pulse) |
                error_set;

            /*
             * --------------------------
             * Capture AW independently.
             * --------------------------
             */
            if (s_axil_awvalid &&
                s_axil_awready) begin

                aw_pending <=
                    1'b1;

                awaddr_reg <=
                    s_axil_awaddr;

            end

            /*
             * --------------------------
             * Capture W independently.
             * --------------------------
             */
            if (s_axil_wvalid &&
                s_axil_wready) begin

                w_pending <=
                    1'b1;

                wdata_reg <=
                    s_axil_wdata;

                wstrb_reg <=
                    s_axil_wstrb;

            end

            /*
             * Retire write response.
             */
            if (bvalid_reg &&
                s_axil_bready) begin

                bvalid_reg <=
                    1'b0;

            end

            /*
             * Execute one write only after both AW and W have
             * independently completed their handshakes.
             */
            if (aw_pending &&
                w_pending &&
                !bvalid_reg) begin

                bresp_reg <=
                    RESP_OKAY;

                case (awaddr_reg)

                    /*
                     * Read-only global registers.
                     */
                    12'h000,
                    12'h004,
                    12'h00C,
                    12'h01C,
                    12'h020,
                    12'h024:
                        bresp_reg <=
                            RESP_SLVERR;

                    /*
                     * GLOBAL_CONTROL
                     *
                     * bit0 is persistent.
                     * bits1/2 are write-one pulses.
                     */
                    12'h008: begin

                        if (wstrb_reg[0]) begin

                            global_enable <=
                                wdata_reg[0];

                            soft_reset_pulse <=
                                wdata_reg[1];

                            counter_clear_pulse <=
                                wdata_reg[2];

                        end

                    end

                    /*
                     * IRQ_STATUS - RW1C
                     */
                    12'h010: begin

                        if (wstrb_reg[0])
                            irq_clear_pulse <=
                                wdata_reg[3:0];

                    end

                    /*
                     * IRQ_ENABLE
                     */
                    12'h014: begin

                        if (wstrb_reg[0])
                            irq_enable_reg <=
                                wdata_reg[3:0];

                    end

                    /*
                     * ERROR_STATUS - RW1C
                     */
                    12'h018: begin

                        if (wstrb_reg[0])
                            error_clear_pulse[7:0] <=
                                wdata_reg[7:0];

                        if (wstrb_reg[1])
                            error_clear_pulse[15:8] <=
                                wdata_reg[15:8];

                        if (wstrb_reg[2])
                            error_clear_pulse[23:16] <=
                                wdata_reg[23:16];

                        if (wstrb_reg[3])
                            error_clear_pulse[31:24] <=
                                wdata_reg[31:24];

                    end

                    /*
                     * TX CONTROL
                     */
                    12'h100: begin

                        if (wstrb_reg[0]) begin

                            tx_enable <=
                                wdata_reg[0];

                            tx_halt <=
                                wdata_reg[1];

                        end

                    end

                    /*
                     * TX STATUS is read-only.
                     */
                    12'h104:
                        bresp_reg <=
                            RESP_SLVERR;

                    /*
                     * TX ring base.
                     */
                    12'h108:
                        tx_ring_base[31:0] <=
                            apply_wstrb(
                                tx_ring_base[31:0],
                                wdata_reg,
                                wstrb_reg
                            );

                    12'h10C:
                        tx_ring_base[63:32] <=
                            apply_wstrb(
                                tx_ring_base[63:32],
                                wdata_reg,
                                wstrb_reg
                            );

                    /*
                     * TX_RING_SIZE acts as the configuration commit
                     * register: software programs BASE first, then
                     * writes SIZE last.
                     */
                    12'h110: begin

                        if (wstrb_reg[0])
                            tx_ring_size[7:0] <=
                                wdata_reg[7:0];

                        if (wstrb_reg[1])
                            tx_ring_size[15:8] <=
                                wdata_reg[15:8];

                        tx_cfg_load_pulse <=
                            |wstrb_reg[1:0];

                    end

                    12'h114:
                        tx_tail <=
                            apply_wstrb(
                                tx_tail,
                                wdata_reg,
                                wstrb_reg
                            );

                    /*
                     * TX read-only state/counters.
                     */
                    12'h118,
                    12'h11C,
                    12'h120,
                    12'h124,
                    12'h128,
                    12'h12C,
                    12'h130,
                    12'h134,
                    12'h138,
                    12'h13C:
                        bresp_reg <=
                            RESP_SLVERR;

                    /*
                     * RX CONTROL
                     */
                    12'h200: begin

                        if (wstrb_reg[0]) begin

                            rx_enable <=
                                wdata_reg[0];

                            rx_halt <=
                                wdata_reg[1];

                        end

                    end

                    12'h204:
                        bresp_reg <=
                            RESP_SLVERR;

                    /*
                     * RX ring base.
                     */
                    12'h208:
                        rx_ring_base[31:0] <=
                            apply_wstrb(
                                rx_ring_base[31:0],
                                wdata_reg,
                                wstrb_reg
                            );

                    12'h20C:
                        rx_ring_base[63:32] <=
                            apply_wstrb(
                                rx_ring_base[63:32],
                                wdata_reg,
                                wstrb_reg
                            );

                    12'h210: begin

                        if (wstrb_reg[0])
                            rx_ring_size[7:0] <=
                                wdata_reg[7:0];

                        if (wstrb_reg[1])
                            rx_ring_size[15:8] <=
                                wdata_reg[15:8];

                        rx_cfg_load_pulse <=
                            |wstrb_reg[1:0];

                    end

                    12'h214:
                        rx_tail <=
                            apply_wstrb(
                                rx_tail,
                                wdata_reg,
                                wstrb_reg
                            );

                    /*
                     * RX read-only state/counters.
                     */
                    12'h218,
                    12'h21C,
                    12'h220,
                    12'h224,
                    12'h228,
                    12'h22C,
                    12'h230,
                    12'h234,
                    12'h238,
                    12'h23C:
                        bresp_reg <=
                            RESP_SLVERR;

                    /*
                     * SCRATCH
                     */
                    12'h3FC: begin

                        scratch <=
                            apply_wstrb(
                                scratch,
                                wdata_reg,
                                wstrb_reg
                            );

                        scratch_write_pulse <=
                            |wstrb_reg;

                    end

                    default:
                        bresp_reg <=
                            RESP_DECERR;

                endcase

                aw_pending <=
                    1'b0;

                w_pending <=
                    1'b0;

                bvalid_reg <=
                    1'b1;

            end

            /*
             * ----------------------------------------------------
             * AXI-Lite read
             * ----------------------------------------------------
             */

            if (s_axil_arvalid &&
                s_axil_arready) begin

                rdata_reg <=
                    read_decode_data;

                rresp_reg <=
                    read_decode_resp;

                rvalid_reg <=
                    1'b1;

            end
            else if (rvalid_reg &&
                     s_axil_rready) begin

                rvalid_reg <=
                    1'b0;

            end

        end

    end

endmodule
