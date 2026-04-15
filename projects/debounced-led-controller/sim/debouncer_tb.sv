`timescale 1ns / 1ps

module debouncer_tb;

    // ── DUT signals ──────────────────────────────────────────────
    logic clk;
    logic rst_n;
    logic button_in;
    logic button_out;

    // ── Instantiate DUT with tiny STABLE_COUNT for fast sim ──────
    debouncer #(
        .COUNTER_WIDTH (8),
        .STABLE_COUNT  (100)   // 100 cycles = 1 us at 100 MHz
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .button_in  (button_in),
        .button_out (button_out)
    );

    // ── 100 MHz clock: toggle every 5 ns → 10 ns period ──────────
    initial clk = 0;
    always #5 clk = ~clk;

    // ── Monitor: print whenever button_out changes ───────────────
    initial begin
        $display("Time(ns)   button_in  button_out");
        forever begin
            @(button_out);
            $display("%8t      %b          %b", $time, button_in, button_out);
        end
    end

    // ── Stimulus ─────────────────────────────────────────────────
    initial begin
        // Init
        rst_n     = 0;
        button_in = 0;
        #50;              // hold reset for 50 ns
        rst_n = 1;
        #100;             // let things settle

        // --- Press: bounce for a bit, then hold stable high ---
        $display("--- Pressing button (with bounce) ---");
        repeat (20) begin
            button_in = 1; #17;
            button_in = 0; #23;
        end
        button_in = 1;
        #5000;            // hold stable for 5 us - plenty past 1 us threshold

        // --- Release: bounce for a bit, then hold stable low ---
        $display("--- Releasing button (with bounce) ---");
        repeat (20) begin
            button_in = 0; #19;
            button_in = 1; #13;
        end
        button_in = 0;
        #5000;

        $display("--- Test complete ---");
        $finish;
    end

endmodule