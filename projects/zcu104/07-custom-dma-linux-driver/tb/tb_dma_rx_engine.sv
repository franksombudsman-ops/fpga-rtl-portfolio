`timescale 1ns/1ps

module tb_dma_rx_engine;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn;

    logic        work_valid;
    logic        work_ready;
    logic [63:0] work_buffer_addr;
    logic [31:0] work_length;
    logic [31:0] work_control;
    logic [63:0] work_cookie;
    logic        work_irq_on_completion;
    logic        work_end_of_packet;

    logic        retire_valid;
    logic        retire_ready;
    logic [31:0] retire_status;
    logic [31:0] retire_actual_length;

    logic [63:0] axis_data;
    logic [7:0]  axis_keep;
    logic        axis_valid;
    logic        axis_ready;
    logic        axis_last;

    logic        wr_req_valid;
    logic        wr_req_ready;
    logic [39:0] wr_req_addr;
    logic [31:0] wr_req_bytes;

    logic [63:0] wr_data;
    logic [7:0]  wr_keep;
    logic        wr_data_valid;
    logic        wr_data_ready;

    logic        wr_cpl_valid;
    logic        wr_cpl_ready;
    logic        wr_cpl_error;
    logic [3:0]  wr_cpl_error_code;
    logic [31:0] wr_cpl_bytes;

    logic [3:0]  awid;
    logic [39:0] awaddr;
    logic [7:0]  awlen;
    logic [2:0]  awsize;
    logic [1:0]  awburst;
    logic        awlock;
    logic [3:0]  awcache;
    logic [2:0]  awprot;
    logic [3:0]  awqos;
    logic        awvalid;
    logic        awready;

    logic [63:0] wdata;
    logic [7:0]  wstrb;
    logic        wlast;
    logic        wvalid;
    logic        wready;

    logic [3:0]  bid;
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    dma_rx_engine rx_engine (
        .clk                    (clk),
        .aresetn                (aresetn),

        .work_valid             (work_valid),
        .work_ready             (work_ready),
        .work_buffer_addr       (work_buffer_addr),
        .work_length            (work_length),
        .work_control           (work_control),
        .work_cookie            (work_cookie),
        .work_irq_on_completion (work_irq_on_completion),
        .work_end_of_packet     (work_end_of_packet),

        .retire_valid           (retire_valid),
        .retire_ready           (retire_ready),
        .retire_status          (retire_status),
        .retire_actual_length   (retire_actual_length),

        .s_axis_tdata           (axis_data),
        .s_axis_tkeep           (axis_keep),
        .s_axis_tvalid          (axis_valid),
        .s_axis_tready          (axis_ready),
        .s_axis_tlast           (axis_last),

        .wr_req_valid           (wr_req_valid),
        .wr_req_ready           (wr_req_ready),
        .wr_req_addr            (wr_req_addr),
        .wr_req_bytes           (wr_req_bytes),

        .wr_data                (wr_data),
        .wr_keep                (wr_keep),
        .wr_data_valid          (wr_data_valid),
        .wr_data_ready          (wr_data_ready),

        .wr_cpl_valid           (wr_cpl_valid),
        .wr_cpl_ready           (wr_cpl_ready),
        .wr_cpl_error           (wr_cpl_error),
        .wr_cpl_error_code      (wr_cpl_error_code),
        .wr_cpl_bytes           (wr_cpl_bytes)
    );

    dma_axi_write_master write_master (
        .clk              (clk),
        .aresetn          (aresetn),

        .req_valid        (wr_req_valid),
        .req_ready        (wr_req_ready),
        .req_addr         (wr_req_addr),
        .req_bytes        (wr_req_bytes),

        .s_data           (wr_data),
        .s_keep           (wr_keep),
        .s_valid          (wr_data_valid),
        .s_ready          (wr_data_ready),

        .cpl_valid        (wr_cpl_valid),
        .cpl_ready        (wr_cpl_ready),
        .cpl_error        (wr_cpl_error),
        .cpl_error_code   (wr_cpl_error_code),
        .cpl_bytes        (wr_cpl_bytes),

        .m_axi_awid       (awid),
        .m_axi_awaddr     (awaddr),
        .m_axi_awlen      (awlen),
        .m_axi_awsize     (awsize),
        .m_axi_awburst    (awburst),
        .m_axi_awlock     (awlock),
        .m_axi_awcache    (awcache),
        .m_axi_awprot     (awprot),
        .m_axi_awqos      (awqos),
        .m_axi_awvalid    (awvalid),
        .m_axi_awready    (awready),

        .m_axi_wdata      (wdata),
        .m_axi_wstrb      (wstrb),
        .m_axi_wlast      (wlast),
        .m_axi_wvalid     (wvalid),
        .m_axi_wready     (wready),

        .m_axi_bid        (bid),
        .m_axi_bresp      (bresp),
        .m_axi_bvalid     (bvalid),
        .m_axi_bready     (bready)
    );

    logic [7:0] mem [0:65535];

    function automatic [63:0] payload_pattern(
        input integer byte_offset
    );

        begin

            payload_pattern =
                64'h5A3C_9000_0000_0000 ^
                byte_offset;

        end

    endfunction

    function automatic [63:0] mem_read64(
        input logic [39:0] address
    );

        integer n;

        begin

            mem_read64 = 64'd0;

            for (n = 0; n < 8; n = n + 1)
                mem_read64[n*8 +: 8] =
                    mem[(address[15:0] + n) & 16'hFFFF];

        end

    endfunction

    logic [31:0] lfsr;

    always_ff @(posedge clk) begin

        if (!aresetn)
            lfsr <= 32'h93C7_14A5;
        else
            lfsr <= {
                lfsr[30:0],
                lfsr[31] ^
                lfsr[21] ^
                lfsr[1] ^
                lfsr[0]
            };

    end

    /*
     * Write-response error injection:
     *
     * 0 normal
     * 1 SLVERR
     * 2 DECERR
     */
    integer inject_mode;

    logic        wr_active;
    logic [39:0] wr_base;
    integer      wr_beats;
    integer      wr_index;

    logic        response_pending;
    integer      response_delay;

    integer aw_count;
    integer b_count;
    integer byte_index;

    assign awready =
        !wr_active &&
        !response_pending &&
        !bvalid &&
        (lfsr[2] | lfsr[7]);

    assign wready =
        wr_active &&
        (lfsr[3] | lfsr[8]);

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            wr_active <= 1'b0;
            wr_base   <= 40'd0;
            wr_beats  <= 0;
            wr_index  <= 0;

            response_pending <= 1'b0;
            response_delay   <= 0;

            bid    <= 4'd0;
            bresp  <= 2'b00;
            bvalid <= 1'b0;

            aw_count <= 0;
            b_count  <= 0;

        end
        else begin

            if (awvalid &&
                awready) begin

                if (awid !== 0 ||
                    awsize !== 3'b011 ||
                    awburst !== 2'b01) begin

                    $display(
                        "FAIL: RX AXI write attributes"
                    );

                    $fatal;
                end

                if ((awaddr[11:0] +
                    ((awlen + 1) * 8)) > 4096) begin

                    $display(
                        "FAIL: RX write crosses 4-KiB boundary"
                    );

                    $fatal;
                end

                wr_active <=
                    1'b1;

                wr_base <=
                    awaddr;

                wr_beats <=
                    awlen + 1;

                wr_index <=
                    0;

                aw_count <=
                    aw_count + 1;

            end

            if (wvalid &&
                wready) begin

                if (!wr_active) begin

                    $display(
                        "FAIL: RX W without AW"
                    );

                    $fatal;

                end

                if (wstrb !==
                    8'hFF) begin

                    $display(
                        "FAIL: RX WSTRB"
                    );

                    $fatal;

                end

                if (wlast !==
                    (wr_index ==
                     (wr_beats - 1))) begin

                    $display(
                        "FAIL: RX WLAST"
                    );

                    $fatal;

                end

                for (byte_index = 0;
                     byte_index < 8;
                     byte_index = byte_index + 1) begin

                    if (wstrb[byte_index]) begin

                        mem[
                            (
                                wr_base[15:0] +
                                (wr_index * 8) +
                                byte_index
                            ) & 16'hFFFF
                        ] <=
                            wdata[
                                byte_index*8 +: 8
                            ];

                    end

                end

                if (wr_index ==
                    (wr_beats - 1)) begin

                    wr_active <=
                        1'b0;

                    response_pending <=
                        1'b1;

                    response_delay <=
                        1 + lfsr[11:10];

                end
                else begin

                    wr_index <=
                        wr_index + 1;

                end

            end

            if (response_pending &&
                !bvalid) begin

                if (response_delay != 0) begin

                    response_delay <=
                        response_delay - 1;

                end
                else begin

                    bid   <= 4'd0;
                    bresp <= 2'b00;

                    if (inject_mode == 1)
                        bresp <= 2'b10;

                    if (inject_mode == 2)
                        bresp <= 2'b11;

                    bvalid <=
                        1'b1;

                    response_pending <=
                        1'b0;

                end

            end

            if (bvalid &&
                bready) begin

                bvalid <=
                    1'b0;

                b_count <=
                    b_count + 1;

            end

        end

    end

    /*
     * Verify source-facing AXIS stability expectations by driving
     * data exactly as a compliant source must: while VALID and
     * !READY, payload remains unchanged.
     */

    task automatic issue_work(
        input logic [63:0] address,
        input logic [31:0] capacity
    );

        begin

            @(negedge clk);

            work_buffer_addr =
                address;

            work_length =
                capacity;

            work_control =
                32'h0000_0001;

            work_cookie =
                64'h8877_6655_4433_2211;

            work_irq_on_completion =
                1'b1;

            work_end_of_packet =
                1'b1;

            work_valid =
                1'b1;

            do begin
                @(posedge clk);
            end while (!work_ready);

            @(negedge clk);

            work_valid =
                1'b0;

        end

    endtask

    task automatic send_packet(
        input integer packet_bytes
    );

        integer offset;

        begin

            offset = 0;

            while (offset < packet_bytes) begin

                /*
                 * Random source-side gaps.
                 */
                while (!(lfsr[5] |
                         lfsr[12]))
                    @(posedge clk);

                @(negedge clk);

                axis_data =
                    payload_pattern(offset);

                axis_keep =
                    8'hFF;

                axis_last =
                    ((offset + 8) ==
                     packet_bytes);

                axis_valid =
                    1'b1;

                do begin
                    @(posedge clk);
                end while (!axis_ready);

                @(negedge clk);

                axis_valid =
                    1'b0;

                offset =
                    offset + 8;

            end

        end

    endtask

    task automatic send_bad_keep_packet;

        begin

            /*
             * First beat is valid.
             */
            @(negedge clk);

            axis_data =
                payload_pattern(0);

            axis_keep =
                8'hFF;

            axis_last =
                1'b0;

            axis_valid =
                1'b1;

            do begin
                @(posedge clk);
            end while (!axis_ready);

            @(negedge clk);

            axis_valid =
                1'b0;

            /*
             * Second/final beat has illegal partial TKEEP.
             */
            @(negedge clk);

            axis_data =
                payload_pattern(8);

            axis_keep =
                8'h0F;

            axis_last =
                1'b1;

            axis_valid =
                1'b1;

            do begin
                @(posedge clk);
            end while (!axis_ready);

            @(negedge clk);

            axis_valid =
                1'b0;

            axis_keep =
                8'hFF;

            axis_last =
                1'b0;

        end

    endtask

    task automatic consume_retirement;

        integer hold_cycle;
        logic [31:0] saved_status;
        logic [31:0] saved_actual;

        begin

            while (!retire_valid)
                @(posedge clk);

            saved_status =
                retire_status;

            saved_actual =
                retire_actual_length;

            for (hold_cycle = 0;
                 hold_cycle < 4;
                 hold_cycle = hold_cycle + 1) begin

                @(posedge clk);
                #1;

                if (!retire_valid ||
                    retire_status !== saved_status ||
                    retire_actual_length !== saved_actual) begin

                    $display(
                        "FAIL: RX retirement changed while stalled"
                    );

                    $fatal;

                end

            end

            @(negedge clk);

            retire_ready =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            retire_ready =
                1'b0;

        end

    endtask

    task automatic verify_memory(
        input logic [39:0] address,
        input integer      bytes
    );

        integer offset;

        begin

            for (offset = 0;
                 offset < bytes;
                 offset = offset + 8) begin

                if (mem_read64(
                        address + offset
                    ) !==
                    payload_pattern(offset)) begin

                    $display(
                        "FAIL RX DDR address=%h offset=%0d got=%h expected=%h",
                        address,
                        offset,
                        mem_read64(
                            address + offset
                        ),
                        payload_pattern(offset)
                    );

                    $fatal;

                end

            end

        end

    endtask

    task automatic run_success(
        input logic [63:0] address,
        input logic [31:0] capacity,
        input integer      packet_bytes
    );

        integer aw_before;

        begin

            inject_mode =
                0;

            aw_before =
                aw_count;

            fork

                issue_work(
                    address,
                    capacity
                );

                send_packet(
                    packet_bytes
                );

            join

            while (!retire_valid)
                @(posedge clk);

            if (retire_status !==
                32'h0000_0001) begin

                $display(
                    "FAIL: RX success status=%h",
                    retire_status
                );

                $fatal;

            end

            if (retire_actual_length !==
                packet_bytes) begin

                $display(
                    "FAIL RX actual=%0d expected=%0d",
                    retire_actual_length,
                    packet_bytes
                );

                $fatal;

            end

            if (aw_count ==
                aw_before) begin

                $display(
                    "FAIL: RX generated no DDR write"
                );

                $fatal;

            end

            verify_memory(
                address[39:0],
                packet_bytes
            );

            consume_retirement();

        end

    endtask

    task automatic run_overflow;

        begin

            inject_mode =
                0;

            fork

                issue_work(
                    64'h0000_0000_0000_5000,
                    32'd64
                );

                /*
                 * 80-byte packet into 64-byte buffer.
                 */
                send_packet(
                    80
                );

            join

            while (!retire_valid)
                @(posedge clk);

            if (retire_status !==
                32'h0000_0083) begin

                $display(
                    "FAIL: RX overflow status=%h",
                    retire_status
                );

                $fatal;

            end

            if (retire_actual_length !==
                32'd64) begin

                $display(
                    "FAIL RX overflow actual=%0d expected=64",
                    retire_actual_length
                );

                $fatal;

            end

            verify_memory(
                40'h0000_5000,
                64
            );

            consume_retirement();

        end

    endtask

    task automatic run_write_error(
        input integer mode
    );

        begin

            inject_mode =
                mode;

            fork

                issue_work(
                    64'h0000_0000_0000_6000,
                    32'd64
                );

                send_packet(
                    64
                );

            join

            while (!retire_valid)
                @(posedge clk);

            if (retire_status !==
                32'h0000_000B) begin

                $display(
                    "FAIL RX write-error status=%h",
                    retire_status
                );

                $fatal;

            end

            /*
             * One 64-byte AXI burst failed its BRESP, so no bytes
             * are counted as known-good committed bytes.
             *
             * Memory itself is deliberately NOT checked for rollback.
             */
            if (retire_actual_length !==
                32'd0) begin

                $display(
                    "FAIL RX write-error actual=%0d expected=0",
                    retire_actual_length
                );

                $fatal;

            end

            consume_retirement();

            inject_mode =
                0;

        end

    endtask

    task automatic run_bad_keep;

        begin

            inject_mode =
                0;

            fork

                issue_work(
                    64'h0000_0000_0000_7000,
                    32'd64
                );

                send_bad_keep_packet();

            join

            while (!retire_valid)
                @(posedge clk);

            if (retire_status !==
                32'h0000_0103) begin

                $display(
                    "FAIL RX bad-TKEEP status=%h",
                    retire_status
                );

                $fatal;

            end

            if (retire_actual_length !==
                32'd8) begin

                $display(
                    "FAIL RX bad-TKEEP actual=%0d expected=8",
                    retire_actual_length
                );

                $fatal;

            end

            verify_memory(
                40'h0000_7000,
                8
            );

            consume_retirement();

        end

    endtask

    task automatic run_invalid_work(
        input logic [63:0] address,
        input logic [31:0] capacity,
        input logic [31:0] expected_status
    );

        integer aw_before;

        begin

            aw_before =
                aw_count;

            issue_work(
                address,
                capacity
            );

            while (!retire_valid)
                @(posedge clk);

            if (retire_status !==
                expected_status) begin

                $display(
                    "FAIL RX invalid status got=%h expected=%h",
                    retire_status,
                    expected_status
                );

                $fatal;

            end

            if (retire_actual_length !==
                0) begin

                $display(
                    "FAIL: invalid RX work transferred bytes"
                );

                $fatal;

            end

            if (aw_count !=
                aw_before) begin

                $display(
                    "FAIL: invalid RX work generated AXI writes"
                );

                $fatal;

            end

            consume_retirement();

        end

    endtask

    integer i;

    initial begin

        for (i = 0;
             i < 65536;
             i = i + 1)
            mem[i] = 8'd0;

        aresetn =
            1'b0;

        work_valid =
            1'b0;

        work_buffer_addr =
            64'd0;

        work_length =
            32'd0;

        work_control =
            32'd0;

        work_cookie =
            64'd0;

        work_irq_on_completion =
            1'b0;

        work_end_of_packet =
            1'b0;

        retire_ready =
            1'b0;

        axis_data =
            64'd0;

        axis_keep =
            8'hFF;

        axis_valid =
            1'b0;

        axis_last =
            1'b0;

        inject_mode =
            0;

        repeat (10)
            @(posedge clk);

        aresetn =
            1'b1;

        repeat (5)
            @(posedge clk);

        /*
         * Minimum full-capacity packet.
         */
        run_success(
            64'h0000_0000_0000_1000,
            32'd8,
            8
        );

        /*
         * Packet shorter than supplied RX buffer.
         */
        run_success(
            64'h0000_0000_0000_1800,
            32'd256,
            64
        );

        $display(
            "BASIC / SHORT RX PAYLOADS: PASS"
        );

        /*
         * Two 2-KiB staging chunks.
         */
        run_success(
            64'h0000_0000_0000_2000,
            32'd4096,
            4096
        );

        $display(
            "MULTI-CHUNK RX: PASS"
        );

        /*
         * Destination starts 16 bytes before 4-KiB boundary.
         * dma_axi_write_master must split legal AW transactions.
         */
        run_success(
            64'h0000_0000_0000_1FF0,
            32'd8192,
            8192
        );

        $display(
            "4-KiB CROSSING RX: PASS"
        );

        run_overflow();

        $display(
            "RX OVERFLOW / DRAIN: PASS"
        );

        run_bad_keep();

        $display(
            "RX TKEEP MISMATCH: PASS"
        );

        run_write_error(1);

        $display(
            "RX SLVERR PROPAGATION: PASS"
        );

        run_write_error(2);

        $display(
            "RX DECERR PROPAGATION: PASS"
        );

        /*
         * Defensive work validation.
         */

        run_invalid_work(
            64'h0000_0000_0000_1001,
            32'd64,
            32'h0000_0013
        );

        run_invalid_work(
            64'h0000_0000_0000_1000,
            32'd0,
            32'h0000_0023
        );

        run_invalid_work(
            64'h0000_0000_0000_1000,
            32'd15,
            32'h0000_0023
        );

        run_invalid_work(
            64'h0000_0100_0000_1000,
            32'd64,
            32'h0000_0043
        );

        $display(
            "RX WORK VALIDATION: PASS"
        );

        $display("");
        $display("=============================================");
        $display(" DMA RX ENGINE: PASS");
        $display(" AXIS -> DDR payload movement : PASS");
        $display(" short-packet receive         : PASS");
        $display(" exact payload ordering       : PASS");
        $display(" randomized source gaps       : PASS");
        $display(" randomized DDR backpressure  : PASS");
        $display(" multi-chunk receive          : PASS");
        $display(" 4-KiB write splitting        : PASS");
        $display(" descriptor-capacity overflow : PASS");
        $display(" post-overflow packet drain   : PASS");
        $display(" TKEEP mismatch detection     : PASS");
        $display(" AXI SLVERR propagation       : PASS");
        $display(" AXI DECERR propagation       : PASS");
        $display(" invalid-work rejection       : PASS");
        $display(" retirement backpressure      : PASS");
        $display("=============================================");

        $finish;

    end

    initial begin

        #30_000_000;

        $display(
            "FAIL: RX engine timeout / possible deadlock"
        );

        $fatal;

    end

endmodule
