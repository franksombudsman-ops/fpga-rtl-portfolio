// ============================================================================
// Deterministic Event & Control Engine
// Deterministic Output Controller
//
// Generates a non-retriggerable timed hardware response from a qualified
// synchronous event.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

module output_controller #(
    parameter int unsigned CLK_FREQ_HZ          = 125_000_000,
    parameter int unsigned OUTPUT_ACTIVE_TIME_MS = 500,

    parameter int unsigned OUTPUT_ACTIVE_CYCLES =
        (CLK_FREQ_HZ / 1000) * OUTPUT_ACTIVE_TIME_MS
) (
    input  logic clk,
    input  logic rst,
    input  logic event_pulse,
    output logic output_active
);

    localparam int unsigned TIMER_WIDTH =
        (OUTPUT_ACTIVE_CYCLES <= 1)
        ? 1
        : $clog2(OUTPUT_ACTIVE_CYCLES);



    typedef enum logic {
        IDLE,
        ACTIVE
    } state_t;

    state_t state;

    logic [TIMER_WIDTH-1:0] output_timer;

    always_ff @(posedge clk) begin
        if (rst) begin
            state        <= IDLE;
            output_timer <= '0;
        end
        else begin
            case (state)

                IDLE: begin
                    output_timer <= '0;

                    if (event_pulse) begin
                        state <= ACTIVE;
                    end
                end

                ACTIVE: begin
                    if (OUTPUT_ACTIVE_CYCLES <= 1) begin
                        state        <= IDLE;
                        output_timer <= '0;
                    end
                    else if (output_timer == OUTPUT_ACTIVE_CYCLES - 1) begin
                        state        <= IDLE;
                        output_timer <= '0;
                    end
                    else begin
                        output_timer <= output_timer + 1'b1;
                    end
                end

                default: begin
                    state        <= IDLE;
                    output_timer <= '0;
                end

            endcase
        end
    end

    assign output_active = (state == ACTIVE);

endmodule