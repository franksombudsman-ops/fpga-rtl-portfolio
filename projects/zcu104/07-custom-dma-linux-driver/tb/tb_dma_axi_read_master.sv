`timescale 1ns/1ps

module tb_dma_axi_read_master;

    localparam ADDR_WIDTH   = 40;
    localparam LEN_WIDTH    = 32;
    localparam AXI_ID_WIDTH = 4;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn = 1'b0;

    logic                  req_valid;
    logic                  req_ready;
    logic [39:0]           req_addr;
    logic [31:0]           req_bytes;

    logic [63:0]           m_data;
    logic [7:0]            m_keep;
    logic                  m_valid;
    logic                  m_ready;
    logic                  m_last;

    logic                  cpl_valid;
    logic                  cpl_ready;
    logic                  cpl_error;
    logic [3:0]            cpl_error_code;
    logic [31:0]           cpl_bytes;

    logic [3:0]            arid;
    logic [39:0]           araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arlock;
    logic [3:0]            arcache;
    logic [2:0]            arprot;
    logic [3:0]            arqos;
    logic                  arvalid;
    logic                  arready;

    logic [3:0]            rid;
    logic [63:0]           rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic                  rvalid;
    logic                  rready;

    dma_axi_read_master dut (
        .clk              (clk),
        .aresetn          (aresetn),

        .req_valid        (req_valid),
        .req_ready        (req_ready),
        .req_addr         (req_addr),
        .req_bytes        (req_bytes),

        .m_data           (m_data),
        .m_keep           (m_keep),
        .m_valid          (m_valid),
        .m_ready          (m_ready),
        .m_last           (m_last),

        .cpl_valid        (cpl_valid),
        .cpl_ready        (cpl_ready),
        .cpl_error        (cpl_error),
        .cpl_error_code   (cpl_error_code),
        .cpl_bytes        (cpl_bytes),

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
            lfsr <= 32'h1ACE_B00C;
        else
            lfsr <= {
                lfsr[30:0],
                lfsr[31] ^ lfsr[21] ^
                lfsr[1]  ^ lfsr[0]
            };
    end

    assign m_ready =
        lfsr[3] | lfsr[7];

    /*
     * Error injection:
     *
     * 0 = normal
     * 1 = SLVERR
     * 2 = DECERR
     * 3 = early RLAST
     * 4 = late RLAST
     * 5 = RID mismatch
     */
    integer inject_mode;

    logic        mem_active;
    logic [39:0] mem_addr;
    integer      mem_beats;
    integer      mem_index;

    integer ar_count;

    function automatic [63:0] memory_pattern(
        input logic [39:0] address
    );
        memory_pattern =
            64'hD15E_A5E0_0000_0000 ^
            {{24{1'b0}}, address};
    endfunction

    assign arready =
        !mem_active &&
        (lfsr[1] | lfsr[5]);

    /*
     * Behavioral AXI read slave.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            mem_active <= 1'b0;
            mem_addr   <= '0;
            mem_beats  <= 0;
            mem_index  <= 0;

            rid        <= '0;
            rdata      <= '0;
            rresp      <= 2'b00;
            rlast      <= 1'b0;
            rvalid     <= 1'b0;

            ar_count   <= 0;

        end
        else begin

            /*
             * Accept a new AR transaction.
             */
            if (arvalid && arready) begin

                if (arid !== 0) begin
                    $display("FAIL: ARID must be zero");
                    $fatal;
                end

                if (arsize !== 3'b011) begin
                    $display("FAIL: ARSIZE incorrect");
                    $fatal;
                end

                if (arburst !== 2'b01) begin
                    $display("FAIL: ARBURST not INCR");
                    $fatal;
                end

                /*
                 * Critical AXI invariant:
                 * no burst may cross 4 KiB.
                 */
                if (
                    (araddr[11:0] +
                    ((arlen + 1) * 8)) > 4096
                ) begin
                    $display(
                        "FAIL: AR burst crosses 4-KiB boundary"
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
             * Present next R beat only when no previous
             * beat is currently being held.
             */
            if (mem_active && !rvalid) begin

                if (lfsr[2] | lfsr[6]) begin

                    rid   <= '0;
                    rdata <= memory_pattern(
                        mem_addr + (mem_index * 8)
                    );

                    rresp <= 2'b00;
                    rlast <= 1'b0;

                    /*
                     * Directed error injection.
                     */
                    if ((inject_mode == 1) &&
                        (mem_index == 2))
                        rresp <= 2'b10;

                    if ((inject_mode == 2) &&
                        (mem_index == 2))
                        rresp <= 2'b11;

                    if ((inject_mode == 5) &&
                        (mem_index == 2))
                        rid <= 4'h7;

                    if (inject_mode == 3) begin

                        /*
                         * Premature end.
                         */
                        if (mem_index == 2)
                            rlast <= 1'b1;

                    end
                    else if (inject_mode == 4) begin

                        /*
                         * Omit RLAST on expected final beat,
                         * then provide one extra terminating beat.
                         */
                        if (mem_index == mem_beats)
                            rlast <= 1'b1;

                    end
                    else begin

                        if (mem_index == (mem_beats - 1))
                            rlast <= 1'b1;

                    end

                    rvalid <= 1'b1;
                end
            end

            /*
             * R handshake.
             *
             * If stalled, all R-channel signals remain unchanged.
             */
            if (rvalid && rready) begin

                if (rlast) begin

                    mem_active <= 1'b0;
                    rvalid     <= 1'b0;

                end
                else begin

                    mem_index <= mem_index + 1;
                    rvalid    <= 1'b0;

                end
            end
        end
    end

    task automatic issue_request(
        input logic [39:0] address,
        input logic [31:0] length
    );
        begin

            @(negedge clk);

            req_addr  = address;
            req_bytes = length;
            req_valid = 1'b1;

            do begin
                @(posedge clk);
            end while (!req_ready);

            @(negedge clk);
            req_valid = 1'b0;

        end
    endtask

    task automatic consume_completion;
        begin

            while (!cpl_valid)
                @(posedge clk);

            @(negedge clk);
            cpl_ready = 1'b1;

            @(posedge clk);
            @(negedge clk);

            cpl_ready = 1'b0;

        end
    endtask

    task automatic run_success(
        input logic [39:0] address,
        input logic [31:0] length
    );

        integer received;
        integer ar_before;

        begin

            inject_mode = 0;
            received    = 0;
            ar_before   = ar_count;

            issue_request(address, length);

            while (!cpl_valid) begin

                @(posedge clk);

                if (m_valid && m_ready) begin

                    if (m_data !==
                        memory_pattern(address + received)) begin

                        $display(
                            "FAIL DATA address=%h offset=%0d got=%h expected=%h",
                            address,
                            received,
                            m_data,
                            memory_pattern(address + received)
                        );

                        $fatal;
                    end

                    if (m_keep !== 8'hFF) begin
                        $display("FAIL: TKEEP");
                        $fatal;
                    end

                    if (m_last !==
                        ((received + 8) == length)) begin

                        $display(
                            "FAIL: TLAST position"
                        );

                        $fatal;
                    end

                    received = received + 8;
                end
            end

            if (cpl_error) begin
                $display(
                    "FAIL: unexpected completion error %0d",
                    cpl_error_code
                );
                $fatal;
            end

            if (cpl_bytes !== length) begin
                $display(
                    "FAIL completion bytes got=%0d expected=%0d",
                    cpl_bytes,
                    length
                );
                $fatal;
            end

            if (received !== length) begin
                $display(
                    "FAIL received bytes got=%0d expected=%0d",
                    received,
                    length
                );
                $fatal;
            end

            if (ar_count == ar_before) begin
                $display("FAIL: no AXI read burst issued");
                $fatal;
            end

            consume_completion();

        end
    endtask

    task automatic run_error(
        input integer mode,
        input logic [3:0] expected_code
    );
        begin

            inject_mode = mode;

            issue_request(
                40'h0000_4000,
                32'd64
            );

            while (!cpl_valid)
                @(posedge clk);

            if (!cpl_error) begin
                $display(
                    "FAIL: expected error mode %0d",
                    mode
                );
                $fatal;
            end

            if (cpl_error_code !== expected_code) begin
                $display(
                    "FAIL error code mode=%0d got=%0d expected=%0d",
                    mode,
                    cpl_error_code,
                    expected_code
                );
                $fatal;
            end

            consume_completion();

            inject_mode = 0;

        end
    endtask

    initial begin

        req_valid   = 1'b0;
        req_addr    = '0;
        req_bytes   = '0;
        cpl_ready   = 1'b0;
        inject_mode = 0;

        repeat (10) @(posedge clk);

        aresetn = 1'b1;

        repeat (5) @(posedge clk);

        /*
         * Basic requests.
         */
        run_success(
            40'h0000_1000,
            32'd8
        );

        run_success(
            40'h0000_1800,
            32'd64
        );

        $display(
            "BASIC READ TRANSACTIONS: PASS"
        );

        /*
         * Requires multiple maximum-sized AXI bursts.
         */
        run_success(
            40'h0000_2000,
            32'd4096
        );

        $display(
            "MULTI-BURST READ: PASS"
        );

        /*
         * Starts only 16 bytes before a 4-KiB boundary,
         * forcing an immediate split.
         */
        run_success(
            40'h0000_1FF0,
            32'd8192
        );

        $display(
            "4-KiB SPLIT READ: PASS"
        );

        /*
         * Response and protocol failures.
         */
        run_error(1, 4'h2);
        $display("SLVERR DETECTION: PASS");

        run_error(2, 4'h3);
        $display("DECERR DETECTION: PASS");

        run_error(3, 4'h4);
        $display("EARLY RLAST DETECTION: PASS");

        run_error(4, 4'h5);
        $display("LATE RLAST DETECTION: PASS");

        run_error(5, 4'h6);
        $display("RID ERROR DETECTION: PASS");

        /*
         * Invalid requests generated internally,
         * with no AXI transaction permitted.
         */
        issue_request(
            40'h0000_1001,
            32'd64
        );

        while (!cpl_valid)
            @(posedge clk);

        if (!cpl_error ||
            cpl_error_code !== 4'h1) begin
            $display(
                "FAIL: unaligned address not rejected"
            );
            $fatal;
        end

        consume_completion();

        issue_request(
            40'h0000_1000,
            32'd15
        );

        while (!cpl_valid)
            @(posedge clk);

        if (!cpl_error ||
            cpl_error_code !== 4'h1) begin
            $display(
                "FAIL: unaligned length not rejected"
            );
            $fatal;
        end

        consume_completion();

        issue_request(
            40'h0000_1000,
            32'd0
        );

        while (!cpl_valid)
            @(posedge clk);

        if (!cpl_error ||
            cpl_error_code !== 4'h1) begin
            $display(
                "FAIL: zero-length request not rejected"
            );
            $fatal;
        end

        consume_completion();

        $display(
            "INVALID REQUEST REJECTION: PASS"
        );

        $display("");
        $display("=============================================");
        $display(" DMA AXI READ MASTER: PASS");
        $display(" randomized ARREADY stalls    : PASS");
        $display(" randomized RVALID gaps       : PASS");
        $display(" downstream backpressure      : PASS");
        $display(" multi-burst operation        : PASS");
        $display(" 4-KiB burst splitting        : PASS");
        $display(" RRESP checking               : PASS");
        $display(" RLAST checking               : PASS");
        $display(" RID checking                 : PASS");
        $display(" request completion accounting: PASS");
        $display("=============================================");

        $finish;
    end

    /*
     * Hard timeout catches deadlocks.
     */
    initial begin
        #5_000_000;

        $display(
            "FAIL: simulation timeout / possible AXI deadlock"
        );

        $fatal;
    end

endmodule
