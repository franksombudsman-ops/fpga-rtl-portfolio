`timescale 1ns/1ps

module tb_ad1_axis_packetizer;

    reg         aclk = 0;
    reg         aresetn = 0;
    reg [11:0]  sample_a = 0;
    reg [11:0]  sample_b = 0;
    reg         sample_valid = 0;
    reg         m_axis_tready = 0;

    wire [31:0] m_axis_tdata;
    wire [3:0]  m_axis_tkeep;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;

    always #20 aclk = ~aclk;   // 25 MHz

    ad1_axis_packetizer dut (
        .aclk           (aclk),
        .aresetn        (aresetn),
        .sample_a       (sample_a),
        .sample_b       (sample_b),
        .sample_valid   (sample_valid),
        .m_axis_tdata   (m_axis_tdata),
        .m_axis_tkeep   (m_axis_tkeep),
        .m_axis_tvalid  (m_axis_tvalid),
        .m_axis_tready  (m_axis_tready),
        .m_axis_tlast   (m_axis_tlast)
    );

    task pulse_sample(
        input [11:0] a,
        input [11:0] b
    );
    begin
        @(negedge aclk);
        sample_a = a;
        sample_b = b;
        sample_valid = 1'b1;

        @(negedge aclk);
        sample_valid = 1'b0;
    end
    endtask

    task expect_transfer(
        input [31:0] expected_data,
        input        expected_last
    );
    begin
        // Wait for the actual AXI handshake clock edge.
        @(posedge aclk);

        while (!(m_axis_tvalid && m_axis_tready))
            @(posedge aclk);

        if (m_axis_tdata !== expected_data) begin
            $display("FAIL: expected %08h, received %08h",
                     expected_data, m_axis_tdata);
            $fatal;
        end

        if (m_axis_tlast !== expected_last) begin
            $display("FAIL: TLAST mismatch");
            $fatal;
        end

        if (m_axis_tkeep !== 4'hF) begin
            $display("FAIL: TKEEP mismatch");
            $fatal;
        end

        // Let DUT nonblocking assignments complete before
        // the caller starts checking the next AXI beat.
        #1;
    end
    endtask

    initial begin
        repeat (5) @(posedge aclk);
        aresetn = 1'b1;

        repeat (2) @(posedge aclk);

        // -------------------------------------------------
        // Packet 0: values observed during live AD1 testing
        // -------------------------------------------------
        pulse_sample(12'hA04, 12'h810);

        m_axis_tready = 1'b1;

        expect_transfer(32'hAD10_0001, 1'b0);

        // Apply AXI backpressure before word 1.
        @(negedge aclk);
        m_axis_tready = 1'b0;

        repeat (5) begin
            @(posedge aclk);

            if (!m_axis_tvalid) begin
                $display("FAIL: TVALID dropped during backpressure");
                $fatal;
            end

            if (m_axis_tdata !== 32'h00A0_4810) begin
                $display("FAIL: TDATA changed during backpressure");
                $fatal;
            end
        end

        @(negedge aclk);
        m_axis_tready = 1'b1;

        expect_transfer(32'h00A0_4810, 1'b0);
        expect_transfer(32'h0000_0000, 1'b0);
        expect_transfer(32'h5A00_0000, 1'b1);

        // -------------------------------------------------
        // Packet 1: prove sequence counter increments
        // -------------------------------------------------
        pulse_sample(12'h123, 12'h456);

        expect_transfer(32'hAD10_0001, 1'b0);
        expect_transfer(32'h0012_3456, 1'b0);
        expect_transfer(32'h0000_0001, 1'b0);
        expect_transfer(32'h5A00_0001, 1'b1);

        $display("");
        $display("============================================");
        $display("AD1 AXI PACKETIZER TEST: PASS");
        $display("Sample packing:              PASS");
        $display("AXI backpressure stability:  PASS");
        $display("TKEEP/TLAST framing:         PASS");
        $display("Sequence increment:          PASS");
        $display("============================================");

        $finish;
    end

endmodule
