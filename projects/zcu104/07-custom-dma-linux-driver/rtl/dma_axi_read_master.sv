`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * AXI4 memory-mapped read master.
 *
 * V1:
 *   - one request active at a time
 *   - one outstanding AXI read burst at a time
 *   - 64-bit AXI data width
 *   - aligned transfers only
 *   - request length multiple of 8 bytes
 *   - INCR bursts
 *   - automatic 4-KiB boundary splitting
 *   - explicit RRESP / RID / RLAST checking
 *   - downstream backpressure
 */

module dma_axi_read_master #(
    parameter integer ADDR_WIDTH       = 40,
    parameter integer LEN_WIDTH        = 32,
    parameter integer AXI_ID_WIDTH     = 4,
    parameter integer MAX_BURST_BEATS  = 256
)(
    input  logic                       clk,
    input  logic                       aresetn,

    /*
     * Internal read request.
     */
    input  logic                       req_valid,
    output logic                       req_ready,
    input  logic [ADDR_WIDTH-1:0]      req_addr,
    input  logic [LEN_WIDTH-1:0]       req_bytes,

    /*
     * Internal output stream.
     */
    output logic [63:0]                m_data,
    output logic [7:0]                 m_keep,
    output logic                       m_valid,
    input  logic                       m_ready,
    output logic                       m_last,

    /*
     * Completion interface.
     */
    output logic                       cpl_valid,
    input  logic                       cpl_ready,
    output logic                       cpl_error,
    output logic [3:0]                 cpl_error_code,
    output logic [LEN_WIDTH-1:0]       cpl_bytes,

    /*
     * AXI4 read-address channel.
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

    /*
     * AXI4 read-data channel.
     */
    input  logic [AXI_ID_WIDTH-1:0]    m_axi_rid,
    input  logic [63:0]                m_axi_rdata,
    input  logic [1:0]                 m_axi_rresp,
    input  logic                       m_axi_rlast,
    input  logic                       m_axi_rvalid,
    output logic                       m_axi_rready
);

    localparam logic [3:0] ERR_NONE        = 4'h0;
    localparam logic [3:0] ERR_REQUEST     = 4'h1;
    localparam logic [3:0] ERR_SLVERR      = 4'h2;
    localparam logic [3:0] ERR_DECERR      = 4'h3;
    localparam logic [3:0] ERR_EARLY_RLAST = 4'h4;
    localparam logic [3:0] ERR_LATE_RLAST  = 4'h5;
    localparam logic [3:0] ERR_RID          = 4'h6;
    localparam logic [3:0] ERR_PLANNER      = 4'h7;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_PLAN,
        ST_AR,
        ST_READ,
        ST_DRAIN,
        ST_CPL
    } state_t;

    state_t state;

    logic [ADDR_WIDTH-1:0] current_addr;
    logic [LEN_WIDTH-1:0]  bytes_remaining;
    logic [LEN_WIDTH-1:0]  bytes_delivered;

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

    logic expected_last;
    logic current_resp_error;
    logic current_rid_error;
    logic current_rlast_error;
    logic current_beat_error;

    always_comb begin

        expected_last =
            (beats_left == 9'd1);

        current_resp_error =
            (m_axi_rresp != 2'b00);

        current_rid_error =
            (m_axi_rid != {AXI_ID_WIDTH{1'b0}});

        current_rlast_error =
            (m_axi_rlast != expected_last);

        current_beat_error =
            m_axi_rvalid &&
            (
                current_resp_error  ||
                current_rid_error   ||
                current_rlast_error
            );
    end

    /*
     * Interface outputs.
     */
    always_comb begin

        req_ready = (state == ST_IDLE);

        m_axi_arid    = {AXI_ID_WIDTH{1'b0}};
        m_axi_araddr  = burst_addr_reg;
        m_axi_arlen   = burst_axlen_reg;
        m_axi_arsize  = 3'b011;  // 8 bytes
        m_axi_arburst = 2'b01;   // INCR
        m_axi_arlock  = 1'b0;
        m_axi_arcache = 4'b0011;
        m_axi_arprot  = 3'b000;
        m_axi_arqos   = 4'b0000;
        m_axi_arvalid = (state == ST_AR);

        m_data = m_axi_rdata;
        m_keep = 8'hFF;

        /*
         * Never deliver a beat that is already known
         * to contain an AXI/protocol error.
         */
        m_valid =
            (state == ST_READ) &&
            m_axi_rvalid &&
            !error_latched &&
            !current_beat_error;

        m_last =
            (state == ST_READ) &&
            expected_last &&
            final_burst_reg;

        /*
         * Normal data follows downstream backpressure.
         *
         * Once an error is known, the current AXI burst
         * must still be drained so the AXI channel cannot
         * deadlock.
         */
        if (state == ST_READ) begin
            if (error_latched || current_beat_error)
                m_axi_rready = 1'b1;
            else
                m_axi_rready = m_ready;
        end
        else if (state == ST_DRAIN) begin
            m_axi_rready = 1'b1;
        end
        else begin
            m_axi_rready = 1'b0;
        end

        cpl_valid      = (state == ST_CPL);
        cpl_error      = error_latched;
        cpl_error_code = error_code_reg;
        cpl_bytes      = bytes_delivered;
    end

    /*
     * Main control state machine.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            state             <= ST_IDLE;

            current_addr      <= '0;
            bytes_remaining   <= '0;
            bytes_delivered   <= '0;

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

                        bytes_delivered <= '0;
                        error_latched   <= 1'b0;
                        error_code_reg  <= ERR_NONE;

                        /*
                         * V1 request contract.
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

                        state <= ST_AR;
                    end
                end

                ST_AR: begin

                    if (m_axi_arvalid && m_axi_arready) begin

                        beats_left <= burst_beats_reg;
                        state      <= ST_READ;

                    end
                end

                ST_READ: begin

                    if (m_axi_rvalid && m_axi_rready) begin

                        /*
                         * Previous error already latched:
                         * continue draining the burst.
                         */
                        if (error_latched) begin

                            if (expected_last) begin

                                if (m_axi_rlast)
                                    state <= ST_CPL;
                                else
                                    state <= ST_DRAIN;

                            end
                            else if (m_axi_rlast) begin

                                state <= ST_CPL;

                            end
                            else begin

                                beats_left <= beats_left - 9'd1;

                            end
                        end

                        /*
                         * New error on this beat.
                         */
                        else if (current_beat_error) begin

                            error_latched <= 1'b1;

                            if (current_resp_error) begin

                                case (m_axi_rresp)
                                    2'b10:
                                        error_code_reg <= ERR_SLVERR;

                                    2'b11:
                                        error_code_reg <= ERR_DECERR;

                                    default:
                                        error_code_reg <= ERR_RID;
                                endcase

                            end
                            else if (current_rid_error) begin

                                error_code_reg <= ERR_RID;

                            end
                            else if (m_axi_rlast &&
                                     !expected_last) begin

                                error_code_reg <= ERR_EARLY_RLAST;

                            end
                            else begin

                                error_code_reg <= ERR_LATE_RLAST;

                            end

                            /*
                             * Early RLAST terminates the malformed
                             * burst immediately.
                             */
                            if (m_axi_rlast && !expected_last) begin

                                state <= ST_CPL;

                            end

                            /*
                             * Expected final beat arrived without
                             * RLAST. Drain until RLAST eventually
                             * appears.
                             */
                            else if (!m_axi_rlast &&
                                     expected_last) begin

                                state <= ST_DRAIN;

                            end

                            /*
                             * Error response on a correctly framed
                             * final beat.
                             */
                            else if (expected_last) begin

                                state <= ST_CPL;

                            end
                            else begin

                                beats_left <= beats_left - 9'd1;

                            end
                        end

                        /*
                         * Correct beat.
                         */
                        else begin

                            bytes_delivered <=
                                bytes_delivered +
                                {{(LEN_WIDTH-4){1'b0}}, 4'd8};

                            if (expected_last) begin

                                /*
                                 * RLAST correctness already checked.
                                 */
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
                            else begin

                                beats_left <= beats_left - 9'd1;

                            end
                        end
                    end
                end

                ST_DRAIN: begin

                    /*
                     * Used after a missing expected RLAST.
                     * Discard everything until the slave finally
                     * terminates the malformed burst.
                     */
                    if (m_axi_rvalid &&
                        m_axi_rready &&
                        m_axi_rlast) begin

                        state <= ST_CPL;

                    end
                end

                ST_CPL: begin

                    if (cpl_valid && cpl_ready)
                        state <= ST_IDLE;

                end

                default: begin

                    state          <= ST_CPL;
                    error_latched  <= 1'b1;
                    error_code_reg <= ERR_PLANNER;

                end

            endcase
        end
    end

endmodule
