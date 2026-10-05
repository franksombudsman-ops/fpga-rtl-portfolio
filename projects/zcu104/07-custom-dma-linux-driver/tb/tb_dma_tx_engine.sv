`timescale 1ns/1ps

module tb_dma_tx_engine;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn;

    /*
     * Work interface.
     */
    logic        work_valid;
    logic        work_ready;

    logic [63:0] work_buffer_addr;
    logic [31:0] work_length;
    logic [31:0] work_control;
    logic [63:0] work_cookie;
    logic        work_irq_on_completion;
    logic        work_end_of_packet;

    /*
     * Retirement.
     */
    logic        retire_valid;
    logic        retire_ready;
    logic [31:0] retire_status;
    logic [31:0] retire_actual_length;

    /*
     * AXIS output.
     */
    logic [63:0] axis_data;
    logic [7:0]  axis_keep;
    logic        axis_valid;
    logic        axis_ready;
    logic        axis_last;

    /*
     * TX -> read-master interface.
     */
    logic        rd_req_valid;
    logic        rd_req_ready;
    logic [39:0] rd_req_addr;
    logic [31:0] rd_req_bytes;

    logic [63:0] rd_data;
    logic [7:0]  rd_data_keep;
    logic        rd_data_valid;
    logic        rd_data_ready;
    logic        rd_data_last;

    logic        rd_cpl_valid;
    logic        rd_cpl_ready;
    logic        rd_cpl_error;
    logic [3:0]  rd_cpl_error_code;
    logic [31:0] rd_cpl_bytes;

    /*
     * AXI read interface.
     */
    logic [3:0]  arid;
    logic [39:0] araddr;
    logic [7:0]  arlen;
    logic [2:0]  arsize;
    logic [1:0]  arburst;
    logic        arlock;
    logic [3:0]  arcache;
    logic [2:0]  arprot;
    logic [3:0]  arqos;
    logic        arvalid;
    logic        arready;

    logic [3:0]  rid;
    logic [63:0] rdata;
    logic [1:0]  rresp;
    logic        rlast;
    logic        rvalid;
    logic        rready;

    dma_tx_engine tx_engine (
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

        .m_axis_tdata           (axis_data),
        .m_axis_tkeep           (axis_keep),
        .m_axis_tvalid          (axis_valid),
        .m_axis_tready          (axis_ready),
        .m_axis_tlast           (axis_last),

        .rd_req_valid           (rd_req_valid),
        .rd_req_ready           (rd_req_ready),
        .rd_req_addr            (rd_req_addr),
        .rd_req_bytes           (rd_req_bytes),

        .rd_data                (rd_data),
        .rd_data_keep           (rd_data_keep),
        .rd_data_valid          (rd_data_valid),
        .rd_data_ready          (rd_data_ready),
        .rd_data_last           (rd_data_last),

        .rd_cpl_valid           (rd_cpl_valid),
        .rd_cpl_ready           (rd_cpl_ready),
        .rd_cpl_error           (rd_cpl_error),
        .rd_cpl_error_code      (rd_cpl_error_code),
        .rd_cpl_bytes           (rd_cpl_bytes)
    );

    dma_axi_read_master read_master (
        .clk              (clk),
        .aresetn          (aresetn),

        .req_valid        (rd_req_valid),
        .req_ready        (rd_req_ready),
        .req_addr         (rd_req_addr),
        .req_bytes        (rd_req_bytes),

        .m_data           (rd_data),
        .m_keep           (rd_data_keep),
        .m_valid          (rd_data_valid),
        .m_ready          (rd_data_ready),
        .m_last           (rd_data_last),

        .cpl_valid        (rd_cpl_valid),
        .cpl_ready        (rd_cpl_ready),
        .cpl_error        (rd_cpl_error),
        .cpl_error_code   (rd_cpl_error_code),
        .cpl_bytes        (rd_cpl_bytes),

        .m_axi_arid       (arid),
        .m_axi_araddr     (araddr),
        .m_axi_arlen      (arlen),
        .m_axi_arsize     (arsize),
        .m_axi_arburst    (arburst),
        .m_axi_arlock     (arlock),
        .m_axi_arcache    (arcache),
        .m_axi_arprot     (arprot),
        .m_axi_arqos      (arqos),
        .m_axi_arvalid    (arvalid),
        .m_axi_arready    (arready),

        .m_axi_rid        (rid),
        .m_axi_rdata      (rdata),
        .m_axi_rresp      (rresp),
        .m_axi_rlast      (rlast),
        .m_axi_rvalid     (rvalid),
        .m_axi_rready     (rready)
    );

    /*
     * Deterministic pseudo-random stalls.
     */
    logic [31:0] lfsr;

    always_ff @(posedge clk) begin

        if (!aresetn)
            lfsr <= 32'hA731_5C9D;
        else
            lfsr <= {
                lfsr[30:0],
                lfsr[31] ^
                lfsr[21] ^
                lfsr[1]  ^
                lfsr[0]
            };

    end

    /*
     * Random AXIS consumer backpressure.
     */
    assign axis_ready =
        lfsr[4] | lfsr[9];

    function automatic [63:0] memory_pattern(
        input logic [39:0] address
    );

        begin

            memory_pattern =
                64'h7A5A_0000_0000_0000 ^
                {{24{1'b0}}, address};

        end

    endfunction

    /*
     * AXI error injection:
     *
     * 0 normal
     * 1 SLVERR
     * 2 DECERR
     */
    integer inject_mode;

    logic        mem_active;
    logic [39:0] mem_addr;
    integer      mem_beats;
    integer      mem_index;

    integer ar_count;

    assign arready =
        !mem_active &&
        (lfsr[1] | lfsr[6]);

    /*
     * Behavioral DDR read slave.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            mem_active <= 1'b0;
            mem_addr   <= 40'd0;
            mem_beats  <= 0;
            mem_index  <= 0;

            rid    <= 4'd0;
            rdata  <= 64'd0;
            rresp  <= 2'b00;
            rlast  <= 1'b0;
            rvalid <= 1'b0;

            ar_count <= 0;

        end
        else begin

            if (arvalid &&
                arready) begin

                if (arid !== 0) begin
                    $display("FAIL: TX ARID");
                    $fatal;
                end

                if (arsize !== 3'b011) begin
                    $display("FAIL: TX ARSIZE");
                    $fatal;
                end

                if (arburst !== 2'b01) begin
                    $display("FAIL: TX ARBURST");
                    $fatal;
                end

                if ((araddr[11:0] +
                    ((arlen + 1) * 8)) > 4096) begin

                    $display(
                        "FAIL: TX read burst crosses 4-KiB"
                    );

                    $fatal;
                end

                mem_active <= 1'b1;
                mem_addr   <= araddr;
                mem_beats  <= arlen + 1;
                mem_index  <= 0;

                ar_count <= ar_count + 1;

            end

            /*
             * Insert random RVALID gaps.
             */
            if (mem_active &&
                !rvalid &&
                (lfsr[2] | lfsr[7])) begin

                rid <= 4'd0;

                rdata <=
                    memory_pattern(
                        mem_addr +
                        (mem_index * 8)
                    );

                rresp <= 2'b00;

                if ((inject_mode == 1) &&
                    (mem_index == 2))
                    rresp <= 2'b10;

                if ((inject_mode == 2) &&
                    (mem_index == 2))
                    rresp <= 2'b11;

                rlast <=
                    (mem_index ==
                     (mem_beats - 1));

                rvalid <= 1'b1;

            end

            /*
             * R-channel stability naturally results because these
             * registers change only after handshake.
             */
            if (rvalid &&
                rready) begin

                if (rlast) begin

                    mem_active <= 1'b0;

                end
                else begin

                    mem_index <=
                        mem_index + 1;

                end

                rvalid <= 1'b0;

            end

        end

    end

    /*
     * Explicit AXIS stability monitor.
     *
     * If the downstream consumer stalls, TDATA/TKEEP/TLAST/TVALID
     * must remain unchanged until the handshake occurs.
     */
    logic        axis_was_stalled;
    logic [63:0] saved_axis_data;
    logic [7:0]  saved_axis_keep;
    logic        saved_axis_last;

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            axis_was_stalled <= 1'b0;

        end
        else begin

            if (axis_was_stalled) begin

                if (!axis_valid ||
                    axis_data !== saved_axis_data ||
                    axis_keep !== saved_axis_keep ||
                    axis_last !== saved_axis_last) begin

                    $display(
                        "FAIL: AXIS TX changed while stalled"
                    );

                    $fatal;

                end

            end

            axis_was_stalled <=
                axis_valid &&
                !axis_ready;

            if (axis_valid &&
                !axis_ready) begin

                saved_axis_data <=
                    axis_data;

                saved_axis_keep <=
                    axis_keep;

                saved_axis_last <=
                    axis_last;

            end

        end

    end

    task automatic issue_work(
        input logic [63:0] address,
        input logic [31:0] length
    );

        begin

            @(negedge clk);

            work_buffer_addr =
                address;

            work_length =
                length;

            work_control =
                32'h0000_0007;

            work_cookie =
                64'h1234_5678_9ABC_DEF0;

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

            /*
             * Deliberately stall retirement and prove the
             * result remains stable.
             */
            for (hold_cycle = 0;
                 hold_cycle < 4;
                 hold_cycle = hold_cycle + 1) begin

                @(posedge clk);
                #1;

                if (!retire_valid ||
                    retire_status !== saved_status ||
                    retire_actual_length !== saved_actual) begin

                    $display(
                        "FAIL: TX retirement changed under stall"
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

    task automatic run_success(
        input logic [63:0] address,
        input logic [31:0] length
    );

        integer received;
        integer ar_before;
        integer last_count;

        begin

            inject_mode = 0;

            received   = 0;
            last_count = 0;
            ar_before  = ar_count;

            issue_work(
                address,
                length
            );

            while (!retire_valid) begin

                @(posedge clk);

                if (axis_valid &&
                    axis_ready) begin

                    if (axis_data !==
                        memory_pattern(
                            address[39:0] +
                            received
                        )) begin

                        $display(
                            "FAIL TX DATA address=%h offset=%0d got=%h expected=%h",
                            address,
                            received,
                            axis_data,
                            memory_pattern(
                                address[39:0] +
                                received
                            )
                        );

                        $fatal;

                    end

                    if (axis_keep !==
                        8'hFF) begin

                        $display(
                            "FAIL: TX TKEEP"
                        );

                        $fatal;

                    end

                    if (axis_last)
                        last_count =
                            last_count + 1;

                    if (axis_last !==
                        ((received + 8) ==
                         length)) begin

                        $display(
                            "FAIL: TX TLAST position"
                        );

                        $fatal;

                    end

                    received =
                        received + 8;

                end

            end

            if (retire_status !==
                32'h0000_0001) begin

                $display(
                    "FAIL: successful TX status=%h",
                    retire_status
                );

                $fatal;

            end

            if (retire_actual_length !==
                length) begin

                $display(
                    "FAIL: TX actual length got=%0d expected=%0d",
                    retire_actual_length,
                    length
                );

                $fatal;

            end

            if (received !==
                length) begin

                $display(
                    "FAIL: TX received=%0d expected=%0d",
                    received,
                    length
                );

                $fatal;

            end

            if (last_count != 1) begin

                $display(
                    "FAIL: TX TLAST count=%0d",
                    last_count
                );

                $fatal;

            end

            if (ar_count ==
                ar_before) begin

                $display(
                    "FAIL: TX issued no AXI read"
                );

                $fatal;

            end

            consume_retirement();

        end

    endtask

    task automatic run_read_error(
        input integer mode
    );

        integer received;

        begin

            inject_mode =
                mode;

            received =
                0;

            issue_work(
                64'h0000_0000_0000_4000,
                32'd64
            );

            while (!retire_valid) begin

                @(posedge clk);

                if (axis_valid &&
                    axis_ready)
                    received =
                        received + 8;

            end

            if (retire_status !==
                32'h0000_0007) begin

                $display(
                    "FAIL: TX AXI error status=%h",
                    retire_status
                );

                $fatal;

            end

            /*
             * Error is injected on beat index 2.
             * Beats 0 and 1 may legitimately have already
             * reached the stream consumer.
             */
            if (retire_actual_length !==
                32'd16) begin

                $display(
                    "FAIL: TX error actual length got=%0d expected=16",
                    retire_actual_length
                );

                $fatal;

            end

            if (received != 16) begin

                $display(
                    "FAIL: TX error forwarded bytes=%0d expected=16",
                    received
                );

                $fatal;

            end

            consume_retirement();

            inject_mode =
                0;

        end

    endtask

    task automatic run_invalid_work(
        input logic [63:0] address,
        input logic [31:0] length,
        input logic [31:0] expected_status
    );

        integer ar_before;

        begin

            ar_before =
                ar_count;

            issue_work(
                address,
                length
            );

            while (!retire_valid)
                @(posedge clk);

            if (retire_status !==
                expected_status) begin

                $display(
                    "FAIL invalid work status got=%h expected=%h",
                    retire_status,
                    expected_status
                );

                $fatal;

            end

            if (retire_actual_length !=
                0) begin

                $display(
                    "FAIL: invalid TX work transferred bytes"
                );

                $fatal;

            end

            if (ar_count !=
                ar_before) begin

                $display(
                    "FAIL: invalid TX work generated AXI traffic"
                );

                $fatal;

            end

            consume_retirement();

        end

    endtask

    initial begin

        aresetn = 1'b0;

        work_valid = 1'b0;

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

        inject_mode =
            0;

        repeat (10)
            @(posedge clk);

        aresetn =
            1'b1;

        repeat (5)
            @(posedge clk);

        /*
         * Minimum transfer.
         */
        run_success(
            64'h0000_0000_0000_1000,
            32'd8
        );

        /*
         * Small descriptor.
         */
        run_success(
            64'h0000_0000_0000_1800,
            32'd64
        );

        $display(
            "BASIC TX PAYLOADS: PASS"
        );

        /*
         * Multiple maximum-size AXI bursts.
         */
        run_success(
            64'h0000_0000_0000_2000,
            32'd4096
        );

        $display(
            "MULTI-BURST TX: PASS"
        );

        /*
         * Begin 16 bytes before a 4-KiB boundary.
         * Must split immediately and continue correctly.
         */
        run_success(
            64'h0000_0000_0000_1FF0,
            32'd8192
        );

        $display(
            "4-KiB CROSSING TX: PASS"
        );

        /*
         * AXI read failures must never retire as success.
         */
        run_read_error(1);

        $display(
            "TX SLVERR PROPAGATION: PASS"
        );

        run_read_error(2);

        $display(
            "TX DECERR PROPAGATION: PASS"
        );

        /*
         * Defensive work validation.
         */

        /*
         * COMPLETE + ERROR + ALIGNMENT_ERROR
         * = bits 0,1,4 = 0x13
         */
        run_invalid_work(
            64'h0000_0000_0000_1001,
            32'd64,
            32'h0000_0013
        );

        /*
         * COMPLETE + ERROR + LENGTH_ERROR
         * = bits 0,1,5 = 0x23
         */
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

        /*
         * COMPLETE + ERROR + ADDRESS_ERROR
         * = bits 0,1,6 = 0x43
         */
        run_invalid_work(
            64'h0000_0100_0000_1000,
            32'd64,
            32'h0000_0043
        );

        $display(
            "TX WORK VALIDATION: PASS"
        );

        $display("");
        $display("=============================================");
        $display(" DMA TX ENGINE: PASS");
        $display(" DDR -> AXIS payload movement : PASS");
        $display(" exact byte ordering          : PASS");
        $display(" randomized DDR stalls        : PASS");
        $display(" randomized AXIS backpressure : PASS");
        $display(" AXIS stall stability         : PASS");
        $display(" multi-burst payloads         : PASS");
        $display(" 4-KiB read splitting         : PASS");
        $display(" exact TLAST generation       : PASS");
        $display(" exact completion accounting  : PASS");
        $display(" AXI SLVERR propagation       : PASS");
        $display(" AXI DECERR propagation       : PASS");
        $display(" invalid-work rejection       : PASS");
        $display(" retirement backpressure      : PASS");
        $display("=============================================");

        $finish;

    end

    initial begin

        #20_000_000;

        $display(
            "FAIL: TX engine timeout / possible deadlock"
        );

        $fatal;

    end

endmodule
