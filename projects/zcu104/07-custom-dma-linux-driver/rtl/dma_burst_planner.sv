`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 07 - Custom Descriptor-Ring DMA Engine + Linux Driver
 *
 * AXI4 burst planner.
 *
 * V1 contract:
 *   - 64-bit AXI data path
 *   - 8 bytes per beat
 *   - aligned addresses
 *   - transfer lengths are multiples of 8 bytes
 *   - INCR bursts only
 *   - no burst may cross a 4-KiB boundary
 *   - maximum AXI burst = 256 beats
 */

module dma_burst_planner #(
    parameter integer ADDR_WIDTH = 40,
    parameter integer LEN_WIDTH  = 32
)(
    input  logic [ADDR_WIDTH-1:0] current_addr,
    input  logic [LEN_WIDTH-1:0]  bytes_remaining,
    input  logic [8:0]            max_burst_beats,

    output logic                  plan_valid,
    output logic                  plan_error,

    output logic [ADDR_WIDTH-1:0] burst_addr,
    output logic [8:0]            burst_beats,
    output logic [12:0]           burst_bytes,
    output logic [7:0]            axi_len
);

    logic [LEN_WIDTH-1:0] beats_remaining;
    logic [12:0]          bytes_to_4k;
    logic [LEN_WIDTH-1:0] beats_to_4k;
    logic [LEN_WIDTH-1:0] selected_beats;

    always_comb begin

        plan_valid     = 1'b0;
        plan_error     = 1'b0;

        burst_addr     = current_addr;
        burst_beats    = 9'd0;
        burst_bytes    = 13'd0;
        axi_len        = 8'd0;

        beats_remaining = bytes_remaining >> 3;

        bytes_to_4k =
            13'd4096 -
            {1'b0, current_addr[11:0]};

        beats_to_4k =
            bytes_to_4k >> 3;

        selected_beats = beats_remaining;

        /*
         * No work remaining is a normal idle condition,
         * not a planner error.
         */
        if (bytes_remaining == 0) begin
            plan_valid = 1'b0;
        end

        /*
         * V1 requires naturally aligned 64-bit transfers.
         */
        else if (current_addr[2:0] != 3'b000) begin
            plan_error = 1'b1;
        end

        else if (bytes_remaining[2:0] != 3'b000) begin
            plan_error = 1'b1;
        end

        else if ((max_burst_beats == 0) ||
                 (max_burst_beats > 9'd256)) begin
            plan_error = 1'b1;
        end

        else begin

            /*
             * Limit by configured maximum AXI burst.
             */
            if (selected_beats > max_burst_beats)
                selected_beats = max_burst_beats;

            /*
             * Limit by number of complete beats remaining
             * before the next 4-KiB boundary.
             */
            if (selected_beats > beats_to_4k)
                selected_beats = beats_to_4k;

            /*
             * A legal aligned request must always yield
             * at least one beat here.
             */
            if (selected_beats == 0) begin
                plan_error = 1'b1;
            end
            else begin
                plan_valid  = 1'b1;

                burst_beats =
                    selected_beats[8:0];

                burst_bytes =
                    selected_beats[9:0] << 3;

                axi_len =
                    selected_beats[7:0] - 8'd1;
            end
        end
    end

endmodule
