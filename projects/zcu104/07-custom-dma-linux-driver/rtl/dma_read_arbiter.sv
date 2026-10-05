`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * Three-client internal read-request arbiter.
 *
 * Client roles:
 *   0 - TX descriptor fetch
 *   1 - RX descriptor fetch
 *   2 - TX payload read
 *
 * Grant ownership persists from request acceptance until the
 * corresponding read completion handshake.
 *
 * Arbitration between requests is round-robin.
 */

module dma_read_arbiter #(
    parameter integer ADDR_WIDTH = 40,
    parameter integer LEN_WIDTH  = 32
)(
    input logic clk,
    input logic aresetn,

    /* Client 0 */
    input  logic                  c0_req_valid,
    output logic                  c0_req_ready,
    input  logic [ADDR_WIDTH-1:0] c0_req_addr,
    input  logic [LEN_WIDTH-1:0]  c0_req_bytes,

    output logic [63:0]           c0_data,
    output logic [7:0]            c0_keep,
    output logic                  c0_data_valid,
    input  logic                  c0_data_ready,
    output logic                  c0_data_last,

    output logic                  c0_cpl_valid,
    input  logic                  c0_cpl_ready,
    output logic                  c0_cpl_error,
    output logic [3:0]            c0_cpl_error_code,
    output logic [LEN_WIDTH-1:0]  c0_cpl_bytes,

    /* Client 1 */
    input  logic                  c1_req_valid,
    output logic                  c1_req_ready,
    input  logic [ADDR_WIDTH-1:0] c1_req_addr,
    input  logic [LEN_WIDTH-1:0]  c1_req_bytes,

    output logic [63:0]           c1_data,
    output logic [7:0]            c1_keep,
    output logic                  c1_data_valid,
    input  logic                  c1_data_ready,
    output logic                  c1_data_last,

    output logic                  c1_cpl_valid,
    input  logic                  c1_cpl_ready,
    output logic                  c1_cpl_error,
    output logic [3:0]            c1_cpl_error_code,
    output logic [LEN_WIDTH-1:0]  c1_cpl_bytes,

    /* Client 2 */
    input  logic                  c2_req_valid,
    output logic                  c2_req_ready,
    input  logic [ADDR_WIDTH-1:0] c2_req_addr,
    input  logic [LEN_WIDTH-1:0]  c2_req_bytes,

    output logic [63:0]           c2_data,
    output logic [7:0]            c2_keep,
    output logic                  c2_data_valid,
    input  logic                  c2_data_ready,
    output logic                  c2_data_last,

    output logic                  c2_cpl_valid,
    input  logic                  c2_cpl_ready,
    output logic                  c2_cpl_error,
    output logic [3:0]            c2_cpl_error_code,
    output logic [LEN_WIDTH-1:0]  c2_cpl_bytes,

    /* Shared read master */
    output logic                  m_req_valid,
    input  logic                  m_req_ready,
    output logic [ADDR_WIDTH-1:0] m_req_addr,
    output logic [LEN_WIDTH-1:0]  m_req_bytes,

    input  logic [63:0]           m_data,
    input  logic [7:0]            m_keep,
    input  logic                  m_data_valid,
    output logic                  m_data_ready,
    input  logic                  m_data_last,

    input  logic                  m_cpl_valid,
    output logic                  m_cpl_ready,
    input  logic                  m_cpl_error,
    input  logic [3:0]            m_cpl_error_code,
    input  logic [LEN_WIDTH-1:0]  m_cpl_bytes
);

    logic       active;
    logic [1:0] owner;
    logic [1:0] rr_ptr;

    logic       grant_valid;
    logic [1:0] grant;

    function automatic [1:0] next_client(
        input logic [1:0] client
    );
        case (client)
            2'd0: next_client = 2'd1;
            2'd1: next_client = 2'd2;
            default: next_client = 2'd0;
        endcase
    endfunction

    always_comb begin

        grant_valid = 1'b0;
        grant       = 2'd0;

        case (rr_ptr)

            2'd0: begin
                if (c0_req_valid) begin
                    grant_valid = 1'b1;
                    grant = 2'd0;
                end
                else if (c1_req_valid) begin
                    grant_valid = 1'b1;
                    grant = 2'd1;
                end
                else if (c2_req_valid) begin
                    grant_valid = 1'b1;
                    grant = 2'd2;
                end
            end

            2'd1: begin
                if (c1_req_valid) begin
                    grant_valid = 1'b1;
                    grant = 2'd1;
                end
                else if (c2_req_valid) begin
                    grant_valid = 1'b1;
                    grant = 2'd2;
                end
                else if (c0_req_valid) begin
                    grant_valid = 1'b1;
                    grant = 2'd0;
                end
            end

            default: begin
                if (c2_req_valid) begin
                    grant_valid = 1'b1;
                    grant = 2'd2;
                end
                else if (c0_req_valid) begin
                    grant_valid = 1'b1;
                    grant = 2'd0;
                end
                else if (c1_req_valid) begin
                    grant_valid = 1'b1;
                    grant = 2'd1;
                end
            end

        endcase

        c0_req_ready = 1'b0;
        c1_req_ready = 1'b0;
        c2_req_ready = 1'b0;

        m_req_valid = 1'b0;
        m_req_addr  = '0;
        m_req_bytes = '0;

        if (!active && grant_valid) begin

            m_req_valid = 1'b1;

            case (grant)

                2'd0: begin
                    m_req_addr     = c0_req_addr;
                    m_req_bytes    = c0_req_bytes;
                    c0_req_ready   = m_req_ready;
                end

                2'd1: begin
                    m_req_addr     = c1_req_addr;
                    m_req_bytes    = c1_req_bytes;
                    c1_req_ready   = m_req_ready;
                end

                default: begin
                    m_req_addr     = c2_req_addr;
                    m_req_bytes    = c2_req_bytes;
                    c2_req_ready   = m_req_ready;
                end

            endcase
        end

        c0_data       = m_data;
        c0_keep       = m_keep;
        c0_data_valid = 1'b0;
        c0_data_last  = m_data_last;

        c1_data       = m_data;
        c1_keep       = m_keep;
        c1_data_valid = 1'b0;
        c1_data_last  = m_data_last;

        c2_data       = m_data;
        c2_keep       = m_keep;
        c2_data_valid = 1'b0;
        c2_data_last  = m_data_last;

        m_data_ready = 1'b0;

        c0_cpl_valid      = 1'b0;
        c0_cpl_error      = m_cpl_error;
        c0_cpl_error_code = m_cpl_error_code;
        c0_cpl_bytes      = m_cpl_bytes;

        c1_cpl_valid      = 1'b0;
        c1_cpl_error      = m_cpl_error;
        c1_cpl_error_code = m_cpl_error_code;
        c1_cpl_bytes      = m_cpl_bytes;

        c2_cpl_valid      = 1'b0;
        c2_cpl_error      = m_cpl_error;
        c2_cpl_error_code = m_cpl_error_code;
        c2_cpl_bytes      = m_cpl_bytes;

        m_cpl_ready = 1'b0;

        if (active) begin

            case (owner)

                2'd0: begin
                    c0_data_valid = m_data_valid;
                    m_data_ready  = c0_data_ready;

                    c0_cpl_valid = m_cpl_valid;
                    m_cpl_ready  = c0_cpl_ready;
                end

                2'd1: begin
                    c1_data_valid = m_data_valid;
                    m_data_ready  = c1_data_ready;

                    c1_cpl_valid = m_cpl_valid;
                    m_cpl_ready  = c1_cpl_ready;
                end

                default: begin
                    c2_data_valid = m_data_valid;
                    m_data_ready  = c2_data_ready;

                    c2_cpl_valid = m_cpl_valid;
                    m_cpl_ready  = c2_cpl_ready;
                end

            endcase

        end

    end

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            active <= 1'b0;
            owner  <= 2'd0;
            rr_ptr <= 2'd0;

        end
        else begin

            if (!active) begin

                if (m_req_valid &&
                    m_req_ready) begin

                    active <= 1'b1;
                    owner  <= grant;
                    rr_ptr <= next_client(grant);

                end

            end
            else begin

                if (m_cpl_valid &&
                    m_cpl_ready) begin

                    active <= 1'b0;

                end

            end

        end

    end

endmodule
