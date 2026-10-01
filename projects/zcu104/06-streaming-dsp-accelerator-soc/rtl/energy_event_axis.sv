`timescale 1ns/1ps

// ============================================================================
// Project 06 - Streaming DSP Accelerator SoC
// Energy-threshold event detector
//
// Author: Frank Ouma
//
// Input result format:
//   [15:0]  filtered sample
//   [52:16] 37-bit moving energy
//   [53]     reserved
//   [63:54] reserved
//
// Output:
//   same payload, with bit [53] set for one sample when energy crosses:
//
//       previous_energy < threshold
//       current_energy  >= threshold
//
// TLAST is transport metadata only.
// TLAST does NOT reset event state.
// ============================================================================

module energy_event_axis #(

    parameter logic [36:0] ENERGY_THRESHOLD =
        37'd1073741824

) (

    input  logic        aclk,
    input  logic        aresetn,

    input  logic [63:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output logic [63:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);

    logic was_above;
    logic current_above;
    logic event_now;

    logic advance;

    assign current_above =
        (s_axis_tdata[52:16] >= ENERGY_THRESHOLD);

    assign event_now =
        current_above && !was_above;

    assign advance =
        (~m_axis_tvalid) | m_axis_tready;

    assign s_axis_tready =
        aresetn && advance;

    always_ff @(posedge aclk) begin

        if (!aresetn) begin

            was_above    <= 1'b0;

            m_axis_tdata  <= 64'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;

        end
        else if (advance) begin

            if (
                s_axis_tvalid &&
                s_axis_tready
            ) begin

                was_above <= current_above;

                m_axis_tdata <= {
                    s_axis_tdata[63:54],
                    event_now,
                    s_axis_tdata[52:0]
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
