`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * AXI4 memory-mapped write master.
 *
 * V1:
 *   - one request active at a time
 *   - one outstanding AXI write burst at a time
 *   - 64-bit AXI data width
 *   - aligned transfers only
 *   - request length multiple of 8 bytes
 *   - INCR bursts
 *   - automatic 4-KiB boundary splitting
 *   - AW/W independently backpressured
 *   - explicit BRESP / BID checking
 */

module dma_axi_write_master #(
    parameter integer ADDR_WIDTH       = 40,
    parameter integer LEN_WIDTH        = 32,
    parameter integer AXI_ID_WIDTH     = 4,
    parameter integer MAX_BURST_BEATS  = 256
)(
    input  logic                       clk,
    input  logic                       aresetn,

    /*
     * Internal write request.
     */
    input  logic                       req_valid,
    output logic                       req_ready,
    input  logic [ADDR_WIDTH-1:0]      req_addr,
    input  logic [LEN_WIDTH-1:0]       req_bytes,

    /*
     * Internal write-data stream.
     *
     * V1 contract:
     *   one 64-bit beat per accepted transfer beat.
     */
    input  logic [63:0]                s_data,
    input  logic [7:0]                 s_keep,
    input  logic                       s_valid,
    output logic                       s_ready,

    /*
     * Completion.
     */
    output logic                       cpl_valid,
    input  logic                       cpl_ready,
    output logic                       cpl_error,
    output logic [3:0]                 cpl_error_code,
    output logic [LEN_WIDTH-1:0]       cpl_bytes,

    /*
     * AXI4 write-address channel.
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

    /*
     * AXI4 write-data channel.
     */
    output logic [63:0]                m_axi_wdata,
    output logic [7:0]                 m_axi_wstrb,
    output logic                       m_axi_wlast,
    output logic                       m_axi_wvalid,
    input  logic                       m_axi_wready,

    /*
     * AXI4 write-response channel.
     */
    input  logic [AXI_ID_WIDTH-1:0]    m_axi_bid,
    input  logic [1:0]                 m_axi_bresp,
    input  logic                       m_axi_bvalid,
    output logic                       m_axi_bready
);

    localparam logic [3:0] ERR_NONE    = 4'h0;
    localparam logic [3:0] ERR_REQUEST = 4'h1;
    localparam logic [3:0] ERR_SLVERR  = 4'h2;
    localparam logic [3:0] ERR_DECERR  = 4'h3;
    localparam logic [3:0] ERR_BID     = 4'h4;
    localparam logic [3:0] ERR_PLANNER = 4'h5;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_PLAN,
        ST_AW,
        ST_WRITE,
        ST_BRESP,
        ST_CPL
    } state_t;

    state_t state;

    logic [ADDR_WIDTH-1:0] current_addr;
    logic [LEN_WIDTH-1:0]  bytes_remaining;
    logic [LEN_WIDTH-1:0]  bytes_committed;

    logic [ADDR_WIDTH-1:0] burst_addr_reg;
    logic [8:0]            burst_beats_reg;
    logic [12:0]           burst_bytes_reg;
    logic [7:0]            burst_axlen_reg;
    logic                  final_burst_reg;

    logic [8:0]            beats_left;

    logic                  error_latched;
    logic [3:0]            error_code_reg;

    /*
     * Burst planner.
     */
    logic                  planner_valid;
    logic                  planner_error;
    logic [ADDR_WIDTH-1:0] planner_addr;
    logic [8:0]            planner_beats;
    logic [12:0]           planner_bytes;
    logic [7:0]            planner_axlen;

    localparam logic [8:0] MAX_BURST_W = MAX_BURST_BEATS;

    dma_burst_planner #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .LEN_WIDTH  (LEN_WIDTH)
    ) burst_planner (
        .current_addr     (current_addr),
        .bytes_remaining  (bytes_remaining),
        .max_burst_beats  (MAX_BURST_W),

        .plan_valid       (planner_valid),
        .plan_error       (planner_error),

        .burst_addr       (planner_addr),
        .burst_beats      (planner_beats),
        .burst_bytes      (planner_bytes),
        .axi_len          (planner_axlen)
    );

    logic expected_last_beat;

    always_comb begin
        expected_last_beat = (beats_left == 9'd1);
    end

    /*
     * Interface outputs.
     */
    always_comb begin

        req_ready = (state == ST_IDLE);

        m_axi_awid    = {AXI_ID_WIDTH{1'b0}};
        m_axi_awaddr  = burst_addr_reg;
        m_axi_awlen   = burst_axlen_reg;
        m_axi_awsize  = 3'b011;  // 8 bytes
        m_axi_awburst = 2'b01;   // INCR
        m_axi_awlock  = 1'b0;
        m_axi_awcache = 4'b0011;
        m_axi_awprot  = 3'b000;
        m_axi_awqos   = 4'b0000;
        m_axi_awvalid = (state == ST_AW);

        /*
         * Write data is directly backpressured by AXI.
         *
         * The upstream internal producer must obey the same
         * VALID stability rule as AXI:
         *
         * while s_valid && !s_ready,
         * s_data and s_keep remain stable.
         */
        m_axi_wdata  = s_data;
        m_axi_wstrb  = s_keep;
        m_axi_wvalid = (state == ST_WRITE) && s_valid;
        m_axi_wlast  = (state == ST_WRITE) &&
                       expected_last_beat;

        s_ready = (state == ST_WRITE) &&
                  m_axi_wready;

        m_axi_bready = (state == ST_BRESP);

        cpl_valid      = (state == ST_CPL);
        cpl_error      = error_latched;
        cpl_error_code = error_code_reg;
        cpl_bytes      = bytes_committed;
    end

    /*
     * Main state machine.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            state             <= ST_IDLE;

            current_addr      <= '0;
            bytes_remaining   <= '0;
            bytes_committed   <= '0;

            burst_addr_reg    <= '0;
            burst_beats_reg   <= '0;
            burst_bytes_reg   <= '0;
            burst_axlen_reg   <= '0;
            final_burst_reg   <= 1'b0;

            beats_left        <= '0;

            error_latched     <= 1'b0;
            error_code_reg    <= ERR_NONE;

        end
        else begin

            case (state)

                ST_IDLE: begin

                    if (req_valid && req_ready) begin

                        bytes_committed <= '0;
                        error_latched   <= 1'b0;
                        error_code_reg  <= ERR_NONE;

                        /*
                         * V1 aligned-request contract.
                         */
                        if ((req_bytes == 0) ||
                            (req_addr[2:0] != 3'b000) ||
                            (req_bytes[2:0] != 3'b000)) begin

                            error_latched  <= 1'b1;
                            error_code_reg <= ERR_REQUEST;
                            state          <= ST_CPL;

                        end
                        else begin

                            current_addr    <= req_addr;
                            bytes_remaining <= req_bytes;
                            state           <= ST_PLAN;

                        end
                    end
                end

                ST_PLAN: begin

                    if (planner_error || !planner_valid) begin

                        error_latched  <= 1'b1;
                        error_code_reg <= ERR_PLANNER;
                        state          <= ST_CPL;

                    end
                    else begin

                        burst_addr_reg  <= planner_addr;
                        burst_beats_reg <= planner_beats;
                        burst_bytes_reg <= planner_bytes;
                        burst_axlen_reg <= planner_axlen;

                        final_burst_reg <=
                            (planner_bytes == bytes_remaining);

                        state <= ST_AW;
                    end
                end

                ST_AW: begin

                    if (m_axi_awvalid &&
                        m_axi_awready) begin

                        beats_left <= burst_beats_reg;
                        state      <= ST_WRITE;

                    end
                end

                ST_WRITE: begin

                    if (m_axi_wvalid &&
                        m_axi_wready) begin

                        if (expected_last_beat) begin

                            /*
                             * Do not count this burst as committed
                             * until its B response is successful.
                             */
                            state <= ST_BRESP;

                        end
                        else begin

                            beats_left <= beats_left - 9'd1;

                        end
                    end
                end

                ST_BRESP: begin

                    if (m_axi_bvalid &&
                        m_axi_bready) begin

                        if (m_axi_bid !=
                            {AXI_ID_WIDTH{1'b0}}) begin

                            error_latched  <= 1'b1;
                            error_code_reg <= ERR_BID;
                            state          <= ST_CPL;

                        end
                        else if (m_axi_bresp != 2'b00) begin

                            error_latched <= 1'b1;

                            if (m_axi_bresp == 2'b10)
                                error_code_reg <= ERR_SLVERR;
                            else if (m_axi_bresp == 2'b11)
                                error_code_reg <= ERR_DECERR;
                            else
                                error_code_reg <= ERR_SLVERR;

                            state <= ST_CPL;

                        end
                        else begin

                            /*
                             * BRESP OKAY means the entire burst
                             * is now considered committed.
                             */
                            bytes_committed <=
                                bytes_committed +
                                burst_bytes_reg;

                            if (final_burst_reg) begin

                                state <= ST_CPL;

                            end
                            else begin

                                current_addr <=
                                    current_addr +
                                    burst_bytes_reg;

                                bytes_remaining <=
                                    bytes_remaining -
                                    burst_bytes_reg;

                                state <= ST_PLAN;

                            end
                        end
                    end
                end

                ST_CPL: begin

                    if (cpl_valid &&
                        cpl_ready)
                        state <= ST_IDLE;

                end

                default: begin

                    error_latched  <= 1'b1;
                    error_code_reg <= ERR_PLANNER;
                    state          <= ST_CPL;

                end

            endcase
        end
    end

endmodule
