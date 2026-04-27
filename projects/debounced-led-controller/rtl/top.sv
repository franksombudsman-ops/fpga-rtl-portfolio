`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/13/2026 10:50:59 PM
// Design Name: 
// Module Name: top
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module top (
    input  logic       clk,           // 100 MHz PL clock from KR260
    input  logic       rst_n,         // reset button (active-low)
    input  logic       btn_raw,       // raw bouncy advance button
    output logic [2:0] leds           // 3 LEDs showing counter state
);

    // ── Internal signals ─────────────────────────────────────────
    logic btn_clean;       // debounced button (level)
    logic btn_clean_d;     // debounced button, delayed one cycle
    logic btn_pulse;       // one-cycle pulse on rising edge

    // ── Debouncer instance ───────────────────────────────────────
    debouncer #(
        .COUNTER_WIDTH (20),
        .STABLE_COUNT  (1_000_000)     // real 10 ms for hardware
    ) u_debouncer (
        .clk        (clk),
        .rst_n      (rst_n),
        .button_in  (btn_raw),
        .button_out (btn_clean)
    );

    // ── Rising-edge detector (inline) ────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) btn_clean_d <= 1'b0;
        else        btn_clean_d <= btn_clean;
    end

    assign btn_pulse = btn_clean & ~btn_clean_d;

    // ── Johnson counter instance ─────────────────────────────────
    johnson_counter #(
        .WIDTH (3)
    ) u_johnson (
        .clk     (clk),
        .rst_n   (rst_n),
        .advance (btn_pulse),
        .q       (leds)
    );

endmodule
