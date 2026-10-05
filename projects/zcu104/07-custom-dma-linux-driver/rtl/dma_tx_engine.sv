`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * TX payload engine.
 *
 * Moves:
 *
 *      DDR -> AXI4-Stream
 *
 * through dma_axi_read_master.
 *
 * V1:
 *   - 64-bit payload datapath
 *   - aligned buffer addresses
 *   - transfer length multiple of 8 bytes
 *   - one descriptor active at a time
 *   - one descriptor maps to one AXIS packet
 *   - TLAST on final descriptor beat
 *   - payload errors retire descriptor explicitly as ERROR
 */

module dma_tx_engine #(
    parameter integer ADDR_WIDTH = 40,
    parameter integer LEN_WIDTH  = 32
)(
    input  logic                     clk,
    input  logic                     aresetn,

    /*
     * Descriptor work interface.
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
     * AXI4-Stream TX output.
     */
    output logic [63:0]              m_axis_tdata,
    output logic [7:0]               m_axis_tkeep,
    output logic                     m_axis_tvalid,
    input  logic                     m_axis_tready,
    output logic                     m_axis_tlast,

    /*
     * Internal interface to dma_axi_read_master.
     */
    output logic                     rd_req_valid,
    input  logic                     rd_req_ready,
    output logic [ADDR_WIDTH-1:0]    rd_req_addr,
    output logic [LEN_WIDTH-1:0]     rd_req_bytes,

    input  logic [63:0]              rd_data,
    input  logic [7:0]               rd_data_keep,
    input  logic                     rd_data_valid,
    output logic                     rd_data_ready,
    input  logic                     rd_data_last,

    input  logic                     rd_cpl_valid,
    output logic                     rd_cpl_ready,
    input  logic                     rd_cpl_error,
    input  logic [3:0]               rd_cpl_error_code,
    input  logic [LEN_WIDTH-1:0]     rd_cpl_bytes
);

    /*
     * Descriptor STATUS bits used here:
     *
     * bit 0 COMPLETE
     * bit 1 ERROR
     * bit 2 AXI_READ_ERROR
     * bit 4 ALIGNMENT_ERROR
     * bit 5 LENGTH_ERROR
     * bit 6 ADDRESS_ERROR
     * bit 9 INTERNAL_ERROR
     */

    localparam logic [31:0] STATUS_SUCCESS =
        32'h0000_0001;

    localparam logic [31:0] STATUS_AXI_READ_ERROR =
        32'h0000_0007;

    localparam logic [31:0] STATUS_INTERNAL_ERROR =
        32'h0000_0203;

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_READ_REQ,
        ST_STREAM,
        ST_RETIRE
    } state_t;

    state_t state;

    logic [63:0] active_buffer_addr;
    logic [31:0] active_length;

    logic [31:0] bytes_forwarded;
    logic        saw_last;

    logic [31:0] result_status;
    logic [31:0] result_actual_length;

    logic work_addr_range_error;

    generate

        if (ADDR_WIDTH < 64) begin : g_work_addr_range

            always_comb begin
                work_addr_range_error =
                    |work_buffer_addr[63:ADDR_WIDTH];
            end

        end
        else begin : g_work_full_addr

            always_comb begin
                work_addr_range_error = 1'b0;
            end

        end

    endgenerate

    /*
     * Create an explicit completion status for a malformed
     * work request. The descriptor parser should normally
     * prevent these from reaching the TX engine, but this
     * block remains defensive when verified independently.
     */
    function automatic [31:0] validation_status(
        input logic [63:0] addr,
        input logic [31:0] length,
        input logic        address_range_error
    );

        logic [31:0] status;

        begin

            status = 32'd0;

            status[0] = 1'b1;  // COMPLETE
            status[1] = 1'b1;  // ERROR

            if (addr[2:0] != 3'b000)
                status[4] = 1'b1;

            if ((length == 0) ||
                (length[2:0] != 3'b000))
                status[5] = 1'b1;

            if (address_range_error)
                status[6] = 1'b1;

            validation_status = status;

        end

    endfunction

    logic work_invalid;

    always_comb begin

        work_invalid =
            (work_buffer_addr[2:0] != 3'b000) ||
            (work_length == 0) ||
            (work_length[2:0] != 3'b000) ||
            work_addr_range_error;

    end

    /*
     * Interface control.
     */
    always_comb begin

        work_ready =
            (state == ST_IDLE);

        /*
         * One accepted descriptor becomes one read request.
         * dma_axi_read_master performs burst splitting.
         */
        rd_req_valid =
            (state == ST_READ_REQ);

        rd_req_addr =
            active_buffer_addr[ADDR_WIDTH-1:0];

        rd_req_bytes =
            active_length[LEN_WIDTH-1:0];

        /*
         * Direct streaming path:
         *
         * dma_axi_read_master already obeys the rule that its
         * output remains stable while VALID && !READY.
         */
        m_axis_tdata =
            rd_data;

        m_axis_tkeep =
            rd_data_keep;

        m_axis_tvalid =
            (state == ST_STREAM) &&
            rd_data_valid;

        m_axis_tlast =
            (state == ST_STREAM) &&
            rd_data_last;

        rd_data_ready =
            (state == ST_STREAM) &&
            m_axis_tready;

        /*
         * Read completion cannot occur until the read master has
         * finished/drained the AXI request.
         */
        rd_cpl_ready =
            (state == ST_STREAM);

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

            active_buffer_addr <= 64'd0;
            active_length      <= 32'd0;

            bytes_forwarded <= 32'd0;
            saw_last        <= 1'b0;

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

                        active_length <=
                            work_length;

                        bytes_forwarded <=
                            32'd0;

                        saw_last <=
                            1'b0;

                        /*
                         * Defensive work-contract validation.
                         */
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

                            state <= ST_READ_REQ;

                        end

                    end

                end

                ST_READ_REQ: begin

                    if (rd_req_valid &&
                        rd_req_ready) begin

                        state <= ST_STREAM;

                    end

                end

                ST_STREAM: begin

                    /*
                     * Count only payload actually accepted by
                     * the AXI4-Stream consumer.
                     */
                    if (m_axis_tvalid &&
                        m_axis_tready) begin

                        bytes_forwarded <=
                            bytes_forwarded +
                            32'd8;

                        if (m_axis_tlast)
                            saw_last <= 1'b1;

                    end

                    /*
                     * Completion comes after the read master has
                     * completed or terminated the memory request.
                     */
                    if (rd_cpl_valid &&
                        rd_cpl_ready) begin

                        if (rd_cpl_error) begin

                            result_status <=
                                STATUS_AXI_READ_ERROR;

                            result_actual_length <=
                                rd_cpl_bytes;

                        end
                        else if ((rd_cpl_bytes != active_length) ||
                                 (bytes_forwarded != active_length) ||
                                 !saw_last) begin

                            /*
                             * Internal accounting mismatch:
                             * never report such a transfer as success.
                             */
                            result_status <=
                                STATUS_INTERNAL_ERROR;

                            result_actual_length <=
                                rd_cpl_bytes;

                        end
                        else begin

                            result_status <=
                                STATUS_SUCCESS;

                            result_actual_length <=
                                active_length;

                        end

                        state <= ST_RETIRE;

                    end

                end

                ST_RETIRE: begin

                    if (retire_valid &&
                        retire_ready) begin

                        state <= ST_IDLE;

                    end

                end

                default: begin

                    result_status <=
                        STATUS_INTERNAL_ERROR;

                    result_actual_length <=
                        bytes_forwarded;

                    state <= ST_RETIRE;

                end

            endcase

        end

    end

endmodule
