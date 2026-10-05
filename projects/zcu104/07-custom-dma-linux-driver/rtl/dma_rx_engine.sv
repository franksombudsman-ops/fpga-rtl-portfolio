`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * RX payload engine.
 *
 * Moves:
 *
 *      AXI4-Stream -> DDR
 *
 * through dma_axi_write_master.
 *
 * V1:
 *   - 64-bit payload datapath
 *   - aligned destination buffers
 *   - descriptor LENGTH is receive-buffer capacity
 *   - packet may terminate before capacity using TLAST
 *   - TKEEP must be 8'hFF
 *   - 256-beat / 2048-byte staging chunk
 *   - descriptor-capacity overflow is explicit
 *   - overflow/error residue is drained through TLAST
 */

module dma_rx_engine #(
    parameter integer ADDR_WIDTH        = 40,
    parameter integer LEN_WIDTH         = 32,
    parameter integer CHUNK_BEATS       = 256
)(
    input  logic                     clk,
    input  logic                     aresetn,

    /*
     * Descriptor work.
     */
    input  logic                     work_valid,
    output logic                     work_ready,

    input  logic [63:0]              work_buffer_addr,
    input  logic [31:0]              work_length,
    input  logic [31:0]              work_control,
    input  logic [63:0]              work_cookie,
    input  logic                     work_irq_on_completion,
    input  logic                     work_end_of_packet,

    /*
     * Descriptor retirement.
     */
    output logic                     retire_valid,
    input  logic                     retire_ready,

    output logic [31:0]              retire_status,
    output logic [31:0]              retire_actual_length,

    /*
     * AXI4-Stream RX input.
     */
    input  logic [63:0]              s_axis_tdata,
    input  logic [7:0]               s_axis_tkeep,
    input  logic                     s_axis_tvalid,
    output logic                     s_axis_tready,
    input  logic                     s_axis_tlast,

    /*
     * Internal interface to dma_axi_write_master.
     */
    output logic                     wr_req_valid,
    input  logic                     wr_req_ready,
    output logic [ADDR_WIDTH-1:0]    wr_req_addr,
    output logic [LEN_WIDTH-1:0]     wr_req_bytes,

    output logic [63:0]              wr_data,
    output logic [7:0]               wr_keep,
    output logic                     wr_data_valid,
    input  logic                     wr_data_ready,

    input  logic                     wr_cpl_valid,
    output logic                     wr_cpl_ready,
    input  logic                     wr_cpl_error,
    input  logic [3:0]               wr_cpl_error_code,
    input  logic [LEN_WIDTH-1:0]     wr_cpl_bytes
);

    /*
     * Descriptor STATUS:
     *
     * bit 0 COMPLETE
     * bit 1 ERROR
     * bit 3 AXI_WRITE_ERROR
     * bit 4 ALIGNMENT_ERROR
     * bit 5 LENGTH_ERROR
     * bit 6 ADDRESS_ERROR
     * bit 7 RX_OVERFLOW
     * bit 8 RX_LENGTH_MISMATCH
     * bit 9 INTERNAL_ERROR
     */

    localparam logic [31:0] STATUS_SUCCESS =
        32'h0000_0001;

    localparam logic [31:0] STATUS_AXI_WRITE_ERROR =
        32'h0000_000B;

    localparam logic [31:0] STATUS_RX_OVERFLOW =
        32'h0000_0083;

    localparam logic [31:0] STATUS_RX_LENGTH_MISMATCH =
        32'h0000_0103;

    localparam logic [31:0] STATUS_INTERNAL_ERROR =
        32'h0000_0203;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_RECV,
        ST_WRITE_REQ,
        ST_WRITE_DATA,
        ST_WRITE_CPL,
        ST_DRAIN,
        ST_RETIRE
    } state_t;

    typedef enum logic [1:0] {
        ACT_CONTINUE,
        ACT_RETIRE_SUCCESS,
        ACT_RETIRE_ERROR,
        ACT_DRAIN_ERROR
    } action_t;

    state_t  state;
    action_t post_write_action;

    /*
     * 256 x 64 = 2048-byte staging chunk.
     *
     * Synthesis implementation/inference will be audited later.
     * No BRAM-utilization claim is made at RTL verification stage.
     */
    logic [63:0] chunk_buffer [0:CHUNK_BEATS-1];

    logic [8:0] buffer_count;
    logic [8:0] chunk_beats_reg;
    logic [8:0] send_index;

    logic [12:0] chunk_bytes_reg;

    logic [63:0] active_buffer_addr;
    logic [31:0] active_capacity;

    logic [31:0] bytes_received;
    logic [31:0] bytes_committed;

    logic [31:0] terminal_error_status;

    logic [31:0] result_status;
    logic [31:0] result_actual_length;

    logic work_addr_range_error;
    logic work_invalid;

    generate

        if (ADDR_WIDTH < 64) begin : g_addr_range

            always_comb begin
                work_addr_range_error =
                    |work_buffer_addr[63:ADDR_WIDTH];
            end

        end
        else begin : g_full_addr

            always_comb begin
                work_addr_range_error = 1'b0;
            end

        end

    endgenerate

    always_comb begin

        work_invalid =
            (work_buffer_addr[2:0] != 3'b000) ||
            (work_length == 0) ||
            (work_length[2:0] != 3'b000) ||
            work_addr_range_error;

    end

    function automatic [31:0] validation_status(
        input logic [63:0] addr,
        input logic [31:0] length,
        input logic        addr_range_error
    );

        logic [31:0] status;

        begin

            status = 32'd0;

            status[0] = 1'b1;
            status[1] = 1'b1;

            if (addr[2:0] != 3'b000)
                status[4] = 1'b1;

            if ((length == 0) ||
                (length[2:0] != 3'b000))
                status[5] = 1'b1;

            if (addr_range_error)
                status[6] = 1'b1;

            validation_status = status;

        end

    endfunction

    /*
     * Interfaces.
     */
    always_comb begin

        work_ready =
            (state == ST_IDLE);

        /*
         * Receive only while:
         *
         *   - collecting a packet;
         *   - chunk buffer has room;
         *   - descriptor capacity has not already been consumed.
         */
        s_axis_tready =
            (state == ST_RECV) &&
            (buffer_count < CHUNK_BEATS) &&
            (bytes_received < active_capacity);

        wr_req_valid =
            (state == ST_WRITE_REQ);

        /*
         * bytes_committed is LEN_WIDTH bits (32 in V1).
         * It is unsigned and is therefore zero-extended to the
         * AXI address width for destination-address generation.
         */
        wr_req_addr =
            active_buffer_addr[ADDR_WIDTH-1:0] +
            bytes_committed;

        wr_req_bytes =
            {{(LEN_WIDTH-13){1'b0}},
             chunk_bytes_reg};

        wr_data =
            chunk_buffer[send_index];

        wr_keep =
            8'hFF;

        wr_data_valid =
            (state == ST_WRITE_DATA);

        wr_cpl_ready =
            (state == ST_WRITE_CPL);

        /*
         * Once an overflow or malformed stream has been detected,
         * consume and discard residue until TLAST so the next
         * descriptor begins on a packet boundary.
         *
         * This discard is explicit/error-reported, never silent.
         */
        if (state == ST_DRAIN)
            s_axis_tready = 1'b1;

        retire_valid =
            (state == ST_RETIRE);

        retire_status =
            result_status;

        retire_actual_length =
            result_actual_length;

    end

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            state <= ST_IDLE;

            post_write_action <= ACT_CONTINUE;

            buffer_count    <= 9'd0;
            chunk_beats_reg <= 9'd0;
            send_index      <= 9'd0;
            chunk_bytes_reg <= 13'd0;

            active_buffer_addr <= 64'd0;
            active_capacity    <= 32'd0;

            bytes_received  <= 32'd0;
            bytes_committed <= 32'd0;

            terminal_error_status <= 32'd0;

            result_status        <= 32'd0;
            result_actual_length <= 32'd0;

        end
        else begin

            case (state)

                ST_IDLE: begin

                    if (work_valid &&
                        work_ready) begin

                        active_buffer_addr <=
                            work_buffer_addr;

                        active_capacity <=
                            work_length;

                        buffer_count <=
                            9'd0;

                        bytes_received <=
                            32'd0;

                        bytes_committed <=
                            32'd0;

                        terminal_error_status <=
                            32'd0;

                        if (work_invalid) begin

                            result_status <=
                                validation_status(
                                    work_buffer_addr,
                                    work_length,
                                    work_addr_range_error
                                );

                            result_actual_length <=
                                32'd0;

                            state <= ST_RETIRE;

                        end
                        else begin

                            state <= ST_RECV;

                        end

                    end

                end

                ST_RECV: begin

                    if (s_axis_tvalid &&
                        s_axis_tready) begin

                        /*
                         * V1 accepts only complete 64-bit beats.
                         */
                        if (s_axis_tkeep != 8'hFF) begin

                            terminal_error_status <=
                                STATUS_RX_LENGTH_MISMATCH;

                            /*
                             * Do not commit the malformed beat.
                             * Any valid prefix already staged is
                             * still written to DDR.
                             */
                            if (buffer_count != 0) begin

                                chunk_beats_reg <=
                                    buffer_count;

                                chunk_bytes_reg <=
                                    buffer_count << 3;

                                send_index <=
                                    9'd0;

                                if (s_axis_tlast)
                                    post_write_action <=
                                        ACT_RETIRE_ERROR;
                                else
                                    post_write_action <=
                                        ACT_DRAIN_ERROR;

                                state <= ST_WRITE_REQ;

                            end
                            else begin

                                result_status <=
                                    STATUS_RX_LENGTH_MISMATCH;

                                result_actual_length <=
                                    bytes_committed;

                                if (s_axis_tlast)
                                    state <= ST_RETIRE;
                                else
                                    state <= ST_DRAIN;

                            end

                        end
                        else begin

                            /*
                             * Store the accepted payload beat.
                             */
                            chunk_buffer[buffer_count] <=
                                s_axis_tdata;

                            bytes_received <=
                                bytes_received +
                                32'd8;

                            /*
                             * Packet terminates normally.
                             */
                            if (s_axis_tlast) begin

                                chunk_beats_reg <=
                                    buffer_count +
                                    9'd1;

                                chunk_bytes_reg <=
                                    (buffer_count + 9'd1)
                                    << 3;

                                send_index <=
                                    9'd0;

                                post_write_action <=
                                    ACT_RETIRE_SUCCESS;

                                state <=
                                    ST_WRITE_REQ;

                            end

                            /*
                             * Descriptor capacity reached without
                             * TLAST. The accepted prefix is valid,
                             * but the packet is larger than the
                             * supplied RX buffer.
                             */
                            else if ((bytes_received + 32'd8) ==
                                     active_capacity) begin

                                chunk_beats_reg <=
                                    buffer_count +
                                    9'd1;

                                chunk_bytes_reg <=
                                    (buffer_count + 9'd1)
                                    << 3;

                                send_index <=
                                    9'd0;

                                terminal_error_status <=
                                    STATUS_RX_OVERFLOW;

                                post_write_action <=
                                    ACT_DRAIN_ERROR;

                                state <=
                                    ST_WRITE_REQ;

                            end

                            /*
                             * Staging chunk full.
                             */
                            else if ((buffer_count + 9'd1) ==
                                     CHUNK_BEATS) begin

                                chunk_beats_reg <=
                                    CHUNK_BEATS;

                                chunk_bytes_reg <=
                                    CHUNK_BEATS << 3;

                                send_index <=
                                    9'd0;

                                post_write_action <=
                                    ACT_CONTINUE;

                                state <=
                                    ST_WRITE_REQ;

                            end
                            else begin

                                buffer_count <=
                                    buffer_count +
                                    9'd1;

                            end

                        end

                    end

                end

                ST_WRITE_REQ: begin

                    if (wr_req_valid &&
                        wr_req_ready) begin

                        send_index <=
                            9'd0;

                        state <=
                            ST_WRITE_DATA;

                    end

                end

                ST_WRITE_DATA: begin

                    if (wr_data_valid &&
                        wr_data_ready) begin

                        if (send_index ==
                            (chunk_beats_reg - 9'd1)) begin

                            state <=
                                ST_WRITE_CPL;

                        end
                        else begin

                            send_index <=
                                send_index +
                                9'd1;

                        end

                    end

                end

                ST_WRITE_CPL: begin

                    if (wr_cpl_valid &&
                        wr_cpl_ready) begin

                        /*
                         * A failed BRESP does not imply rollback.
                         * Only bytes covered by successful write
                         * responses are reported as known-good.
                         */
                        if (wr_cpl_error) begin

                            result_status <=
                                STATUS_AXI_WRITE_ERROR;

                            result_actual_length <=
                                bytes_committed +
                                wr_cpl_bytes;

                            /*
                             * If packet termination has not yet been
                             * consumed, drain the remaining AXIS
                             * packet before allowing a new descriptor.
                             */
                            if ((post_write_action ==
                                 ACT_CONTINUE) ||
                                (post_write_action ==
                                 ACT_DRAIN_ERROR)) begin

                                state <=
                                    ST_DRAIN;

                            end
                            else begin

                                state <=
                                    ST_RETIRE;

                            end

                        end
                        else begin

                            bytes_committed <=
                                bytes_committed +
                                chunk_bytes_reg;

                            case (post_write_action)

                                ACT_CONTINUE: begin

                                    buffer_count <=
                                        9'd0;

                                    state <=
                                        ST_RECV;

                                end

                                ACT_RETIRE_SUCCESS: begin

                                    result_status <=
                                        STATUS_SUCCESS;

                                    result_actual_length <=
                                        bytes_committed +
                                        chunk_bytes_reg;

                                    state <=
                                        ST_RETIRE;

                                end

                                ACT_RETIRE_ERROR: begin

                                    result_status <=
                                        terminal_error_status;

                                    result_actual_length <=
                                        bytes_committed +
                                        chunk_bytes_reg;

                                    state <=
                                        ST_RETIRE;

                                end

                                ACT_DRAIN_ERROR: begin

                                    result_status <=
                                        terminal_error_status;

                                    result_actual_length <=
                                        bytes_committed +
                                        chunk_bytes_reg;

                                    state <=
                                        ST_DRAIN;

                                end

                                default: begin

                                    result_status <=
                                        STATUS_INTERNAL_ERROR;

                                    result_actual_length <=
                                        bytes_committed +
                                        chunk_bytes_reg;

                                    state <=
                                        ST_RETIRE;

                                end

                            endcase

                        end

                    end

                end

                ST_DRAIN: begin

                    /*
                     * Discard only because an explicit RX error has
                     * already been recorded. This restores packet
                     * alignment for the next descriptor.
                     */
                    if (s_axis_tvalid &&
                        s_axis_tready &&
                        s_axis_tlast) begin

                        state <=
                            ST_RETIRE;

                    end

                end

                ST_RETIRE: begin

                    if (retire_valid &&
                        retire_ready) begin

                        state <=
                            ST_IDLE;

                    end

                end

                default: begin

                    result_status <=
                        STATUS_INTERNAL_ERROR;

                    result_actual_length <=
                        bytes_committed;

                    state <=
                        ST_RETIRE;

                end

            endcase

        end

    end

endmodule
