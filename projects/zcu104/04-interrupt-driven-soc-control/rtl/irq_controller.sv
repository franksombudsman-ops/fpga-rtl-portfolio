`timescale 1ns/1ps

module irq_controller (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        event_pulse,
    input  logic        irq_enable,
    input  logic        irq_clear,

    output logic        irq_pending,
    output logic        irq_out,
    output logic [31:0] event_count
);

    /*
     * Interrupt policy:
     *
     * - event_pulse sets irq_pending.
     * - irq_pending remains set until software clears it.
     * - irq_enable masks only the external IRQ output;
     *   it does NOT destroy a pending event.
     * - If irq_clear and event_pulse occur in the same cycle,
     *   the new event wins so an event cannot be lost.
     */

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            irq_pending <= 1'b0;
            event_count <= 32'd0;
        end else begin

            if (event_pulse) begin
                irq_pending <= 1'b1;
                event_count <= event_count + 32'd1;
            end
            else if (irq_clear) begin
                irq_pending <= 1'b0;
            end

        end
    end

    assign irq_out = irq_pending & irq_enable;

endmodule
