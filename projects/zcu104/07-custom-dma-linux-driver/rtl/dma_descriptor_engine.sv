`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * Descriptor fetch / dispatch / retirement engine.
 *
 * Key ownership rule:
 *
 *   HEAD advances only after:
 *
 *     descriptor fetch
 *     -> validation
 *     -> payload retirement
 *     -> STATUS/ACTUAL_LENGTH writeback succeeds
 *     -> OWN-clear write succeeds
 *     -> HEAD++
 *
 * A descriptor is never returned to software before completion
 * information has been committed.
 */

module dma_descriptor_engine #(
    parameter integer ADDR_WIDTH = 40,
    parameter integer LEN_WIDTH  = 32
)(
    input  logic                     clk,
    input  logic                     aresetn,

    /*
     * Ring configuration / software producer state.
     */
    input  logic                     cfg_load,
    input  logic [63:0]              cfg_ring_base,
    input  logic [15:0]              cfg_ring_size,
    input  logic [31:0]              sw_tail,

    output logic                     config_valid,
    output logic [3:0]               config_error_code,
    output logic [31:0]              hw_head,
    output logic [31:0]              pending_count,
    output logic                     ring_empty,
    output logic                     ring_overrun,

    /*
     * Work descriptor presented to the future TX/RX payload engine.
     */
    output logic                     work_valid,
    input  logic                     work_ready,

    output logic [63:0]              work_buffer_addr,
    output logic [31:0]              work_length,
    output logic [31:0]              work_control,
    output logic [63:0]              work_cookie,

    output logic                     work_irq_on_completion,
    output logic                     work_end_of_packet,

    /*
     * Payload-engine retirement.
     *
     * retire_status follows the descriptor STATUS register format.
     */
    input  logic                     retire_valid,
    output logic                     retire_ready,
    input  logic [31:0]              retire_status,
    input  logic [31:0]              retire_actual_length,

    /*
     * Descriptor-completion event.
     */
    output logic                     completion_pulse,
    output logic                     completion_irq_requested,
    output logic [63:0]              completion_cookie,
    output logic [31:0]              completion_status,
    output logic [31:0]              completion_actual_length,

    /*
     * Fatal engine fault.
     *
     * 1 = descriptor-read failure
     * 2 = ownership violation
     * 3 = status-write failure
     * 4 = ownership-release-write failure
     * 5 = malformed descriptor-fetch stream
     * 6 = ring overrun
     */
    output logic                     fault_valid,
    input  logic                     fault_clear,
    output logic [3:0]               fault_code,

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
    input  logic [LEN_WIDTH-1:0]     rd_cpl_bytes,

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

    localparam logic [3:0] FAULT_NONE       = 4'h0;
    localparam logic [3:0] FAULT_DESC_READ  = 4'h1;
    localparam logic [3:0] FAULT_OWNERSHIP  = 4'h2;
    localparam logic [3:0] FAULT_STATUS_WR  = 4'h3;
    localparam logic [3:0] FAULT_OWN_WR     = 4'h4;
    localparam logic [3:0] FAULT_FETCH      = 4'h5;
    localparam logic [3:0] FAULT_OVERRUN    = 4'h6;

    typedef enum logic [3:0] {
        ST_IDLE,
        ST_FETCH_REQ,
        ST_FETCH_DATA,
        ST_PARSE_SUBMIT,
        ST_PARSE_WAIT,
        ST_DISPATCH,
        ST_WAIT_RETIRE,
        ST_STATUS_WR_REQ,
        ST_STATUS_WR_DATA,
        ST_STATUS_WR_CPL,
        ST_OWN_WR_REQ,
        ST_OWN_WR_DATA,
        ST_OWN_WR_CPL,
        ST_ADVANCE,
        ST_FAULT
    } state_t;

    state_t state;

    /*
     * Ring manager.
     */
    logic                  ring_descriptor_available;
    logic [15:0]           ring_slot_index;
    logic [ADDR_WIDTH-1:0] ring_descriptor_addr;
    logic                  ring_advance_head;

    dma_ring_manager #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) ring_manager (
        .clk                  (clk),
        .aresetn              (aresetn),

        .cfg_load             (cfg_load),
        .cfg_ring_base        (cfg_ring_base),
        .cfg_ring_size        (cfg_ring_size),

        .config_valid         (config_valid),
        .config_error_code    (config_error_code),

        .sw_tail              (sw_tail),
        .advance_head         (ring_advance_head),

        .hw_head              (hw_head),
        .pending_count        (pending_count),

        .ring_empty           (ring_empty),
        .ring_overrun         (ring_overrun),
        .descriptor_available (ring_descriptor_available),

        .slot_index           (ring_slot_index),
        .descriptor_addr      (ring_descriptor_addr)
    );

    /*
     * Descriptor parser.
     */
    logic         parser_desc_valid;
    logic         parser_desc_ready;
    logic [511:0] parser_desc_data;

    logic         parser_valid;
    logic         parser_ready;

    logic [63:0]  parser_buffer_addr;
    logic [31:0]  parser_length;
    logic [31:0]  parser_control;
    logic [63:0]  parser_cookie;

    logic         parser_own;
    logic         parser_irq;
    logic         parser_eop;
    logic         parser_ok;
    logic [5:0]   parser_errors;

    dma_descriptor_parser #(
        .ADDR_WIDTH (ADDR_WIDTH)
    ) descriptor_parser (
        .clk               (clk),
        .aresetn           (aresetn),

        .desc_valid        (parser_desc_valid),
        .desc_ready        (parser_desc_ready),
        .desc_data         (parser_desc_data),

        .parsed_valid      (parser_valid),
        .parsed_ready      (parser_ready),

        .buffer_addr       (parser_buffer_addr),
        .length            (parser_length),
        .control           (parser_control),
        .cookie            (parser_cookie),

        .own               (parser_own),
        .irq_on_completion (parser_irq),
        .end_of_packet     (parser_eop),

        .descriptor_ok     (parser_ok),
        .error_flags       (parser_errors)
    );

    logic [ADDR_WIDTH-1:0] active_desc_addr;

    logic [511:0] fetch_buffer;
    logic [3:0]   fetch_count;
    logic         fetch_stream_error;

    logic [63:0] latched_buffer_addr;
    logic [31:0] latched_length;
    logic [31:0] latched_control;
    logic [63:0] latched_cookie;
    logic        latched_irq;
    logic        latched_eop;

    logic [31:0] result_status;
    logic [31:0] result_actual_length;

    logic        fault_valid_reg;
    logic [3:0]  fault_code_reg;

    /*
     * Convert parser validation failures into descriptor STATUS bits.
     *
     * STATUS:
     * bit 0 COMPLETE
     * bit 1 ERROR
     * bit 4 ALIGNMENT_ERROR
     * bit 5 LENGTH_ERROR
     * bit 6 ADDRESS_ERROR
     * bit 9 INTERNAL_ERROR
     */
    function automatic [31:0] parser_error_status(
        input logic [5:0] errors
    );

        logic [31:0] status;

        begin

            status = 32'd0;

            status[0] = 1'b1;
            status[1] = 1'b1;

            if (errors[1] || errors[2])
                status[5] = 1'b1;

            if (errors[3])
                status[4] = 1'b1;

            if (errors[4])
                status[6] = 1'b1;

            if (errors[5])
                status[9] = 1'b1;

            parser_error_status = status;

        end
    endfunction

    /*
     * Combinational interface control.
     */
    always_comb begin

        /*
         * Ring retirement.
         */
        ring_advance_head =
            (state == ST_ADVANCE);

        /*
         * Descriptor read request.
         */
        rd_req_valid =
            (state == ST_FETCH_REQ);

        rd_req_addr =
            active_desc_addr;

        rd_req_bytes =
            {{(LEN_WIDTH-7){1'b0}}, 7'd64};

        /*
         * During descriptor fetch, always accept data.
         * This engine contains the complete 64-byte assembly buffer.
         */
        rd_data_ready =
            (state == ST_FETCH_DATA);

        /*
         * Completion is accepted in FETCH_DATA as well.
         *
         * This is intentional: if the AXI read master encounters an
         * error before delivering all eight descriptor beats, it can
         * still report completion without deadlocking this engine.
         */
        rd_cpl_ready =
            (state == ST_FETCH_DATA);

        /*
         * Parser interface.
         */
        parser_desc_valid =
            (state == ST_PARSE_SUBMIT);

        parser_desc_data =
            fetch_buffer;

        parser_ready =
            (state == ST_PARSE_WAIT);

        /*
         * Work dispatch.
         */
        work_valid =
            (state == ST_DISPATCH);

        work_buffer_addr =
            latched_buffer_addr;

        work_length =
            latched_length;

        work_control =
            latched_control;

        work_cookie =
            latched_cookie;

        work_irq_on_completion =
            latched_irq;

        work_end_of_packet =
            latched_eop;

        retire_ready =
            (state == ST_WAIT_RETIRE);

        /*
         * Completion write request.
         *
         * STATUS and ACTUAL_LENGTH occupy one 64-bit descriptor word
         * beginning at offset 0x18.
         */
        wr_req_valid = 1'b0;
        wr_req_addr  = '0;
        wr_req_bytes =
            {{(LEN_WIDTH-4){1'b0}}, 4'd8};

        wr_data       = 64'd0;
        wr_keep       = 8'hFF;
        wr_data_valid = 1'b0;

        wr_cpl_ready  = 1'b0;

        if (state == ST_STATUS_WR_REQ) begin

            wr_req_valid = 1'b1;
            wr_req_addr  =
                active_desc_addr +
                {{(ADDR_WIDTH-5){1'b0}}, 5'h18};

        end
        else if (state == ST_STATUS_WR_DATA) begin

            wr_data =
                {
                    result_actual_length,
                    result_status
                };

            wr_data_valid = 1'b1;

        end
        else if (state == ST_STATUS_WR_CPL) begin

            wr_cpl_ready = 1'b1;

        end
        else if (state == ST_OWN_WR_REQ) begin

            /*
             * Offset 0x08 contains:
             *
             * [31:0]  LENGTH
             * [63:32] CONTROL
             */
            wr_req_valid = 1'b1;

            wr_req_addr =
                active_desc_addr +
                {{(ADDR_WIDTH-4){1'b0}}, 4'h8};

        end
        else if (state == ST_OWN_WR_DATA) begin

            wr_data =
                {
                    (latched_control &
                     32'hFFFF_FFFE),
                    latched_length
                };

            wr_data_valid = 1'b1;

        end
        else if (state == ST_OWN_WR_CPL) begin

            wr_cpl_ready = 1'b1;

        end

        /*
         * Completion event.
         */
        completion_pulse =
            (state == ST_ADVANCE);

        completion_irq_requested =
            latched_irq;

        completion_cookie =
            latched_cookie;

        completion_status =
            result_status;

        completion_actual_length =
            result_actual_length;

        fault_valid =
            fault_valid_reg;

        fault_code =
            fault_code_reg;

    end

    /*
     * Main descriptor state machine.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            state <= ST_IDLE;

            active_desc_addr <= '0;

            fetch_buffer       <= '0;
            fetch_count        <= '0;
            fetch_stream_error <= 1'b0;

            latched_buffer_addr <= 64'd0;
            latched_length      <= 32'd0;
            latched_control     <= 32'd0;
            latched_cookie      <= 64'd0;
            latched_irq         <= 1'b0;
            latched_eop         <= 1'b0;

            result_status        <= 32'd0;
            result_actual_length <= 32'd0;

            fault_valid_reg <= 1'b0;
            fault_code_reg  <= FAULT_NONE;

        end
        else begin

            case (state)

                ST_IDLE: begin

                    fault_valid_reg <= 1'b0;
                    fault_code_reg  <= FAULT_NONE;

                    if (ring_overrun) begin

                        fault_valid_reg <= 1'b1;
                        fault_code_reg  <= FAULT_OVERRUN;
                        state           <= ST_FAULT;

                    end
                    else if (ring_descriptor_available) begin

                        active_desc_addr <=
                            ring_descriptor_addr;

                        state <= ST_FETCH_REQ;

                    end
                end

                ST_FETCH_REQ: begin

                    if (rd_req_valid &&
                        rd_req_ready) begin

                        fetch_buffer       <= '0;
                        fetch_count        <= 4'd0;
                        fetch_stream_error <= 1'b0;

                        state <= ST_FETCH_DATA;

                    end
                end

                ST_FETCH_DATA: begin

                    /*
                     * Assemble eight 64-bit beats into the 512-bit
                     * descriptor image.
                     */
                    if (rd_data_valid &&
                        rd_data_ready) begin

                        if (fetch_count < 8) begin

                            fetch_buffer[
                                (fetch_count * 64) +: 64
                            ] <= rd_data;

                        end
                        else begin

                            fetch_stream_error <= 1'b1;

                        end

                        if (rd_data_keep != 8'hFF)
                            fetch_stream_error <= 1'b1;

                        if (rd_data_last !=
                            (fetch_count == 4'd7))
                            fetch_stream_error <= 1'b1;

                        fetch_count <=
                            fetch_count + 4'd1;

                    end

                    /*
                     * The AXI read master produces completion only
                     * after the read request has terminated.
                     */
                    if (rd_cpl_valid &&
                        rd_cpl_ready) begin

                        if (rd_cpl_error) begin

                            fault_valid_reg <= 1'b1;
                            fault_code_reg  <= FAULT_DESC_READ;
                            state           <= ST_FAULT;

                        end
                        else if ((rd_cpl_bytes != 64) ||
                                 (fetch_count != 8) ||
                                 fetch_stream_error) begin

                            fault_valid_reg <= 1'b1;
                            fault_code_reg  <= FAULT_FETCH;
                            state           <= ST_FAULT;

                        end
                        else begin

                            state <= ST_PARSE_SUBMIT;

                        end
                    end
                end

                ST_PARSE_SUBMIT: begin

                    if (parser_desc_valid &&
                        parser_desc_ready) begin

                        state <= ST_PARSE_WAIT;

                    end
                end

                ST_PARSE_WAIT: begin

                    if (parser_valid &&
                        parser_ready) begin

                        latched_buffer_addr <=
                            parser_buffer_addr;

                        latched_length <=
                            parser_length;

                        latched_control <=
                            parser_control;

                        latched_cookie <=
                            parser_cookie;

                        latched_irq <=
                            parser_irq;

                        latched_eop <=
                            parser_eop;

                        /*
                         * OWN=0 is fundamentally different from an
                         * ordinary descriptor-format error.
                         *
                         * Hardware does not own the descriptor and
                         * therefore must not write it.
                         */
                        if (parser_errors[0]) begin

                            fault_valid_reg <= 1'b1;
                            fault_code_reg  <= FAULT_OWNERSHIP;
                            state           <= ST_FAULT;

                        end
                        else if (!parser_ok) begin

                            /*
                             * Hardware owns the descriptor, but it is
                             * invalid. Complete it as an explicit
                             * error without dispatching payload work.
                             */
                            result_status <=
                                parser_error_status(
                                    parser_errors
                                );

                            result_actual_length <=
                                32'd0;

                            state <= ST_STATUS_WR_REQ;

                        end
                        else begin

                            state <= ST_DISPATCH;

                        end
                    end
                end

                ST_DISPATCH: begin

                    /*
                     * All work fields remain stable until accepted.
                     */
                    if (work_valid &&
                        work_ready) begin

                        state <= ST_WAIT_RETIRE;

                    end
                end

                ST_WAIT_RETIRE: begin

                    if (retire_valid &&
                        retire_ready) begin

                        result_status <=
                            retire_status;

                        result_actual_length <=
                            retire_actual_length;

                        state <= ST_STATUS_WR_REQ;

                    end
                end

                ST_STATUS_WR_REQ: begin

                    if (wr_req_valid &&
                        wr_req_ready) begin

                        state <= ST_STATUS_WR_DATA;

                    end
                end

                ST_STATUS_WR_DATA: begin

                    if (wr_data_valid &&
                        wr_data_ready) begin

                        state <= ST_STATUS_WR_CPL;

                    end
                end

                ST_STATUS_WR_CPL: begin

                    if (wr_cpl_valid &&
                        wr_cpl_ready) begin

                        if (wr_cpl_error ||
                            (wr_cpl_bytes != 8)) begin

                            fault_valid_reg <= 1'b1;
                            fault_code_reg  <= FAULT_STATUS_WR;
                            state           <= ST_FAULT;

                        end
                        else begin

                            state <= ST_OWN_WR_REQ;

                        end
                    end
                end

                ST_OWN_WR_REQ: begin

                    if (wr_req_valid &&
                        wr_req_ready) begin

                        state <= ST_OWN_WR_DATA;

                    end
                end

                ST_OWN_WR_DATA: begin

                    if (wr_data_valid &&
                        wr_data_ready) begin

                        state <= ST_OWN_WR_CPL;

                    end
                end

                ST_OWN_WR_CPL: begin

                    if (wr_cpl_valid &&
                        wr_cpl_ready) begin

                        if (wr_cpl_error ||
                            (wr_cpl_bytes != 8)) begin

                            fault_valid_reg <= 1'b1;
                            fault_code_reg  <= FAULT_OWN_WR;
                            state           <= ST_FAULT;

                        end
                        else begin

                            /*
                             * Only now may HEAD move.
                             */
                            state <= ST_ADVANCE;

                        end
                    end
                end

                ST_ADVANCE: begin

                    /*
                     * ring_advance_head is asserted combinationally
                     * for exactly this state.
                     */
                    state <= ST_IDLE;

                end

                ST_FAULT: begin

                    /*
                     * HEAD remains unchanged while faulted.
                     *
                     * Software recovery policy will be defined at the
                     * CSR/driver layer.
                     */
                    if (fault_clear) begin

                        fault_valid_reg <= 1'b0;
                        fault_code_reg  <= FAULT_NONE;
                        state           <= ST_IDLE;

                    end
                end

                default: begin

                    fault_valid_reg <= 1'b1;
                    fault_code_reg  <= FAULT_FETCH;
                    state           <= ST_FAULT;

                end

            endcase
        end
    end

endmodule
