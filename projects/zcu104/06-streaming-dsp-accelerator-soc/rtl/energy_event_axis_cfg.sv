`timescale 1ns/1ps

// ============================================================================
// Project 06 - Streaming DSP Accelerator SoC
// Programmable moving-energy threshold event detector
//
// Author: Frank Ouma
//
// Crossing rule:
//
//   event[n] =
//       (energy[n-1] < threshold) &&
//       (energy[n]   >= threshold)
//
// The event is asserted for exactly the result sample that crosses upward.
// Remaining above threshold does not repeatedly generate events.
//
// TLAST is transport metadata only and does not clear event history.
// ============================================================================

module energy_event_axis_cfg (

    input  logic        aclk,
    input  logic        aresetn,

    input  logic [36:0] energy_threshold,

    input  logic [63:0] s_axis_tdata,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,

    output logic [63:0] m_axis_tdata,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);

    logic [36:0] previous_energy;
    logic [36:0] current_energy;

    logic event_now;
    logic advance;

    assign current_energy =
        s_axis_tdata[52:16];

    assign event_now =
        (previous_energy < energy_threshold) &&
        (current_energy  >= energy_threshold);

    assign advance =
        (~m_axis_tvalid) | m_axis_tready;

    assign s_axis_tready =
        aresetn && advance;

    always_ff @(posedge aclk) begin

        if (!aresetn) begin

            previous_energy <= 37'd0;

            m_axis_tdata  <= 64'd0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;

        end
        else if (advance) begin

            if (
                s_axis_tvalid &&
                s_axis_tready
            ) begin

                previous_energy <=
                    current_energy;

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
