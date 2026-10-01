`timescale 1ns/1ps

// ============================================================================
// Project 06 - Streaming DSP Accelerator SoC
// 64-sample moving signal-energy engine
//
// Author: Frank Ouma
//
// Input:
//   signed 16-bit filtered Q1.15 sample
//
// Operation:
//   square[n] = sample[n]^2
//
//   energy[n] = energy[n-1]
//             + square[n]
//             - square[n-64]
//
// Numerical contract:
//   sample square : unsigned 31-bit
//   moving energy : unsigned 37-bit
//
// AXI behaviour:
//   state advances ONLY on an accepted input transfer.
//   entire engine freezes under downstream backpressure.
//   TLAST propagates but DOES NOT clear signal history.
// ============================================================================

module moving_energy64_axis (

    input  logic        aclk,
    input  logic        aresetn,

    input  logic [15:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    // Result format:
    //
    // [15:0]  = filtered sample
    // [52:16] = 37-bit moving energy
    // [53]    = reserved for event flag
    // [63:54] = reserved
    output logic [63:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);

    logic [30:0] square_history [0:63];

    logic [5:0]  history_ptr;
    logic [36:0] energy_acc;

    logic signed [31:0] square_signed;
    logic        [30:0] new_square;
    logic        [30:0] old_square;

    logic [37:0] energy_next_ext;

    logic advance;

    integer i;

    // ------------------------------------------------------------------------
    // 16-bit signed sample squared.
    //
    // Maximum:
    //   (-32768)^2 = 2^30
    //
    // Therefore 31 unsigned bits are sufficient.
    // ------------------------------------------------------------------------

    always_comb begin
        square_signed =
            $signed(s_axis_tdata) *
            $signed(s_axis_tdata);

        new_square = square_signed[30:0];

        old_square = square_history[history_ptr];

        energy_next_ext =
            {1'b0, energy_acc}
            - {{7{1'b0}}, old_square}
            + {{7{1'b0}}, new_square};
    end

    // Output register may accept a new result when:
    //
    //   1. it is currently empty, OR
    //   2. the current output is being consumed.
    assign advance =
        (~m_axis_tvalid) | m_axis_tready;

    assign s_axis_tready =
        aresetn && advance;

    always_ff @(posedge aclk) begin

        if (!aresetn) begin

            history_ptr   <= 6'd0;
            energy_acc    <= 37'd0;

            m_axis_tdata  <= 64'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;

            for (i = 0; i < 64; i = i + 1)
                square_history[i] <= 31'd0;

        end
        else if (advance) begin

            if (s_axis_tvalid && s_axis_tready) begin

                // Remove the sample leaving the 64-sample window
                // and add the newly accepted squared sample.
                energy_acc <= energy_next_ext[36:0];

                // Replace oldest stored square.
                square_history[history_ptr] <= new_square;

                // Modulo-64 naturally through 6-bit overflow.
                history_ptr <= history_ptr + 6'd1;

                // Preserve the filtered sample and publish the
                // updated energy corresponding to THIS sample.
                m_axis_tdata <= {
                    10'd0,
                    1'b0,
                    energy_next_ext[36:0],
                    s_axis_tdata
                };

                m_axis_tvalid <= 1'b1;
                m_axis_tlast  <= s_axis_tlast;

            end
            else begin

                m_axis_tvalid <= 1'b0;
                m_axis_tlast  <= 1'b0;
            end
        end
    end

endmodule
