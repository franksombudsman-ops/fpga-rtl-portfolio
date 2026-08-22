// ============================================================================
// Deterministic Event & Control Engine
// Reset Conditioner
//
// Provides asynchronous assertion on clock-lock loss and synchronized
// handling of the external application reset request.
//
// Author:    Frank Ouma
// Email:     frankotieno254@gmail.com
// Contact:   +254725582132
// Copyright: (c) 2026 Frank Ouma. All rights reserved.
// ============================================================================

module reset_conditioner #(
    parameter int unsigned STAGES = 2
) (
    input  logic clk,
    input  logic reset_request,
    input  logic clock_locked,
    output logic rst
);

    (* ASYNC_REG = "TRUE" *)
    logic [1:0] request_sync;

    (* ASYNC_REG = "TRUE" *)
    logic [STAGES-1:0] reset_sync;

    // Synchronize the asynchronous pushbutton reset request.
    always_ff @(posedge clk or negedge clock_locked) begin
        if (!clock_locked) begin
            request_sync <= '0;
        end
        else begin
            request_sync <= {request_sync[0], reset_request};
        end
    end

    // Loss of clock lock asserts reset immediately.
    // Normal reset release and pushbutton reset handling occur on clk edges.
    always_ff @(posedge clk or negedge clock_locked) begin
        if (!clock_locked) begin
            reset_sync <= '1;
        end
        else if (request_sync[1]) begin
            reset_sync <= '1;
        end
        else begin
            reset_sync <= {reset_sync[STAGES-2:0], 1'b0};
        end
    end

    assign rst = reset_sync[STAGES-1];

endmodule