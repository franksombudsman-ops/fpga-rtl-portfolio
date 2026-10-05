`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * Descriptor-ring head/tail manager.
 *
 * Software owns TAIL.
 * Hardware owns HEAD.
 *
 * Descriptor size = 64 bytes.
 */

module dma_ring_manager #(
    parameter integer ADDR_WIDTH = 40
)(
    input  logic         clk,
    input  logic         aresetn,

    /*
     * Configuration is loaded only while the channel is idle.
     */
    input  logic         cfg_load,
    input  logic [63:0]  cfg_ring_base,
    input  logic [15:0]  cfg_ring_size,

    output logic         config_valid,
    output logic [3:0]   config_error_code,

    /*
     * Software producer index.
     */
    input  logic [31:0]  sw_tail,

    /*
     * Pulse after hardware fully retires one descriptor.
     */
    input  logic         advance_head,

    output logic [31:0]  hw_head,
    output logic [31:0]  pending_count,

    output logic         ring_empty,
    output logic         ring_overrun,
    output logic         descriptor_available,

    output logic [15:0]  slot_index,
    output logic [ADDR_WIDTH-1:0] descriptor_addr
);

    localparam logic [3:0] CFG_OK            = 4'h0;
    localparam logic [3:0] CFG_BASE_ALIGN    = 4'h1;
    localparam logic [3:0] CFG_BASE_RANGE    = 4'h2;
    localparam logic [3:0] CFG_SIZE_RANGE    = 4'h3;
    localparam logic [3:0] CFG_SIZE_POWER2   = 4'h4;
    localparam logic [3:0] CFG_ADDR_OVERFLOW = 4'h5;

    logic [ADDR_WIDTH-1:0] ring_base_reg;
    logic [15:0]           ring_size_reg;
    logic [15:0]           ring_mask_reg;

    logic [3:0] cfg_eval_error;

    logic cfg_base_range_error;
    logic cfg_size_range_error;
    logic cfg_size_power2_error;
    logic cfg_addr_overflow;

    logic [64:0] cfg_span_ext;
    logic [64:0] cfg_end_ext;

    function automatic logic is_power_of_two(
        input logic [15:0] value
    );
        begin
            is_power_of_two =
                (value != 0) &&
                ((value & (value - 16'd1)) == 0);
        end
    endfunction

    generate
        if (ADDR_WIDTH < 64) begin : g_cfg_addr_range
            always_comb
                cfg_base_range_error =
                    |cfg_ring_base[63:ADDR_WIDTH];
        end
        else begin : g_cfg_full_addr
            always_comb
                cfg_base_range_error = 1'b0;
        end
    endgenerate

    always_comb begin

        cfg_size_range_error =
            (cfg_ring_size < 16) ||
            (cfg_ring_size > 1024);

        cfg_size_power2_error =
            !is_power_of_two(cfg_ring_size);

        cfg_span_ext =
            ({49'd0, cfg_ring_size} << 6);

        cfg_end_ext =
            {1'b0, cfg_ring_base} +
            cfg_span_ext -
            65'd1;

        cfg_addr_overflow =
            |cfg_end_ext[64:ADDR_WIDTH];

        cfg_eval_error = CFG_OK;

        if (cfg_ring_base[5:0] != 6'b0)
            cfg_eval_error = CFG_BASE_ALIGN;

        else if (cfg_base_range_error)
            cfg_eval_error = CFG_BASE_RANGE;

        else if (cfg_size_range_error)
            cfg_eval_error = CFG_SIZE_RANGE;

        else if (cfg_size_power2_error)
            cfg_eval_error = CFG_SIZE_POWER2;

        else if (cfg_addr_overflow)
            cfg_eval_error = CFG_ADDR_OVERFLOW;

    end

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            config_valid      <= 1'b0;
            config_error_code <= CFG_OK;

            ring_base_reg <= '0;
            ring_size_reg <= 16'd0;
            ring_mask_reg <= 16'd0;

            hw_head <= 32'd0;

        end
        else begin

            if (cfg_load) begin

                hw_head <= 32'd0;

                if (cfg_eval_error == CFG_OK) begin

                    ring_base_reg <=
                        cfg_ring_base[ADDR_WIDTH-1:0];

                    ring_size_reg <=
                        cfg_ring_size;

                    ring_mask_reg <=
                        cfg_ring_size - 16'd1;

                    config_valid      <= 1'b1;
                    config_error_code <= CFG_OK;

                end
                else begin

                    config_valid      <= 1'b0;
                    config_error_code <= cfg_eval_error;

                    ring_base_reg <= '0;
                    ring_size_reg <= 16'd0;
                    ring_mask_reg <= 16'd0;

                end
            end
            else if (advance_head &&
                     descriptor_available) begin

                hw_head <= hw_head + 32'd1;

            end
        end
    end

    always_comb begin

        pending_count =
            sw_tail - hw_head;

        ring_empty =
            !config_valid ||
            (pending_count == 0);

        ring_overrun =
            config_valid &&
            (pending_count >
             {16'd0, ring_size_reg});

        descriptor_available =
            config_valid &&
            (pending_count != 0) &&
            !ring_overrun;

        slot_index =
            hw_head[15:0] &
            ring_mask_reg;

        descriptor_addr =
            ring_base_reg +
            ({{(ADDR_WIDTH-16){1'b0}},
              slot_index} << 6);

    end

endmodule
