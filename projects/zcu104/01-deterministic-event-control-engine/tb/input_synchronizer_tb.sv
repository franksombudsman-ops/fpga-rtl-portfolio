// ============================================================================
// Deterministic Event & Control Engine
// Input Synchronizer Testbench
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

`timescale 1ns/1ps

module input_synchronizer_tb;

    localparam time CLK_PERIOD = 8ns;

    logic clk      = 1'b0;
    logic rst      = 1'b1;
    logic async_in = 1'b0;
    logic sync_out;

    input_synchronizer #(
        .STAGES(2),
        .RESET_VALUE(1'b0)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .async_in (async_in),
        .sync_out (sync_out)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        repeat (4) @(posedge clk);
        rst <= 1'b0;

        #11 async_in <= 1'b1;
        #40;

        #3 async_in <= 1'b0;
        #40;

        #5 async_in <= 1'b1;
        #6 async_in <= 1'b0;
        #40;

        $finish;
    end

endmodule
