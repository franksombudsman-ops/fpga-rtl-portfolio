`timescale 1ns/1ps
module pmod_ad1_spi_master #(
    parameter int unsigned CLK_FREQ_HZ  = 125_000_000,
    parameter int unsigned SCLK_FREQ_HZ =   2_500_000
) (
    input  logic        clk,
    input  logic        rst,

    // Transaction control
    input  logic        start,
    output logic        busy,
    output logic        sample_valid,

    // Pmod AD1 interface
    output logic        cs_n,
    output logic        sclk,
    input  logic        sdata_a,
    input  logic        sdata_b,

    // Acquired ADC samples
    output logic [11:0] sample_a,
    output logic [11:0] sample_b
);

    localparam int unsigned HALF_PERIOD_CYCLES =
        CLK_FREQ_HZ / (2 * SCLK_FREQ_HZ);

    localparam int unsigned DIV_WIDTH =
        $clog2(HALF_PERIOD_CYCLES);

    typedef enum logic {
        IDLE,
        TRANSFER
    } state_t;

    state_t state;

    logic [DIV_WIDTH-1:0] div_count;
    logic [4:0]           bit_count;

    logic [15:0] shift_a;
    logic [15:0] shift_b;

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;

            div_count    <= '0;
            bit_count    <= '0;

            shift_a      <= '0;
            shift_b      <= '0;

            sample_a     <= '0;
            sample_b     <= '0;

            cs_n         <= 1'b1;
            sclk         <= 1'b0;

            busy         <= 1'b0;
            sample_valid <= 1'b0;

        end else begin

            // Default: valid is a one-clock pulse.
            sample_valid <= 1'b0;

            case (state)

                IDLE: begin
                    cs_n      <= 1'b1;
                    sclk      <= 1'b0;
                    busy      <= 1'b0;

                    div_count <= '0;
                    bit_count <= '0;

                    if (start) begin
                        cs_n      <= 1'b0;
                        busy      <= 1'b1;

                        shift_a   <= '0;
                        shift_b   <= '0;

                        state     <= TRANSFER;
                    end
                end


                TRANSFER: begin

                    if (div_count == HALF_PERIOD_CYCLES - 1) begin

                        div_count <= '0;

                        // LOW -> HIGH:
                        // capture ADC data on rising SCLK edge.
                        if (!sclk) begin
                            sclk <= 1'b1;

                            shift_a <= {shift_a[14:0], sdata_a};
                            shift_b <= {shift_b[14:0], sdata_b};

                            bit_count <= bit_count + 1'b1;

                        // HIGH -> LOW
                        end else begin
                            sclk <= 1'b0;

                            // Complete after all 16 captured bits
                            // have received their full clock cycle.
                            if (bit_count == 5'd16) begin
                                cs_n <= 1'b1;
                                busy <= 1'b0;

                                // AD1 frame:
                                // [15:12] = four leading zeros
                                // [11:0]  = ADC measurement
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
