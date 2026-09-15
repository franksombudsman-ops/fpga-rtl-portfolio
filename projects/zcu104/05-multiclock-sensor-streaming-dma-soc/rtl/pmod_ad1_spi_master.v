`timescale 1ns/1ps

/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 */

module pmod_ad1_spi_master #(
    parameter integer CLK_FREQ_HZ  = 125000000,
    parameter integer SCLK_FREQ_HZ = 2500000
) (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,

    output reg         busy,
    output reg         sample_valid,

    output reg         cs_n,
    output reg         sclk,

    input  wire        sdata_a,
    input  wire        sdata_b,

    output reg [11:0]  sample_a,
    output reg [11:0]  sample_b
);

    localparam integer HALF_PERIOD_CYCLES =
        CLK_FREQ_HZ / (2 * SCLK_FREQ_HZ);

    localparam integer DIV_WIDTH =
        (HALF_PERIOD_CYCLES <= 1) ?
        1 : $clog2(HALF_PERIOD_CYCLES);

    localparam IDLE     = 1'b0;
    localparam TRANSFER = 1'b1;

    reg state;

    reg [DIV_WIDTH-1:0] div_count;
    reg [4:0] bit_count;

    reg [15:0] shift_a;
    reg [15:0] shift_b;

    always @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            div_count    <= 0;
            bit_count    <= 0;
            shift_a      <= 0;
            shift_b      <= 0;
            sample_a     <= 0;
            sample_b     <= 0;
            cs_n         <= 1'b1;
            sclk         <= 1'b0;
            busy         <= 1'b0;
            sample_valid <= 1'b0;

        end else begin

            sample_valid <= 1'b0;

            case (state)

                IDLE: begin
                    cs_n      <= 1'b1;
                    sclk      <= 1'b0;
                    busy      <= 1'b0;
                    div_count <= 0;
                    bit_count <= 0;

                    if (start) begin
                        cs_n    <= 1'b0;
                        busy    <= 1'b1;
                        shift_a <= 0;
                        shift_b <= 0;
                        state   <= TRANSFER;
                    end
                end

                TRANSFER: begin

                    if (div_count == HALF_PERIOD_CYCLES - 1) begin
                        div_count <= 0;

                        if (!sclk) begin
                            sclk <= 1'b1;

                            shift_a <= {shift_a[14:0], sdata_a};
                            shift_b <= {shift_b[14:0], sdata_b};

                            bit_count <= bit_count + 1'b1;

                        end else begin
                            sclk <= 1'b0;

                            if (bit_count == 5'd16) begin
                                cs_n <= 1'b1;
                                busy <= 1'b0;

                                sample_a <= shift_a[11:0];
                                sample_b <= shift_b[11:0];

                                sample_valid <= 1'b1;
                                state <= IDLE;
                            end
                        end
                    end else begin
                        div_count <= div_count + 1'b1;
                    end
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

endmodule
