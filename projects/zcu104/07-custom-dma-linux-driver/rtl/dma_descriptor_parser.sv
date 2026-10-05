`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * 64-byte DMA descriptor parser / validator.
 */

module dma_descriptor_parser #(
    parameter integer ADDR_WIDTH = 40
)(
    input  logic         clk,
    input  logic         aresetn,

    input  logic         desc_valid,
    output logic         desc_ready,
    input  logic [511:0] desc_data,

    output logic         parsed_valid,
    input  logic         parsed_ready,

    output logic [63:0]  buffer_addr,
    output logic [31:0]  length,
    output logic [31:0]  control,
    output logic [63:0]  cookie,

    output logic         own,
    output logic         irq_on_completion,
    output logic         end_of_packet,

    output logic         descriptor_ok,
    output logic [5:0]   error_flags
);

    /*
     * error_flags:
     * [0] OWN not set
     * [1] zero length
     * [2] length not 8-byte aligned
     * [3] buffer address not 8-byte aligned
     * [4] address exceeds supported physical width
     * [5] reserved CONTROL bits non-zero
     */

    logic [63:0] in_buffer_addr;
    logic [31:0] in_length;
    logic [31:0] in_control;
    logic [63:0] in_cookie;

    logic [5:0] in_errors;
    logic       addr_range_error;

    assign in_buffer_addr = desc_data[63:0];
    assign in_length      = desc_data[95:64];
    assign in_control     = desc_data[127:96];
    assign in_cookie      = desc_data[191:128];

    generate
        if (ADDR_WIDTH < 64) begin : g_addr_range
            always_comb
                addr_range_error =
                    |in_buffer_addr[63:ADDR_WIDTH];
        end
        else begin : g_full_addr
            always_comb
                addr_range_error = 1'b0;
        end
    endgenerate

    always_comb begin

        in_errors = 6'b0;

        in_errors[0] = !in_control[0];
        in_errors[1] = (in_length == 0);
        in_errors[2] = (in_length[2:0] != 3'b000);
        in_errors[3] = (in_buffer_addr[2:0] != 3'b000);
        in_errors[4] = addr_range_error;
        in_errors[5] = |in_control[31:3];

    end

    assign desc_ready =
        !parsed_valid || parsed_ready;

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            parsed_valid      <= 1'b0;

            buffer_addr       <= 64'd0;
            length            <= 32'd0;
            control           <= 32'd0;
            cookie            <= 64'd0;

            own               <= 1'b0;
            irq_on_completion <= 1'b0;
            end_of_packet     <= 1'b0;

            descriptor_ok     <= 1'b0;
            error_flags       <= 6'd0;

        end
        else if (desc_ready) begin

            if (desc_valid) begin

                buffer_addr <= in_buffer_addr;
                length      <= in_length;
                control     <= in_control;
                cookie      <= in_cookie;

                own               <= in_control[0];
                irq_on_completion <= in_control[1];
                end_of_packet     <= in_control[2];

                error_flags   <= in_errors;
                descriptor_ok <= (in_errors == 0);

                parsed_valid <= 1'b1;

            end
            else begin

                parsed_valid <= 1'b0;

            end
        end
    end

endmodule
