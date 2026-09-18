`timescale 1ns/1ps

/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 * Two-source AXI4-Stream packet arbiter regression.
 */

module tb_axis_packet_arbiter_2to1;

    reg aclk = 1'b0;
    reg aresetn = 1'b0;

    reg  [31:0] s0_axis_tdata  = 32'd0;
    reg  [3:0]  s0_axis_tkeep  = 4'hF;
    reg         s0_axis_tvalid = 1'b0;
    wire        s0_axis_tready;
    reg         s0_axis_tlast  = 1'b0;

    reg  [31:0] s1_axis_tdata  = 32'd0;
    reg  [3:0]  s1_axis_tkeep  = 4'hF;
    reg         s1_axis_tvalid = 1'b0;
    wire        s1_axis_tready;
    reg         s1_axis_tlast  = 1'b0;

    wire [31:0] m_axis_tdata;
    wire [3:0]  m_axis_tkeep;
    wire        m_axis_tvalid;
    reg         m_axis_tready = 1'b0;
    wire        m_axis_tlast;

    always #20 aclk = ~aclk;   // 25 MHz


    axis_packet_arbiter_2to1 dut (
        .aclk           (aclk),
        .aresetn        (aresetn),

        .s0_axis_tdata  (s0_axis_tdata),
        .s0_axis_tkeep  (s0_axis_tkeep),
        .s0_axis_tvalid (s0_axis_tvalid),
        .s0_axis_tready (s0_axis_tready),
        .s0_axis_tlast  (s0_axis_tlast),

        .s1_axis_tdata  (s1_axis_tdata),
        .s1_axis_tkeep  (s1_axis_tkeep),
        .s1_axis_tvalid (s1_axis_tvalid),
        .s1_axis_tready (s1_axis_tready),
        .s1_axis_tlast  (s1_axis_tlast),

        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tkeep   (m_axis_tkeep),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast)
    );


    task automatic send_s0_packet(
        input [31:0] w0,
        input [31:0] w1,
        input [31:0] w2,
        input [31:0] w3
    );
        integer i;
        reg [31:0] word;
    begin

        @(negedge aclk);

        s0_axis_tvalid = 1'b1;
        s0_axis_tkeep  = 4'hF;
        s0_axis_tlast  = 1'b0;
        s0_axis_tdata  = w0;

        for (i = 0; i < 4; i = i + 1) begin

            /*
             * Advance only after observing an actual AXI
             * handshake on a rising clock edge.
             */
            @(posedge aclk);

            while (!s0_axis_tready)
                @(posedge aclk);

            #1;
            @(negedge aclk);

            if (i == 3) begin

                s0_axis_tvalid = 1'b0;
                s0_axis_tlast  = 1'b0;
                s0_axis_tdata  = 32'd0;

            end
            else begin

                case (i + 1)
                    1: word = w1;
                    2: word = w2;
                    3: word = w3;
                    default: word = 32'd0;
                endcase

                s0_axis_tdata = word;
                s0_axis_tlast = ((i + 1) == 3);

            end

        end
    end
    endtask


    task automatic send_s1_packet(
        input [31:0] w0,
        input [31:0] w1,
        input [31:0] w2,
        input [31:0] w3
    );
        integer i;
        reg [31:0] word;
    begin

        @(negedge aclk);

        s1_axis_tvalid = 1'b1;
        s1_axis_tkeep  = 4'hF;
        s1_axis_tlast  = 1'b0;
        s1_axis_tdata  = w0;

        for (i = 0; i < 4; i = i + 1) begin

            /*
             * Advance only after observing an actual AXI
             * handshake on a rising clock edge.
             */
            @(posedge aclk);

            while (!s1_axis_tready)
                @(posedge aclk);

            #1;
            @(negedge aclk);

            if (i == 3) begin

                s1_axis_tvalid = 1'b0;
                s1_axis_tlast  = 1'b0;
                s1_axis_tdata  = 32'd0;

            end
            else begin

                case (i + 1)
                    1: word = w1;
                    2: word = w2;
                    3: word = w3;
                    default: word = 32'd0;
                endcase

                s1_axis_tdata = word;
                s1_axis_tlast = ((i + 1) == 3);

            end

        end
    end
    endtask


    task automatic expect_word(
        input [31:0] expected_data,
        input        expected_last
    );
    begin

        @(posedge aclk);

        while (!(m_axis_tvalid && m_axis_tready))
            @(posedge aclk);

        if (m_axis_tdata !== expected_data) begin
            $display(
                "FAIL: expected data %08h, received %08h",
                expected_data,
                m_axis_tdata
            );
            $fatal;
        end

        if (m_axis_tkeep !== 4'hF) begin
            $display("FAIL: TKEEP mismatch");
            $fatal;
        end

        if (m_axis_tlast !== expected_last) begin
            $display(
                "FAIL: TLAST mismatch for word %08h",
                expected_data
            );
            $fatal;
        end

        #1;

    end
    endtask


    task automatic expect_packet(
        input [31:0] w0,
        input [31:0] w1,
        input [31:0] w2,
        input [31:0] w3
    );
    begin

        expect_word(w0, 1'b0);
        expect_word(w1, 1'b0);
        expect_word(w2, 1'b0);
        expect_word(w3, 1'b1);

    end
    endtask


    initial begin

        // -------------------------------------------------
        // RESET
        // -------------------------------------------------

        repeat (5)
            @(posedge aclk);

        aresetn = 1'b1;
        m_axis_tready = 1'b1;

        repeat (2)
            @(posedge aclk);


        // -------------------------------------------------
        // TEST 1
        // Source 0 operating alone.
        // -------------------------------------------------

        fork

            send_s0_packet(
                32'hA000_0000,
                32'hA000_0001,
                32'hA000_0002,
                32'hA000_0003
            );

            expect_packet(
                32'hA000_0000,
                32'hA000_0001,
                32'hA000_0002,
                32'hA000_0003
            );

        join


        // -------------------------------------------------
        // TEST 2
        // Both sources request simultaneously.
        //
        // TEST 1 completed with source 0 as the last grant.
        // Round-robin priority must therefore select source 1
        // first, without interleaving the source 0 packet.
        // -------------------------------------------------

        fork

            send_s0_packet(
                32'hA100_0000,
                32'hA100_0001,
                32'hA100_0002,
                32'hA100_0003
            );

            send_s1_packet(
                32'hB100_0000,
                32'hB100_0001,
                32'hB100_0002,
                32'hB100_0003
            );

            begin

                expect_packet(
                    32'hB100_0000,
                    32'hB100_0001,
                    32'hB100_0002,
                    32'hB100_0003
                );

                expect_packet(
                    32'hA100_0000,
                    32'hA100_0001,
                    32'hA100_0002,
                    32'hA100_0003
                );

            end

        join


        // -------------------------------------------------
        // TEST 3
        // Packet locking under downstream backpressure.
        //
        // Source 0 was the previous completed grant, so
        // simultaneous requests must initially select source 1.
        //
        // Stall after source 1 word 0. Source 0 must remain
        // blocked and source 1 word 1 must remain stable.
        // -------------------------------------------------

        fork

            send_s0_packet(
                32'hA200_0000,
                32'hA200_0001,
                32'hA200_0002,
                32'hA200_0003
            );

            send_s1_packet(
                32'hB200_0000,
                32'hB200_0001,
                32'hB200_0002,
                32'hB200_0003
            );

            begin

                expect_packet(
                    32'hB200_0000,
                    32'hB200_0001,
                    32'hB200_0002,
                    32'hB200_0003
                );

                expect_packet(
                    32'hA200_0000,
                    32'hA200_0001,
                    32'hA200_0002,
                    32'hA200_0003
                );

            end

            begin

                /*
                 * Wait for B200_0000 to transfer.
                 */
                @(posedge aclk);

                while (!(m_axis_tvalid &&
                         m_axis_tready &&
                         m_axis_tdata == 32'hB200_0000))
                    @(posedge aclk);

                /*
                 * Apply backpressure before the next beat.
                 */
                @(negedge aclk);
                m_axis_tready = 1'b0;

                repeat (6) begin

                    @(posedge aclk);
                    #1;

                    if (!m_axis_tvalid) begin
                        $display(
                            "FAIL: TVALID dropped during backpressure"
                        );
                        $fatal;
                    end

                    if (m_axis_tdata !== 32'hB200_0001) begin
                        $display(
                            "FAIL: selected packet changed during stall"
                        );
                        $fatal;
                    end

                    if (m_axis_tlast !== 1'b0) begin
                        $display(
                            "FAIL: TLAST changed during stalled word"
                        );
                        $fatal;
                    end

                    if (s0_axis_tready !== 1'b0) begin
                        $display(
                            "FAIL: unselected source became ready"
                        );
                        $fatal;
                    end

                    if (s1_axis_tready !== 1'b0) begin
                        $display(
                            "FAIL: selected source ready asserted while downstream stalled"
                        );
                        $fatal;
                    end

                end

                @(negedge aclk);
                m_axis_tready = 1'b1;

            end

        join


        // -------------------------------------------------
        // FINAL RESULT
        // -------------------------------------------------

        $display("");
        $display("====================================================");
        $display("2:1 AXI PACKET ARBITER TEST: PASS");
        $display("Single-source forwarding:          PASS");
        $display("Simultaneous request arbitration:  PASS");
        $display("Round-robin priority:              PASS");
        $display("Packet locking through TLAST:      PASS");
        $display("Backpressure stability:            PASS");
        $display("Unselected-source isolation:       PASS");
        $display("TKEEP/TLAST integrity:             PASS");
        $display("====================================================");
        $display("");

        $finish;

    end

endmodule
