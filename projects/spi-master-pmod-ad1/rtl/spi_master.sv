// =============================================================================
// spi_master.sv — Generic SPI master (Mode 0: CPOL=0, CPHA=0)
//
// Drives a single CS_N/SCLK/MOSI/MISO bus.  Width and clock divider are
// both parameterised so the same core works for different peripherals.
//
// Transaction protocol:
//   - Assert start_i for one clk cycle to begin a transfer.
//   - busy_o stays high until all BITS bits have been clocked.
//   - data_i is sampled on the rising edge of start_i.
//   - data_o is valid on the rising edge of done_o.
//
// SPI timing (Mode 0):
//   CS_N goes low one SCLK half-period before the first SCLK rising edge.
//   MOSI is driven on the falling edge; slave data is sampled on rising edge.
// =============================================================================

module spi_master #(
    parameter int BITS    = 16,   // transfer length in bits
    parameter int CLK_DIV = 4     // SCLK = clk / (2 * CLK_DIV)
) (
    input  logic              clk,
    input  logic              rst_n,

    // Control / data interface
    input  logic              start_i,     // pulse: begin a transfer
    input  logic [BITS-1:0]   data_i,      // data to shift out (MOSI)
    output logic [BITS-1:0]   data_o,      // data shifted in  (MISO)
    output logic              busy_o,      // high while transfer in progress
    output logic              done_o,      // one-cycle pulse: transfer complete

    // SPI bus
    output logic              sclk_o,
    output logic              cs_n_o,
    output logic              mosi_o,
    input  logic              miso_i
);

    // ── Clock divider counter ─────────────────────────────────────────────────
    localparam int CNT_W = $clog2(CLK_DIV);

    logic [CNT_W-1:0] clk_cnt;
    logic             clk_tick;   // one-cycle pulse at each SCLK half-period

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt  <= '0;
            clk_tick <= 1'b0;
        end else begin
            if (clk_cnt == CNT_W'(CLK_DIV - 1)) begin
                clk_cnt  <= '0;
                clk_tick <= 1'b1;
            end else begin
                clk_cnt  <= clk_cnt + 1'b1;
                clk_tick <= 1'b0;
            end
        end
    end

    // ── State machine ─────────────────────────────────────────────────────────
    typedef enum logic [1:0] {
        IDLE,
        CS_SETUP,   // one tick of CS_N low before first SCLK edge
        TRANSFER,
        DONE
    } state_t;

    state_t               state;
    logic [$clog2(BITS):0] bit_cnt;   // counts from BITS-1 down to 0
    logic [BITS-1:0]       shift_out;
    logic [BITS-1:0]       shift_in;
    logic                  sclk_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            bit_cnt   <= '0;
            shift_out <= '0;
            shift_in  <= '0;
            sclk_reg  <= 1'b0;
            cs_n_o    <= 1'b1;
            mosi_o    <= 1'b0;
            busy_o    <= 1'b0;
            done_o    <= 1'b0;
            data_o    <= '0;
        end else begin
            done_o <= 1'b0;   // default: pulse for one cycle only

            case (state)
                IDLE: begin
                    sclk_reg <= 1'b0;
                    cs_n_o   <= 1'b1;
                    if (start_i) begin
                        shift_out <= data_i;
                        bit_cnt   <= BITS[$clog2(BITS):0] - 1'b1;
                        busy_o    <= 1'b1;
                        state     <= CS_SETUP;
                    end
                end

                CS_SETUP: begin
                    cs_n_o <= 1'b0;   // assert CS_N
                    mosi_o <= shift_out[BITS-1];   // pre-drive MSB
                    if (clk_tick)
                        state <= TRANSFER;
                end

                TRANSFER: begin
                    if (clk_tick) begin
                        sclk_reg <= ~sclk_reg;

                        if (!sclk_reg) begin
                            // Rising edge of SCLK: sample MISO
                            shift_in <= {shift_in[BITS-2:0], miso_i};
                        end else begin
                            // Falling edge of SCLK: advance shift-out, check done
                            if (bit_cnt == '0) begin
                                state  <= DONE;
                                mosi_o <= 1'b0;
                            end else begin
                                shift_out <= {shift_out[BITS-2:0], 1'b0};
                                mosi_o    <= shift_out[BITS-2];
                                bit_cnt   <= bit_cnt - 1'b1;
                            end
                        end
                    end
                end

                DONE: begin
                    if (clk_tick) begin
                        cs_n_o <= 1'b1;
                        sclk_reg <= 1'b0;
                        data_o <= shift_in;
                        done_o <= 1'b1;
                        busy_o <= 1'b0;
                        state  <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign sclk_o = sclk_reg;

endmodule
