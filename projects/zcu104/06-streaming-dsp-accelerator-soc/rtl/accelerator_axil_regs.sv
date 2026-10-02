`timescale 1ns/1ps

// ============================================================================
// Project 06 - Streaming DSP Accelerator SoC
// AXI4-Lite control / status / telemetry register bank
//
// Author: Frank Ouma
//
// 32-bit AXI4-Lite
//
// Register map:
//   0x00 CONTROL
//   0x04 STATUS
//   0x08 ENERGY_THRESHOLD_LO
//   0x0C ENERGY_THRESHOLD_HI
//   0x10 SAMPLE_COUNT
//   0x14 RESULT_COUNT
//   0x18 EVENT_COUNT
//   0x1C INPUT_STALL_COUNT
//   0x20 OUTPUT_STALL_COUNT
//
// Important:
//   AW and W channels are captured independently.
//   WSTRB is respected.
// ============================================================================

module accelerator_axil_regs (

    input  logic         aclk,
    input  logic         aresetn,

    // ------------------------------------------------------------------------
    // AXI4-Lite write address
    // ------------------------------------------------------------------------

    input  logic [5:0]   s_axi_awaddr,
    input  logic         s_axi_awvalid,
    output logic         s_axi_awready,

    // ------------------------------------------------------------------------
    // AXI4-Lite write data
    // ------------------------------------------------------------------------

    input  logic [31:0]  s_axi_wdata,
    input  logic [3:0]   s_axi_wstrb,
    input  logic         s_axi_wvalid,
    output logic         s_axi_wready,

    // ------------------------------------------------------------------------
    // AXI4-Lite write response
    // ------------------------------------------------------------------------

    output logic [1:0]   s_axi_bresp,
    output logic         s_axi_bvalid,
    input  logic         s_axi_bready,

    // ------------------------------------------------------------------------
    // AXI4-Lite read address
    // ------------------------------------------------------------------------

    input  logic [5:0]   s_axi_araddr,
    input  logic         s_axi_arvalid,
    output logic         s_axi_arready,

    // ------------------------------------------------------------------------
    // AXI4-Lite read data
    // ------------------------------------------------------------------------

    output logic [31:0]  s_axi_rdata,
    output logic [1:0]   s_axi_rresp,
    output logic         s_axi_rvalid,
    input  logic         s_axi_rready,

    // ------------------------------------------------------------------------
    // Accelerator status
    // ------------------------------------------------------------------------

    input  logic         status_idle,
    input  logic         status_input_active,
    input  logic         status_output_active,

    // ------------------------------------------------------------------------
    // Telemetry event pulses
    // ------------------------------------------------------------------------

    input  logic         sample_accepted,
    input  logic         result_accepted,
    input  logic         event_accepted,
    input  logic         input_stall_cycle,
    input  logic         output_stall_cycle,

    // ------------------------------------------------------------------------
    // Configuration outputs
    // ------------------------------------------------------------------------

    output logic         cfg_enable,
    output logic [36:0]  cfg_energy_threshold,

    output logic         cfg_state_clear_pulse,
    output logic         cfg_counter_clear_pulse
);

    // ------------------------------------------------------------------------
    // AXI write channel holding registers
    // ------------------------------------------------------------------------

    logic        aw_pending;
    logic [5:0]  awaddr_hold;

    logic        w_pending;
    logic [31:0] wdata_hold;
    logic [3:0]  wstrb_hold;

    logic write_fire;

    // ------------------------------------------------------------------------
    // Telemetry counters
    // ------------------------------------------------------------------------

    logic [31:0] sample_count;
    logic [31:0] result_count;
    logic [31:0] event_count;
    logic [31:0] input_stall_count;
    logic [31:0] output_stall_count;

    // ------------------------------------------------------------------------
    // Write transaction
    // ------------------------------------------------------------------------

    assign s_axi_awready =
        !aw_pending && !s_axi_bvalid;

    assign s_axi_wready =
        !w_pending && !s_axi_bvalid;

    assign write_fire =
        aw_pending &&
        w_pending &&
        !s_axi_bvalid;

    assign s_axi_bresp =
        2'b00; // OKAY

    // ------------------------------------------------------------------------
    // Read transaction
    // ------------------------------------------------------------------------

    assign s_axi_arready =
        !s_axi_rvalid;

    assign s_axi_rresp =
        2'b00; // OKAY

    // ------------------------------------------------------------------------
    // Write address/data capture and register writes
    // ------------------------------------------------------------------------

    always_ff @(posedge aclk) begin

        if (!aresetn) begin

            aw_pending <= 1'b0;
            awaddr_hold <= 6'd0;

            w_pending <= 1'b0;
            wdata_hold <= 32'd0;
            wstrb_hold <= 4'd0;

            s_axi_bvalid <= 1'b0;

            cfg_enable <= 1'b0;

            cfg_energy_threshold <=
                37'd1073741824;

            cfg_state_clear_pulse <= 1'b0;
            cfg_counter_clear_pulse <= 1'b0;

        end
        else begin

            // W1P signals default low every cycle.
            cfg_state_clear_pulse <= 1'b0;
            cfg_counter_clear_pulse <= 1'b0;

            // ---------------------------------------------------------------
            // Capture AW independently
            // ---------------------------------------------------------------

            if (
                s_axi_awvalid &&
                s_axi_awready
            ) begin

                aw_pending <= 1'b1;
                awaddr_hold <= s_axi_awaddr;

            end

            // ---------------------------------------------------------------
            // Capture W independently
            // ---------------------------------------------------------------

            if (
                s_axi_wvalid &&
                s_axi_wready
            ) begin

                w_pending <= 1'b1;
                wdata_hold <= s_axi_wdata;
                wstrb_hold <= s_axi_wstrb;

            end

            // ---------------------------------------------------------------
            // Execute once both channels have arrived
            // ---------------------------------------------------------------

            if (write_fire) begin

                case (awaddr_hold)

                    // --------------------------------------------------------
                    // CONTROL
                    // --------------------------------------------------------

                    6'h00: begin

                        if (wstrb_hold[0]) begin

                            // ENABLE is normal RW.
                            cfg_enable <=
                                wdata_hold[0];

                            // STATE_CLEAR:
                            // accepted only when already disabled AND idle.
                            //
                            // Software therefore performs:
                            // disable -> poll idle -> state clear.
                            if (
                                wdata_hold[1] &&
                                !cfg_enable &&
                                status_idle
                            ) begin

                                cfg_state_clear_pulse <=
                                    1'b1;

                            end

                            // COUNTER_CLEAR may occur at any time.
                            if (wdata_hold[2]) begin

                                cfg_counter_clear_pulse <=
                                    1'b1;

                            end
                        end
                    end

                    // --------------------------------------------------------
                    // ENERGY_THRESHOLD_LO
                    // Only writable when disabled and idle.
                    // --------------------------------------------------------

                    6'h08: begin

                        if (
                            !cfg_enable &&
                            status_idle
                        ) begin

                            if (wstrb_hold[0])
                                cfg_energy_threshold[7:0]
                                    <= wdata_hold[7:0];

                            if (wstrb_hold[1])
                                cfg_energy_threshold[15:8]
                                    <= wdata_hold[15:8];

                            if (wstrb_hold[2])
                                cfg_energy_threshold[23:16]
                                    <= wdata_hold[23:16];

                            if (wstrb_hold[3])
                                cfg_energy_threshold[31:24]
                                    <= wdata_hold[31:24];

                        end
                    end

                    // --------------------------------------------------------
                    // ENERGY_THRESHOLD_HI
                    // Only bits [4:0] are implemented.
                    // --------------------------------------------------------

                    6'h0C: begin

                        if (
                            !cfg_enable &&
                            status_idle &&
                            wstrb_hold[0]
                        ) begin

                            cfg_energy_threshold[36:32]
                                <= wdata_hold[4:0];

                        end
                    end

                    default: begin
                        // RO / reserved / unmapped writes ignored.
                    end

                endcase

                aw_pending <= 1'b0;
                w_pending <= 1'b0;

                s_axi_bvalid <= 1'b1;

            end

            // ---------------------------------------------------------------
            // Write response completion
            // ---------------------------------------------------------------

            if (
                s_axi_bvalid &&
                s_axi_bready
            ) begin

                s_axi_bvalid <= 1'b0;

            end
        end
    end

    // ------------------------------------------------------------------------
    // Telemetry counters
    //
    // Counter clear takes precedence over increments.
    // ------------------------------------------------------------------------

    always_ff @(posedge aclk) begin

        if (!aresetn) begin

            sample_count <= 32'd0;
            result_count <= 32'd0;
            event_count <= 32'd0;
            input_stall_count <= 32'd0;
            output_stall_count <= 32'd0;

        end
        else if (
            write_fire &&
            awaddr_hold == 6'h00 &&
            wstrb_hold[0] &&
            wdata_hold[2]
        ) begin

            sample_count <= 32'd0;
            result_count <= 32'd0;
            event_count <= 32'd0;
            input_stall_count <= 32'd0;
            output_stall_count <= 32'd0;

        end
        else begin

            if (sample_accepted)
                sample_count <=
                    sample_count + 32'd1;

            if (result_accepted)
                result_count <=
                    result_count + 32'd1;

            if (event_accepted)
                event_count <=
                    event_count + 32'd1;

            if (input_stall_cycle)
                input_stall_count <=
                    input_stall_count + 32'd1;

            if (output_stall_cycle)
                output_stall_count <=
                    output_stall_count + 32'd1;

        end
    end

    // ------------------------------------------------------------------------
    // AXI read channel
    // ------------------------------------------------------------------------

    always_ff @(posedge aclk) begin

        if (!aresetn) begin

            s_axi_rvalid <= 1'b0;
            s_axi_rdata <= 32'd0;

        end
        else begin

            if (
                s_axi_arvalid &&
                s_axi_arready
            ) begin

                case (s_axi_araddr)

                    6'h00:
                        s_axi_rdata <= {
                            29'd0,
                            2'b00,
                            cfg_enable
                        };

                    6'h04:
                        s_axi_rdata <= {
                            28'd0,
                            status_output_active,
                            status_input_active,
                            status_idle,
                            cfg_enable
                        };

                    6'h08:
                        s_axi_rdata <=
                            cfg_energy_threshold[31:0];

                    6'h0C:
                        s_axi_rdata <= {
                            27'd0,
                            cfg_energy_threshold[36:32]
                        };

                    6'h10:
                        s_axi_rdata <=
                            sample_count;

                    6'h14:
                        s_axi_rdata <=
                            result_count;

                    6'h18:
                        s_axi_rdata <=
                            event_count;

                    6'h1C:
                        s_axi_rdata <=
                            input_stall_count;

                    6'h20:
                        s_axi_rdata <=
                            output_stall_count;

                    default:
                        s_axi_rdata <=
                            32'd0;

                endcase

                s_axi_rvalid <= 1'b1;

            end
            else if (
                s_axi_rvalid &&
                s_axi_rready
            ) begin

                s_axi_rvalid <= 1'b0;

            end
        end
    end

endmodule
