// ============================================================================
// Deterministic Event & Control Engine
// Input Synchronizer
//
// Converts a single asynchronous input into a signal aligned with the
// destination system-clock domain.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

module input_synchronizer #(
    parameter int unsigned STAGES      = 2,
    parameter logic        RESET_VALUE = 1'b0
) (
    input  logic clk,
    input  logic rst,
    input  logic async_in,
    output logic sync_out
);

    // Synchronizer stages.
    //
    // ASYNC_REG identifies these registers to Vivado as a synchronization
    // chain so that synthesis and implementation preserve and optimize the
    // structure appropriately.
    (* ASYNC_REG = "TRUE" *)
    logic [STAGES-1:0] sync_ff;

    always_ff @(posedge clk) begin
        if (rst) begin
            sync_ff <= {STAGES{RESET_VALUE}};
        end
        else begin
            sync_ff[0] <= async_in;

            for (int unsigned stage = 1; stage < STAGES; stage++) begin
                sync_ff[stage] <= sync_ff[stage-1];
            end
        end
    end

    assign sync_out = sync_ff[STAGES-1];

endmodule
