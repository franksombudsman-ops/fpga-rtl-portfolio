`timescale 1ns/1ps

module tb_mpu6050_axis_packetizer;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg         aresetn = 1'b0;
    reg [111:0] motion_frame = 112'd0;
    reg         motion_valid = 1'b0;
    reg         m_axis_tready = 1'b1;

    wire [31:0] m_axis_tdata;
    wire [3:0]  m_axis_tkeep;
    wire        m_axis_tvalid;
    wire        m_axis_tlast;

    wire [31:0] frame_drop_count;
    wire        overflow_sticky;

    localparam [111:0] FRAME_A =
        112'hFF9C00C840001900012CFED40064;

    localparam [111:0] FRAME_B =
        112'hD9ECDA5C15B4F2B0FE7EFFC1FF94;

    mpu6050_axis_packetizer dut (
        .aclk             (clk),
        .aresetn          (aresetn),

        .motion_frame     (motion_frame),
        .motion_valid     (motion_valid),

        .m_axis_tdata     (m_axis_tdata),
        .m_axis_tkeep     (m_axis_tkeep),
        .m_axis_tvalid    (m_axis_tvalid),
        .m_axis_tready    (m_axis_tready),
        .m_axis_tlast     (m_axis_tlast),

        .frame_drop_count (frame_drop_count),
        .overflow_sticky  (overflow_sticky)
    );

    task automatic send_frame(input [111:0] frame);
        begin
            @(negedge clk);
            motion_frame = frame;
            motion_valid = 1'b1;

            @(posedge clk);
            @(negedge clk);

            motion_valid = 1'b0;
        end
    endtask

    task automatic expect_word(
        input [31:0] expected_data,
        input        expected_last
    );
        begin
            while (!(m_axis_tvalid && m_axis_tready))
                @(negedge clk);

            if (m_axis_tdata !== expected_data) begin
                $display("FAIL: expected %08h received %08h",
                         expected_data, m_axis_tdata);
                $fatal;
            end

            if (m_axis_tkeep !== 4'hF) begin
                $display("FAIL: TKEEP = %h", m_axis_tkeep);
                $fatal;
            end

            if (m_axis_tlast !== expected_last) begin
                $display("FAIL: TLAST incorrect for %08h",
                         expected_data);
                $fatal;
            end

            @(posedge clk);
            @(negedge clk);
        end
    endtask


    initial begin

        repeat (5) @(posedge clk);
        aresetn = 1'b1;

        /* ------------------------------------------
         * Packet 0: normal flow
         * ------------------------------------------ */

        send_frame(FRAME_A);

        expect_word(32'h6050_0001, 1'b0);
        expect_word(32'hFF9C_00C8, 1'b0);
        expect_word(32'h4000_1900, 1'b0);
        expect_word(32'h012C_FED4, 1'b0);
        expect_word(32'h0064_0000, 1'b0);
        expect_word(32'h0000_0000, 1'b0);
        expect_word(32'h5B00_0000, 1'b1);

        $display("FIELD MAPPING: PASS");
        $display("TLAST POSITION: PASS");
        $display("SEQUENCE 0: PASS");

        /* ------------------------------------------
         * Packet 1: deliberate downstream stall
         * ------------------------------------------ */

        m_axis_tready = 1'b0;
        send_frame(FRAME_B);

        if (!m_axis_tvalid ||
            m_axis_tdata !== 32'h6050_0001) begin
            $display("FAIL: packet not held during stall");
            $fatal;
        end

        repeat (5) begin
            @(posedge clk);
            #1;
            if (m_axis_tdata !== 32'h6050_0001 ||
                !m_axis_tvalid ||
                m_axis_tlast) begin
                $display("FAIL: AXIS changed while stalled");
                $fatal;
            end
        end

        $display("BACKPRESSURE STABILITY: PASS");

        /*
         * Present another sensor frame while stalled.
         * It must be counted as a drop and must not
         * overwrite FRAME_B already being transmitted.
         */
        @(negedge clk);
        motion_frame = FRAME_A;
        motion_valid = 1'b1;

        @(posedge clk);
        @(negedge clk);
        motion_valid = 1'b0;

        if (frame_drop_count !== 32'd1 ||
            overflow_sticky !== 1'b1) begin
            $display("FAIL: drop monitor incorrect");
            $fatal;
        end

        $display("DROP MONITOR: PASS");

        m_axis_tready = 1'b1;

        expect_word(32'h6050_0001, 1'b0);
        expect_word(32'hD9EC_DA5C, 1'b0);
        expect_word(32'h15B4_F2B0, 1'b0);
        expect_word(32'hFE7E_FFC1, 1'b0);
        expect_word(32'hFF94_0000, 1'b0);
        expect_word(32'h0000_0001, 1'b0);
        expect_word(32'h5B00_0001, 1'b1);

        $display("FRAME RETENTION UNDER STALL: PASS");
        $display("SEQUENCE INCREMENT: PASS");

        $display("");
        $display("==========================================");
        $display(" MPU6050 AXI4-STREAM PACKETIZER: PASS");
        $display(" 7-word packet contract     : PASS");
        $display(" Motion-field mapping       : PASS");
        $display(" AXIS backpressure          : PASS");
        $display(" TLAST integrity            : PASS");
        $display(" Frame-drop monitor         : PASS");
        $display(" Sequence progression       : PASS");
        $display("==========================================");

        $finish;
    end

    initial begin
        #100000;
        $display("FAIL: simulation timeout");
        $fatal;
    end

endmodule
