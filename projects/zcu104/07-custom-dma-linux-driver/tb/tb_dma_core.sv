`timescale 1ns/1ps

module tb_dma_core;

    localparam integer MEM_BYTES = 131072;

    localparam logic [39:0] TX_RING = 40'h0000_1000;
    localparam logic [39:0] RX_RING = 40'h0000_2000;

    localparam logic [39:0] TX_BUF  = 40'h0000_4000;
    localparam logic [39:0] RX_BUF  = 40'h0000_8000;

    localparam integer TX_BYTES = 4096;

`ifdef GATE4A_RX64
    localparam integer RX_BYTES = 64;
    localparam integer EXPECTED_AXI_WRITES = 5;
`else
    localparam integer RX_BYTES = 4096;
    localparam integer EXPECTED_AXI_WRITES = 6;
`endif

    localparam logic [63:0] TX_COOKIE =
        64'h5458_0000_0000_0001;

    localparam logic [63:0] RX_COOKIE =
        64'h5258_0000_0000_0001;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn;

    /*
     * ------------------------------------------------------------
     * Ring controls
     * ------------------------------------------------------------
     */

    logic        tx_cfg_load;
    logic [63:0] tx_ring_base;
    logic [15:0] tx_ring_size;
    logic [31:0] tx_sw_tail;

    logic        tx_config_valid;
    logic [3:0]  tx_config_error_code;
    logic [31:0] tx_hw_head;
    logic [31:0] tx_pending_count;
    logic        tx_ring_empty;
    logic        tx_ring_overrun;

    logic        tx_fault_valid;
    logic        tx_fault_clear;
    logic [3:0]  tx_fault_code;

    logic        tx_completion_pulse;
    logic        tx_completion_irq_requested;
    logic [63:0] tx_completion_cookie;
    logic [31:0] tx_completion_status;
    logic [31:0] tx_completion_actual_length;

    logic        rx_cfg_load;
    logic [63:0] rx_ring_base;
    logic [15:0] rx_ring_size;
    logic [31:0] rx_sw_tail;

    logic        rx_config_valid;
    logic [3:0]  rx_config_error_code;
    logic [31:0] rx_hw_head;
    logic [31:0] rx_pending_count;
    logic        rx_ring_empty;
    logic        rx_ring_overrun;

    logic        rx_fault_valid;
    logic        rx_fault_clear;
    logic [3:0]  rx_fault_code;

    logic        rx_completion_pulse;
    logic        rx_completion_irq_requested;
    logic [63:0] rx_completion_cookie;
    logic [31:0] rx_completion_status;
    logic [31:0] rx_completion_actual_length;

    /*
     * ------------------------------------------------------------
     * Streams
     * ------------------------------------------------------------
     */

    logic [63:0] m_axis_tx_tdata;
    logic [7:0]  m_axis_tx_tkeep;
    logic        m_axis_tx_tvalid;
    logic        m_axis_tx_tready;
    logic        m_axis_tx_tlast;

    logic [63:0] s_axis_rx_tdata;
    logic [7:0]  s_axis_rx_tkeep;
    logic        s_axis_rx_tvalid;
    logic        s_axis_rx_tready;
    logic        s_axis_rx_tlast;

    /*
     * ------------------------------------------------------------
     * AXI memory interface
     * ------------------------------------------------------------
     */

    logic [3:0]  m_axi_arid;
    logic [39:0] m_axi_araddr;
    logic [7:0]  m_axi_arlen;
    logic [2:0]  m_axi_arsize;
    logic [1:0]  m_axi_arburst;
    logic        m_axi_arlock;
    logic [3:0]  m_axi_arcache;
    logic [2:0]  m_axi_arprot;
    logic [3:0]  m_axi_arqos;
    logic        m_axi_arvalid;
    logic        m_axi_arready;

    logic [3:0]  m_axi_rid;
    logic [63:0] m_axi_rdata;
    logic [1:0]  m_axi_rresp;
    logic        m_axi_rlast;
    logic        m_axi_rvalid;
    logic        m_axi_rready;

    logic [3:0]  m_axi_awid;
    logic [39:0] m_axi_awaddr;
    logic [7:0]  m_axi_awlen;
    logic [2:0]  m_axi_awsize;
    logic [1:0]  m_axi_awburst;
    logic        m_axi_awlock;
    logic [3:0]  m_axi_awcache;
    logic [2:0]  m_axi_awprot;
    logic [3:0]  m_axi_awqos;
    logic        m_axi_awvalid;
    logic        m_axi_awready;

    logic [63:0] m_axi_wdata;
    logic [7:0]  m_axi_wstrb;
    logic        m_axi_wlast;
    logic        m_axi_wvalid;
    logic        m_axi_wready;

    logic [3:0]  m_axi_bid;
    logic [1:0]  m_axi_bresp;
    logic        m_axi_bvalid;
    logic        m_axi_bready;

    dma_core dut (
        .clk                       (clk),
        .aresetn                   (aresetn),

        .tx_cfg_load               (tx_cfg_load),
        .tx_ring_base              (tx_ring_base),
        .tx_ring_size              (tx_ring_size),
        .tx_sw_tail                (tx_sw_tail),

        .tx_config_valid           (tx_config_valid),
        .tx_config_error_code      (tx_config_error_code),
        .tx_hw_head                (tx_hw_head),
        .tx_pending_count          (tx_pending_count),
        .tx_ring_empty             (tx_ring_empty),
        .tx_ring_overrun           (tx_ring_overrun),

        .tx_fault_valid            (tx_fault_valid),
        .tx_fault_clear            (tx_fault_clear),
        .tx_fault_code             (tx_fault_code),

        .tx_completion_pulse       (tx_completion_pulse),
        .tx_completion_irq_requested
                                    (tx_completion_irq_requested),
        .tx_completion_cookie      (tx_completion_cookie),
        .tx_completion_status      (tx_completion_status),
        .tx_completion_actual_length
                                    (tx_completion_actual_length),

        .rx_cfg_load               (rx_cfg_load),
        .rx_ring_base              (rx_ring_base),
        .rx_ring_size              (rx_ring_size),
        .rx_sw_tail                (rx_sw_tail),

        .rx_config_valid           (rx_config_valid),
        .rx_config_error_code      (rx_config_error_code),
        .rx_hw_head                (rx_hw_head),
        .rx_pending_count          (rx_pending_count),
        .rx_ring_empty             (rx_ring_empty),
        .rx_ring_overrun           (rx_ring_overrun),

        .rx_fault_valid            (rx_fault_valid),
        .rx_fault_clear            (rx_fault_clear),
        .rx_fault_code             (rx_fault_code),

        .rx_completion_pulse       (rx_completion_pulse),
        .rx_completion_irq_requested
                                    (rx_completion_irq_requested),
        .rx_completion_cookie      (rx_completion_cookie),
        .rx_completion_status      (rx_completion_status),
        .rx_completion_actual_length
                                    (rx_completion_actual_length),

        .m_axis_tx_tdata           (m_axis_tx_tdata),
        .m_axis_tx_tkeep           (m_axis_tx_tkeep),
        .m_axis_tx_tvalid          (m_axis_tx_tvalid),
        .m_axis_tx_tready          (m_axis_tx_tready),
        .m_axis_tx_tlast           (m_axis_tx_tlast),

        .s_axis_rx_tdata           (s_axis_rx_tdata),
        .s_axis_rx_tkeep           (s_axis_rx_tkeep),
        .s_axis_rx_tvalid          (s_axis_rx_tvalid),
        .s_axis_rx_tready          (s_axis_rx_tready),
        .s_axis_rx_tlast           (s_axis_rx_tlast),

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

    /*
     * ------------------------------------------------------------
     * Shared byte-addressable DDR model
     * ------------------------------------------------------------
     */

    logic [7:0] mem [0:MEM_BYTES-1];

    task automatic mem_write64(
        input integer address,
        input logic [63:0] value
    );

        integer n;

        begin

            for (n = 0; n < 8; n = n + 1)
                mem[address + n] =
                    value[n*8 +: 8];

        end

    endtask

    function automatic [63:0] mem_read64(
        input logic [39:0] address
    );

        integer n;

        begin

            mem_read64 = 64'd0;

            for (n = 0; n < 8; n = n + 1)
                mem_read64[n*8 +: 8] =
                    mem[address[16:0] + n];

        end

    endfunction

    function automatic [63:0] tx_pattern(
        input integer offset
    );

        begin

            tx_pattern =
                64'hA100_0000_0000_0000 ^
                (offset >> 3);

        end

    endfunction

    function automatic [63:0] rx_pattern(
        input integer offset
    );

        begin

`ifdef GATE4A_RX64

            case (offset)

                0:
                    rx_pattern =
                        64'h22222222_11111111;

                8:
                    rx_pattern =
                        64'h44444444_33333333;

                16:
                    rx_pattern =
                        64'h66666666_55555555;

                24:
                    rx_pattern =
                        64'h88888888_77777777;

                32:
                    rx_pattern =
                        64'hAAAAAAAA_99999999;

                40:
                    rx_pattern =
                        64'hCCCCCCCC_BBBBBBBB;

                48:
                    rx_pattern =
                        64'hEEEEEEEE_DDDDDDDD;

                56:
                    rx_pattern =
                        64'h12345678_FFFFFFFF;

                default:
                    rx_pattern =
                        64'hDEAD_DEAD_DEAD_DEAD;

            endcase

`else

            rx_pattern =
                64'hB200_0000_0000_0000 ^
                (offset >> 3);

`endif

        end

    endfunction

    task automatic write_descriptor(
        input integer      address,
        input logic [63:0] buffer_addr,
        input logic [31:0] length,
        input logic [31:0] control,
        input logic [63:0] cookie
    );

        begin

            mem_write64(
                address + 16'h00,
                buffer_addr
            );

            mem_write64(
                address + 16'h08,
                {control, length}
            );

            mem_write64(
                address + 16'h10,
                cookie
            );

            mem_write64(
                address + 16'h18,
                64'd0
            );

            mem_write64(address + 16'h20, 64'd0);
            mem_write64(address + 16'h28, 64'd0);
            mem_write64(address + 16'h30, 64'd0);
            mem_write64(address + 16'h38, 64'd0);

        end

    endtask

    /*
     * ------------------------------------------------------------
     * Deterministic pseudo-random backpressure
     * ------------------------------------------------------------
     */

    logic [31:0] lfsr;

    always_ff @(posedge clk) begin

        if (!aresetn)
            lfsr <= 32'hD74A_21C9;
        else
            lfsr <= {
                lfsr[30:0],
                lfsr[31] ^
                lfsr[21] ^
                lfsr[1] ^
                lfsr[0]
            };

    end

    /*
     * ------------------------------------------------------------
     * AXI READ slave
     * ------------------------------------------------------------
     */

    logic        rd_active;
    logic [39:0] rd_base;
    integer      rd_beats;
    integer      rd_index;

    integer ar_count;

    assign m_axi_arready =
        !rd_active &&
        !m_axi_rvalid &&
        (lfsr[1] | lfsr[6]);

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            rd_active <= 1'b0;
            rd_base   <= 40'd0;
            rd_beats  <= 0;
            rd_index  <= 0;

            m_axi_rid    <= 4'd0;
            m_axi_rdata  <= 64'd0;
            m_axi_rresp  <= 2'b00;
            m_axi_rlast  <= 1'b0;
            m_axi_rvalid <= 1'b0;

            ar_count <= 0;

        end
        else begin

            if (m_axi_arvalid &&
                m_axi_arready) begin

                if (m_axi_arid !== 4'd0 ||
                    m_axi_arsize !== 3'b011 ||
                    m_axi_arburst !== 2'b01) begin

                    $display(
                        "FAIL: integrated AXI read attributes"
                    );
                    $fatal;

                end

                if ((m_axi_araddr[11:0] +
                    ((m_axi_arlen + 1) * 8)) >
                    4096) begin

                    $display(
                        "FAIL: integrated AXI read crossed 4-KiB"
                    );
                    $fatal;

                end

                rd_active <= 1'b1;
                rd_base   <= m_axi_araddr;
                rd_beats  <= m_axi_arlen + 1;
                rd_index  <= 0;

                ar_count <= ar_count + 1;

            end

            /*
             * Random RVALID gaps.
             */
            if (rd_active &&
                !m_axi_rvalid &&
                (lfsr[2] | lfsr[7])) begin

                m_axi_rid <= 4'd0;

                m_axi_rdata <=
                    mem_read64(
                        rd_base +
                        (rd_index * 8)
                    );

                m_axi_rresp <=
                    2'b00;

                m_axi_rlast <=
                    (rd_index ==
                     (rd_beats - 1));

                m_axi_rvalid <=
                    1'b1;

            end

            if (m_axi_rvalid &&
                m_axi_rready) begin

                if (m_axi_rlast) begin

                    rd_active <=
                        1'b0;

                end
                else begin

                    rd_index <=
                        rd_index + 1;

                end

                m_axi_rvalid <=
                    1'b0;

            end

        end

    end

    /*
     * ------------------------------------------------------------
     * AXI WRITE slave
     * ------------------------------------------------------------
     */

    logic        wr_active;
    logic [39:0] wr_base;
    integer      wr_beats;
    integer      wr_index;

    logic        b_pending;
    integer      b_delay;

    integer aw_count;
    integer b_count;
    integer byte_index;

    assign m_axi_awready =
        !wr_active &&
        !b_pending &&
        !m_axi_bvalid &&
        (lfsr[3] | lfsr[8]);

    assign m_axi_wready =
        wr_active &&
        (lfsr[5] | lfsr[10]);

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            wr_active <= 1'b0;
            wr_base   <= 40'd0;
            wr_beats  <= 0;
            wr_index  <= 0;

            b_pending <= 1'b0;
            b_delay   <= 0;

            m_axi_bid    <= 4'd0;
            m_axi_bresp  <= 2'b00;
            m_axi_bvalid <= 1'b0;

            aw_count <= 0;
            b_count  <= 0;

        end
        else begin

            if (m_axi_awvalid &&
                m_axi_awready) begin

                if (m_axi_awid !== 4'd0 ||
                    m_axi_awsize !== 3'b011 ||
                    m_axi_awburst !== 2'b01) begin

                    $display(
                        "FAIL: integrated AXI write attributes"
                    );
                    $fatal;

                end

                if ((m_axi_awaddr[11:0] +
                    ((m_axi_awlen + 1) * 8)) >
                    4096) begin

                    $display(
                        "FAIL: integrated AXI write crossed 4-KiB"
                    );
                    $fatal;

                end

                wr_active <=
                    1'b1;

                wr_base <=
                    m_axi_awaddr;

                wr_beats <=
                    m_axi_awlen + 1;

                wr_index <=
                    0;

                aw_count <=
                    aw_count + 1;

            end

            if (m_axi_wvalid &&
                m_axi_wready) begin

                if (!wr_active) begin

                    $display(
                        "FAIL: integrated W without AW"
                    );
                    $fatal;

                end

                if (m_axi_wlast !==
                    (wr_index ==
                     (wr_beats - 1))) begin

                    $display(
                        "FAIL: integrated WLAST"
                    );
                    $fatal;

                end

                for (byte_index = 0;
                     byte_index < 8;
                     byte_index = byte_index + 1) begin

                    if (m_axi_wstrb[byte_index]) begin

                        mem[
                            wr_base[16:0] +
                            (wr_index * 8) +
                            byte_index
                        ] <=
                            m_axi_wdata[
                                byte_index*8 +: 8
                            ];

                    end

                end

                if (wr_index ==
                    (wr_beats - 1)) begin

                    wr_active <=
                        1'b0;

                    b_pending <=
                        1'b1;

                    b_delay <=
                        1 + lfsr[12:11];

                end
                else begin

                    wr_index <=
                        wr_index + 1;

                end

            end

            if (b_pending &&
                !m_axi_bvalid) begin

                if (b_delay != 0) begin

                    b_delay <=
                        b_delay - 1;

                end
                else begin

                    m_axi_bid <=
                        4'd0;

                    m_axi_bresp <=
                        2'b00;

                    m_axi_bvalid <=
                        1'b1;

                    b_pending <=
                        1'b0;

                end

            end

            if (m_axi_bvalid &&
                m_axi_bready) begin

                m_axi_bvalid <=
                    1'b0;

                b_count <=
                    b_count + 1;

            end

        end

    end

    /*
     * ------------------------------------------------------------
     * TX stream sink
     * ------------------------------------------------------------
     */

    integer tx_seen;
    logic   tx_stream_done;

    assign m_axis_tx_tready =
        lfsr[4] | lfsr[9];

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            tx_seen        <= 0;
            tx_stream_done <= 1'b0;

        end
        else if (m_axis_tx_tvalid &&
                 m_axis_tx_tready) begin

            if (m_axis_tx_tdata !==
                tx_pattern(tx_seen)) begin

                $display(
                    "FAIL TX CORE DATA offset=%0d got=%h expected=%h",
                    tx_seen,
                    m_axis_tx_tdata,
                    tx_pattern(tx_seen)
                );

                $fatal;

            end

            if (m_axis_tx_tkeep !==
                8'hFF) begin

                $display(
                    "FAIL: integrated TX TKEEP"
                );
                $fatal;

            end

            if (m_axis_tx_tlast !==
                ((tx_seen + 8) ==
                 TX_BYTES)) begin

                $display(
                    "FAIL: integrated TX TLAST at offset %0d",
                    tx_seen
                );
                $fatal;

            end

            tx_seen <=
                tx_seen + 8;

            if (m_axis_tx_tlast)
                tx_stream_done <=
                    1'b1;

        end

    end

    /*
     * ------------------------------------------------------------
     * RX stream source
     * ------------------------------------------------------------
     */

    logic rx_source_done;

    task automatic send_rx_packet;

        integer offset;

        begin

            offset = 0;

            /*
             * Start RX only once the TX payload stream has appeared.
             * This deliberately forces overlap between the two
             * active DMA channels.
             */
            wait (m_axis_tx_tvalid);

            while (offset < RX_BYTES) begin

                /*
                 * After the first beat, inject deterministic
                 * source-side gaps.
                 */
                if (offset != 0) begin

                    while (!(lfsr[13] |
                             lfsr[17]))
                        @(posedge clk);

                end

                @(negedge clk);

                s_axis_rx_tdata =
                    rx_pattern(offset);

                s_axis_rx_tkeep =
                    8'hFF;

                s_axis_rx_tlast =
                    ((offset + 8) ==
                     RX_BYTES);

                s_axis_rx_tvalid =
                    1'b1;

                do begin
                    @(posedge clk);
                end while (!s_axis_rx_tready);

                @(negedge clk);

                s_axis_rx_tvalid =
                    1'b0;

                offset =
                    offset + 8;

            end

            s_axis_rx_tlast =
                1'b0;

            rx_source_done =
                1'b1;

        end

    endtask

    /*
     * ------------------------------------------------------------
     * System-level monitors
     * ------------------------------------------------------------
     */

    integer tx_completion_count;
    integer rx_completion_count;

    logic [63:0] tx_seen_cookie;
    logic [31:0] tx_seen_status;
    logic [31:0] tx_seen_actual;
    logic        tx_seen_irq;

    logic [63:0] rx_seen_cookie;
    logic [31:0] rx_seen_status;
    logic [31:0] rx_seen_actual;
    logic        rx_seen_irq;

    logic both_pending_seen;
    logic concurrent_stream_seen;
    logic concurrent_axi_rw_seen;

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            tx_completion_count <= 0;
            rx_completion_count <= 0;

            tx_seen_cookie <= 64'd0;
            tx_seen_status <= 32'd0;
            tx_seen_actual <= 32'd0;
            tx_seen_irq    <= 1'b0;

            rx_seen_cookie <= 64'd0;
            rx_seen_status <= 32'd0;
            rx_seen_actual <= 32'd0;
            rx_seen_irq    <= 1'b0;

            both_pending_seen    <= 1'b0;
            concurrent_stream_seen <= 1'b0;
            concurrent_axi_rw_seen <= 1'b0;

        end
        else begin

            if ((tx_pending_count != 0) &&
                (rx_pending_count != 0))
                both_pending_seen <=
                    1'b1;

            if (m_axis_tx_tvalid &&
                m_axis_tx_tready &&
                s_axis_rx_tvalid &&
                s_axis_rx_tready)
                concurrent_stream_seen <=
                    1'b1;

            if ((m_axi_rvalid &&
                 m_axi_rready) &&
                (m_axi_wvalid &&
                 m_axi_wready))
                concurrent_axi_rw_seen <=
                    1'b1;

            if (tx_completion_pulse) begin

                tx_completion_count <=
                    tx_completion_count + 1;

                tx_seen_cookie <=
                    tx_completion_cookie;

                tx_seen_status <=
                    tx_completion_status;

                tx_seen_actual <=
                    tx_completion_actual_length;

                tx_seen_irq <=
                    tx_completion_irq_requested;

            end

            if (rx_completion_pulse) begin

                rx_completion_count <=
                    rx_completion_count + 1;

                rx_seen_cookie <=
                    rx_completion_cookie;

                rx_seen_status <=
                    rx_completion_status;

                rx_seen_actual <=
                    rx_completion_actual_length;

                rx_seen_irq <=
                    rx_completion_irq_requested;

            end

        end

    end

    task automatic verify_rx_memory;

        integer offset;

        begin

            for (offset = 0;
                 offset < RX_BYTES;
                 offset = offset + 8) begin

                if (mem_read64(
                        RX_BUF + offset
                    ) !==
                    rx_pattern(offset)) begin

                    $display(
                        "FAIL RX CORE DDR offset=%0d got=%h expected=%h",
                        offset,
                        mem_read64(
                            RX_BUF + offset
                        ),
                        rx_pattern(offset)
                    );

                    $fatal;

                end

            end

        end

    endtask

    integer i;
    integer offset;

    initial begin

        /*
         * --------------------------------------------------------
         * Memory initialization
         * --------------------------------------------------------
         */

        for (i = 0;
             i < MEM_BYTES;
             i = i + 1)
            mem[i] = 8'd0;

        /*
         * TX descriptor:
         * OWN=1, IRQ=1, EOP=1
         */
        write_descriptor(
            TX_RING,
            TX_BUF,
            TX_BYTES,
            32'h0000_0007,
            TX_COOKIE
        );

        /*
         * RX descriptor.
         */
        write_descriptor(
            RX_RING,
            RX_BUF,
            RX_BYTES,
            32'h0000_0007,
            RX_COOKIE
        );

        /*
         * TX source payload in DDR.
         */
        for (offset = 0;
             offset < TX_BYTES;
             offset = offset + 8)
            mem_write64(
                TX_BUF + offset,
                tx_pattern(offset)
            );

        /*
         * --------------------------------------------------------
         * Initial interface state
         * --------------------------------------------------------
         */

        aresetn =
            1'b0;

        tx_cfg_load =
            1'b0;

        tx_ring_base =
            TX_RING;

        tx_ring_size =
            16;

        tx_sw_tail =
            0;

        tx_fault_clear =
            1'b0;

        rx_cfg_load =
            1'b0;

        rx_ring_base =
            RX_RING;

        rx_ring_size =
            16;

        rx_sw_tail =
            0;

        rx_fault_clear =
            1'b0;

        s_axis_rx_tdata =
            64'd0;

        s_axis_rx_tkeep =
            8'hFF;

        s_axis_rx_tvalid =
            1'b0;

        s_axis_rx_tlast =
            1'b0;

        rx_source_done =
            1'b0;

        repeat (12)
            @(posedge clk);

        aresetn =
            1'b1;

        repeat (4)
            @(posedge clk);

        /*
         * Configure both rings together.
         */
        @(negedge clk);

        tx_cfg_load =
            1'b1;

        rx_cfg_load =
            1'b1;

        @(posedge clk);
        @(negedge clk);

        tx_cfg_load =
            1'b0;

        rx_cfg_load =
            1'b0;

        repeat (2)
            @(posedge clk);

        if (!tx_config_valid ||
            tx_config_error_code != 0) begin

            $display(
                "FAIL: TX ring configuration"
            );
            $fatal;

        end

        if (!rx_config_valid ||
            rx_config_error_code != 0) begin

            $display(
                "FAIL: RX ring configuration"
            );
            $fatal;

        end

        $display(
            "DUAL RING CONFIGURATION: PASS"
        );

        /*
         * Publish one descriptor to each channel simultaneously.
         */
        @(negedge clk);

        tx_sw_tail =
            32'd1;

        rx_sw_tail =
            32'd1;

        /*
         * RX packet source operates concurrently with TX.
         */
        fork
            send_rx_packet();
        join_none

        /*
         * Wait until both descriptor heads retire.
         */
        while ((tx_hw_head != 1) ||
               (rx_hw_head != 1))
            @(posedge clk);

        /*
         * Allow final NBA/writeback effects to settle.
         */
        repeat (4)
            @(posedge clk);

        /*
         * --------------------------------------------------------
         * Final system checks
         * --------------------------------------------------------
         */

        if (tx_fault_valid) begin

            $display(
                "FAIL: TX descriptor fault code=%0d",
                tx_fault_code
            );
            $fatal;

        end

        if (rx_fault_valid) begin

            $display(
                "FAIL: RX descriptor fault code=%0d",
                rx_fault_code
            );
            $fatal;

        end

        if (!tx_stream_done ||
            tx_seen != TX_BYTES) begin

            $display(
                "FAIL TX stream bytes=%0d expected=%0d",
                tx_seen,
                TX_BYTES
            );
            $fatal;

        end

        if (!rx_source_done) begin

            $display(
                "FAIL: RX source packet did not complete"
            );
            $fatal;

        end

        verify_rx_memory();

        $display(
            "CONCURRENT TX/RX PAYLOAD MOVEMENT: PASS"
        );

        /*
         * Exactly one completion per descriptor.
         */
        if (tx_completion_count != 1 ||
            rx_completion_count != 1) begin

            $display(
                "FAIL completion counts TX=%0d RX=%0d",
                tx_completion_count,
                rx_completion_count
            );
            $fatal;

        end

        if (tx_seen_cookie !== TX_COOKIE ||
            tx_seen_status !== 32'h0000_0001 ||
            tx_seen_actual !== TX_BYTES ||
            !tx_seen_irq) begin

            $display(
                "FAIL TX completion metadata"
            );
            $fatal;

        end

        if (rx_seen_cookie !== RX_COOKIE ||
            rx_seen_status !== 32'h0000_0001 ||
            rx_seen_actual !== RX_BYTES ||
            !rx_seen_irq) begin

            $display(
                "FAIL RX completion metadata"
            );
            $fatal;

        end

        $display(
            "DUAL DESCRIPTOR COMPLETION EVENTS: PASS"
        );

        /*
         * STATUS + ACTUAL_LENGTH writeback.
         */
        if (mem_read64(
                TX_RING + 40'h18
            ) !==
            {32'd4096, 32'h0000_0001}) begin

            $display(
                "FAIL TX descriptor STATUS writeback got=%h",
                mem_read64(TX_RING + 40'h18)
            );
            $fatal;

        end

        if (mem_read64(
                RX_RING + 40'h18
            ) !==
            {RX_BYTES, 32'h0000_0001}) begin

            $display(
                "FAIL RX descriptor STATUS writeback got=%h",
                mem_read64(RX_RING + 40'h18)
            );
            $fatal;

        end

        /*
         * LENGTH remains unchanged and OWN is cleared:
         *
         * original CONTROL = 0x7
         * retired CONTROL  = 0x6
         */
        if (mem_read64(
                TX_RING + 40'h08
            ) !==
            {32'h0000_0006, 32'd4096}) begin

            $display(
                "FAIL TX descriptor OWN release got=%h",
                mem_read64(TX_RING + 40'h08)
            );
            $fatal;

        end

        if (mem_read64(
                RX_RING + 40'h08
            ) !==
            {32'h0000_0006, RX_BYTES}) begin

            $display(
                "FAIL RX descriptor OWN release got=%h",
                mem_read64(RX_RING + 40'h08)
            );
            $fatal;

        end

        $display(
            "DUAL DESCRIPTOR WRITEBACK / OWN RELEASE: PASS"
        );

        /*
         * HEAD is the authoritative retirement boundary.
         */
        if (tx_hw_head != 1 ||
            rx_hw_head != 1 ||
            tx_pending_count != 0 ||
            rx_pending_count != 0 ||
            !tx_ring_empty ||
            !rx_ring_empty) begin

            $display(
                "FAIL final ring state TX_HEAD=%0d RX_HEAD=%0d",
                tx_hw_head,
                rx_hw_head
            );
            $fatal;

        end

        $display(
            "DUAL HEAD ADVANCEMENT: PASS"
        );

        /*
         * Both channels were simultaneously pending and their stream
         * datapaths overlapped during the campaign.
         */
        if (!both_pending_seen) begin

            $display(
                "FAIL: TX/RX were never simultaneously pending"
            );
            $fatal;

        end

        if (!concurrent_stream_seen) begin

            $display(
                "FAIL: TX/RX stream handshakes never overlapped"
            );
            $fatal;

        end

        /*
         * Read and write AXI channels are independent. With long
         * concurrent payloads, at least one simultaneous read/write
         * data handshake must have occurred.
         */
        if (!concurrent_axi_rw_seen) begin

            $display(
                "FAIL: no concurrent AXI read/write activity observed"
            );
            $fatal;

        end

        $display(
            "TRUE BIDIRECTIONAL CONCURRENCY: PASS"
        );

        /*
         * Expected AXI bursts:
         *
         * READ:
         *   TX descriptor = 1
         *   RX descriptor = 1
         *   TX payload 4096B = 2 x 2048B
         *                 TOTAL = 4
         *
         * WRITE:
         *   RX payload = 2 x 2048B
         *   TX descriptor STATUS + OWN = 2
         *   RX descriptor STATUS + OWN = 2
         *                 TOTAL = 6
         */
        if (ar_count != 4) begin

            $display(
                "FAIL AXI AR count=%0d expected=4",
                ar_count
            );
            $fatal;

        end

        if (aw_count != EXPECTED_AXI_WRITES ||
            b_count != EXPECTED_AXI_WRITES) begin

            $display(
                "FAIL AXI write counts AW=%0d B=%0d expected=%0d",
                aw_count,
                b_count,
                EXPECTED_AXI_WRITES
            );
            $fatal;

        end

        $display(
            "SHARED MEMORY TRANSACTION ACCOUNTING: PASS"
        );

        $display("");
        $display("====================================================");
        $display(" INTEGRATED BIDIRECTIONAL DMA CORE: PASS");

`ifdef GATE4A_RX64
        $display(" GATE 4A 64-BYTE RX INTEGRATION: PASS");
`endif
        $display(" TX descriptor DDR fetch             : PASS");
        $display(" RX descriptor DDR fetch             : PASS");
        $display(" descriptor parser/ring integration  : PASS");
        $display(" TX DDR -> AXIS payload              : PASS");
        $display(" RX AXIS -> DDR payload              : PASS");
        $display(" exact TX payload ordering           : PASS");
        $display(" exact RX payload ordering           : PASS");
        $display(" randomized AXI backpressure         : PASS");
        $display(" randomized TX sink backpressure     : PASS");
        $display(" shared read arbitration             : PASS");
        $display(" shared write arbitration            : PASS");
        $display(" simultaneous TX/RX pending work     : PASS");
        $display(" overlapping TX/RX stream traffic    : PASS");
        $display(" concurrent AXI read/write traffic   : PASS");
        $display(" descriptor STATUS writeback         : PASS");
        $display(" descriptor OWN release              : PASS");
        $display(" authoritative HEAD advancement      : PASS");
        $display(" IRQ completion metadata             : PASS");
        $display(" no TX/RX payload corruption         : PASS");
        $display("====================================================");

        $finish;

    end

    /*
     * System-level deadlock watchdog.
     */
    initial begin

        #50_000_000;

        $display(
            "FAIL: integrated DMA core timeout / possible deadlock"
        );

        $fatal;

    end

endmodule
