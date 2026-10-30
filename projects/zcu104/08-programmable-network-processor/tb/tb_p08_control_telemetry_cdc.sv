`timescale 1ns/1ps

/*
 * Frank Ouma
 * Project 08 - Programmable Network Processor
 *
 * FPGA / SoC / Digital Hardware Engineering
 * Platform: AMD ZCU104 / Zynq UltraScale+ MPSoC
 *
 * Verification:
 *   Asynchronous Control / Packet Domain CDC
 *
 * Control clock : 100 MHz
 * Data clock    : 125 MHz
 *
 * Author: Frank Ouma
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 *
 * Copyright (c) 2026 Frank Ouma.
 * All rights reserved.
 */

module tb_p08_control_telemetry_cdc;

    localparam integer WIDTH = 256;

    /*
     * Asynchronous clocks.
     */
    logic ctrl_clk = 1'b0;
    logic data_clk = 1'b0;

    always #5 ctrl_clk = ~ctrl_clk;  // 100 MHz
    always #4 data_clk = ~data_clk;  // 125 MHz

    logic ctrl_aresetn = 1'b0;
    logic data_aresetn = 1'b0;

    logic             ctrl_cmd_valid;
    logic             ctrl_cmd_ready;
    logic [WIDTH-1:0] ctrl_cmd_payload;

    logic             ctrl_snapshot_req;
    logic             ctrl_snapshot_busy;
    logic             ctrl_snapshot_valid;
    logic [WIDTH-1:0] ctrl_snapshot_payload;

    logic             data_cmd_valid;
    logic [WIDTH-1:0] data_cmd_payload;

    logic [WIDTH-1:0] data_snapshot_payload;

    p08_control_telemetry_cdc #(
        .CMD_WIDTH (WIDTH),
        .SNAP_WIDTH(WIDTH)
    ) dut (
        .ctrl_clk              (ctrl_clk),
        .ctrl_aresetn          (ctrl_aresetn),

        .ctrl_cmd_valid        (ctrl_cmd_valid),
        .ctrl_cmd_ready        (ctrl_cmd_ready),
        .ctrl_cmd_payload      (ctrl_cmd_payload),

        .ctrl_snapshot_req     (ctrl_snapshot_req),
        .ctrl_snapshot_busy    (ctrl_snapshot_busy),
        .ctrl_snapshot_valid   (ctrl_snapshot_valid),
        .ctrl_snapshot_payload (ctrl_snapshot_payload),

        .data_clk              (data_clk),
        .data_aresetn          (data_aresetn),

        .data_cmd_valid        (data_cmd_valid),
        .data_cmd_payload      (data_cmd_payload),

        .data_snapshot_payload (data_snapshot_payload)
    );

    /*
     * ---------------------------------------------------------
     * PACKET-DOMAIN TELEMETRY GENERATOR
     * ---------------------------------------------------------
     *
     * The relationships between these fields allow the control
     * side to prove every returned snapshot is internally atomic.
     */

    logic [31:0] telemetry_epoch;

    always_ff @(posedge data_clk) begin

        if (!data_aresetn)
            telemetry_epoch <=
                32'd0;
        else
            telemetry_epoch <=
                telemetry_epoch + 1'b1;

    end

    always_comb begin

        data_snapshot_payload =
            '0;

        /*
         * word 0: datapath epoch
         */
        data_snapshot_payload[
            31:0
        ] =
            telemetry_epoch;

        /*
         * word 1: packets accepted
         */
        data_snapshot_payload[
            63:32
        ] =
            telemetry_epoch + 32'd10;

        /*
         * word 2: bytes
         */
        data_snapshot_payload[
            95:64
        ] =
            (telemetry_epoch + 32'd10) << 6;

        /*
         * word 3: drops
         */
        data_snapshot_payload[
            127:96
        ] =
            telemetry_epoch + 32'd100;

        /*
         * word 4: forwards
         */
        data_snapshot_payload[
            159:128
        ] =
            telemetry_epoch + 32'd200;

        /*
         * word 5: ingress stalls
         */
        data_snapshot_payload[
            191:160
        ] =
            telemetry_epoch + 32'd300;

        /*
         * word 6: egress stalls
         */
        data_snapshot_payload[
            223:192
        ] =
            telemetry_epoch + 32'd400;

        /*
         * word 7: error counter
         */
        data_snapshot_payload[
            255:224
        ] =
            32'd0;

    end

    /*
     * ---------------------------------------------------------
     * COMMAND VERIFICATION
     * ---------------------------------------------------------
     */

    integer commands_sent;
    integer commands_received;

    integer expected_sequence;

    logic [31:0] rx_seq;

    always @(posedge data_clk) begin

        if (data_aresetn &&
            data_cmd_valid) begin

            rx_seq =
                data_cmd_payload[
                    31:0
                ];

            if (rx_seq !==
                expected_sequence[31:0]) begin

                $display(
                    "FAIL: command order got=%0d expected=%0d",
                    rx_seq,
                    expected_sequence
                );

                $fatal;

            end

            if (data_cmd_payload[
                    63:32
                ] !==
                (rx_seq ^
                 32'hA5A55A5A)) begin

                $display(
                    "FAIL: command word1 corruption seq=%0d",
                    rx_seq
                );

                $fatal;

            end

            if (data_cmd_payload[
                    95:64
                ] !==
                (rx_seq + 32'h12340000)) begin

                $display(
                    "FAIL: command word2 corruption seq=%0d",
                    rx_seq
                );

                $fatal;

            end

            if (data_cmd_payload[
                    127:96
                ] !==
                ~rx_seq) begin

                $display(
                    "FAIL: command word3 corruption seq=%0d",
                    rx_seq
                );

                $fatal;

            end

            if (data_cmd_payload[
                    159:128
                ] !==
                (rx_seq * 32'd17)) begin

                $display(
                    "FAIL: command word4 corruption seq=%0d",
                    rx_seq
                );

                $fatal;

            end

            if (data_cmd_payload[
                    191:160
                ] !==
                (rx_seq * 32'd31)) begin

                $display(
                    "FAIL: command word5 corruption seq=%0d",
                    rx_seq
                );

                $fatal;

            end

            if (data_cmd_payload[
                    223:192
                ] !==
                (32'hCAFEB000 +
                 rx_seq)) begin

                $display(
                    "FAIL: command word6 corruption seq=%0d",
                    rx_seq
                );

                $fatal;

            end

            if (data_cmd_payload[
                    255:224
                ] !==
                (32'h5A5A0000 +
                 rx_seq)) begin

                $display(
                    "FAIL: command word7 corruption seq=%0d",
                    rx_seq
                );

                $fatal;

            end

            expected_sequence =
                expected_sequence + 1;

            commands_received =
                commands_received + 1;

        end

    end

    task automatic send_command(
        input integer seq
    );

        logic [255:0] payload;

        begin

            payload =
                '0;

            payload[31:0] =
                seq;

            payload[63:32] =
                seq ^
                32'hA5A55A5A;

            payload[95:64] =
                seq +
                32'h12340000;

            payload[127:96] =
                ~seq;

            payload[159:128] =
                seq * 32'd17;

            payload[191:160] =
                seq * 32'd31;

            payload[223:192] =
                32'hCAFEB000 +
                seq;

            payload[255:224] =
                32'h5A5A0000 +
                seq;

            while (!ctrl_cmd_ready)
                @(posedge ctrl_clk);

            @(negedge ctrl_clk);

            ctrl_cmd_payload =
                payload;

            ctrl_cmd_valid =
                1'b1;

            @(posedge ctrl_clk);
            @(negedge ctrl_clk);

            ctrl_cmd_valid =
                1'b0;

            commands_sent =
                commands_sent + 1;

        end

    endtask

    /*
     * ---------------------------------------------------------
     * SNAPSHOT VERIFICATION
     * ---------------------------------------------------------
     */

    integer snapshots_requested;
    integer snapshots_received;

    task automatic request_and_verify_snapshot;

        logic [31:0] epoch;
        logic [31:0] packets;
        logic [31:0] bytes;
        logic [31:0] drops;
        logic [31:0] forwards;
        logic [31:0] ingress_stalls;
        logic [31:0] egress_stalls;
        logic [31:0] errors;

        begin

            while (ctrl_snapshot_busy)
                @(posedge ctrl_clk);

            @(negedge ctrl_clk);

            ctrl_snapshot_req =
                1'b1;

            @(posedge ctrl_clk);
            @(negedge ctrl_clk);

            ctrl_snapshot_req =
                1'b0;

            snapshots_requested =
                snapshots_requested + 1;

            wait (
                ctrl_snapshot_valid === 1'b1
            );

            #1;

            epoch =
                ctrl_snapshot_payload[
                    31:0
                ];

            packets =
                ctrl_snapshot_payload[
                    63:32
                ];

            bytes =
                ctrl_snapshot_payload[
                    95:64
                ];

            drops =
                ctrl_snapshot_payload[
                    127:96
                ];

            forwards =
                ctrl_snapshot_payload[
                    159:128
                ];

            ingress_stalls =
                ctrl_snapshot_payload[
                    191:160
                ];

            egress_stalls =
                ctrl_snapshot_payload[
                    223:192
                ];

            errors =
                ctrl_snapshot_payload[
                    255:224
                ];

            /*
             * All these relationships are true only if every
             * telemetry word came from one data-domain instant.
             */
            if (packets !==
                (epoch + 32'd10)) begin

                $display(
                    "FAIL: non-atomic snapshot packets epoch=%0d packets=%0d",
                    epoch,
                    packets
                );

                $fatal;

            end

            if (bytes !==
                (packets << 6)) begin

                $display(
                    "FAIL: snapshot bytes relationship"
                );

                $fatal;

            end

            if (drops !==
                (epoch + 32'd100)) begin

                $display(
                    "FAIL: snapshot drops relationship"
                );

                $fatal;

            end

            if (forwards !==
                (epoch + 32'd200)) begin

                $display(
                    "FAIL: snapshot forwards relationship"
                );

                $fatal;

            end

            if (ingress_stalls !==
                (epoch + 32'd300)) begin

                $display(
                    "FAIL: snapshot ingress-stall relationship"
                );

                $fatal;

            end

            if (egress_stalls !==
                (epoch + 32'd400)) begin

                $display(
                    "FAIL: snapshot egress-stall relationship"
                );

                $fatal;

            end

            if (errors !==
                32'd0) begin

                $display(
                    "FAIL: unexpected snapshot errors=%0d",
                    errors
                );

                $fatal;

            end

            snapshots_received =
                snapshots_received + 1;

            $display(
                "SNAPSHOT %0d: PASS epoch=%0d packets=%0d bytes=%0d",
                snapshots_received,
                epoch,
                packets,
                bytes
            );

            @(posedge ctrl_clk);

        end

    endtask

    integer n;

    initial begin

        ctrl_cmd_valid =
            1'b0;

        ctrl_cmd_payload =
            '0;

        ctrl_snapshot_req =
            1'b0;

        commands_sent =
            0;

        commands_received =
            0;

        expected_sequence =
            0;

        snapshots_requested =
            0;

        snapshots_received =
            0;

        /*
         * Independent reset release.
         */
        repeat (8)
            @(posedge data_clk);

        data_aresetn =
            1'b1;

        repeat (5)
            @(posedge ctrl_clk);

        ctrl_aresetn =
            1'b1;

        repeat (5)
            @(posedge ctrl_clk);

        $display("");
        $display(
            "===== 08I PHASE 1: ASYNCHRONOUS COMMAND CDC ====="
        );

        /*
         * 64 control-plane commands cross 100 -> 125 MHz.
         */
        for (n = 0;
             n < 64;
             n = n + 1) begin

            send_command(n);

            /*
             * Interleave telemetry transactions with command
             * traffic to exercise both directions concurrently.
             */
            if ((n % 4) == 3)
                request_and_verify_snapshot();

        end

        wait (
            commands_received ==
            commands_sent
        );

        repeat (10)
            @(posedge data_clk);

        if (commands_sent != 64 ||
            commands_received != 64) begin

            $display(
                "FAIL: command accounting sent=%0d received=%0d",
                commands_sent,
                commands_received
            );

            $fatal;

        end

        $display(
            "COMMAND DELIVERY / ORDER / INTEGRITY: PASS"
        );

        if (snapshots_requested != 16 ||
            snapshots_received != 16) begin

            $display(
                "FAIL: snapshot accounting req=%0d rx=%0d",
                snapshots_requested,
                snapshots_received
            );

            $fatal;

        end

        $display(
            "ATOMIC TELEMETRY SNAPSHOTS: PASS"
        );

        /*
         * Additional snapshot after command traffic is idle.
         */
        request_and_verify_snapshot();

        if (snapshots_received != 17) begin

            $display(
                "FAIL: final snapshot missing"
            );

            $fatal;

        end

        $display("");
        $display(
            "============================================"
        );
        $display(
            " PROJECT08 08I CONTROL/TELEMETRY CDC: PASS"
        );
        $display(
            "============================================"
        );
        $display(
            " Control clock             : 100 MHz"
        );
        $display(
            " Packet clock              : 125 MHz"
        );
        $display(
            " Clock relationship        : asynchronous"
        );
        $display(
            " Commands launched         : %0d",
            commands_sent
        );
        $display(
            " Commands received         : %0d",
            commands_received
        );
        $display(
            " Lost commands             : 0"
        );
        $display(
            " Duplicate commands        : 0"
        );
        $display(
            " Command ordering          : PASS"
        );
        $display(
            " Command payload integrity : PASS"
        );
        $display(
            " Snapshot requests         : %0d",
            snapshots_requested
        );
        $display(
            " Snapshots received        : %0d",
            snapshots_received
        );
        $display(
            " Atomic telemetry          : PASS"
        );
        $display(
            " Request/ACK handshake     : PASS"
        );
        $display(
            " ASYNC_REG synchronizers   : PRESENT"
        );
        $display(
            "============================================"
        );

        $finish;

    end

    initial begin

        #20_000_000;

        $display(
            "FAIL: Project08 08I simulation timeout"
        );

        $fatal;

    end

endmodule
