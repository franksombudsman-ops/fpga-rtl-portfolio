`timescale 1ns/1ps

module tb_dma_axi_write_master;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn = 1'b0;

    logic        req_valid;
    logic        req_ready;
    logic [39:0] req_addr;
    logic [31:0] req_bytes;

    logic [63:0] s_data;
    logic [7:0]  s_keep;
    logic        s_valid;
    logic        s_ready;

    logic        cpl_valid;
    logic        cpl_ready;
    logic        cpl_error;
    logic [3:0]  cpl_error_code;
    logic [31:0] cpl_bytes;

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

    dma_axi_write_master dut (
        .clk            (clk),
        .aresetn        (aresetn),

        .req_valid      (req_valid),
        .req_ready      (req_ready),
        .req_addr       (req_addr),
        .req_bytes      (req_bytes),

        .s_data         (s_data),
        .s_keep         (s_keep),
        .s_valid        (s_valid),
        .s_ready        (s_ready),

        .cpl_valid      (cpl_valid),
        .cpl_ready      (cpl_ready),
        .cpl_error      (cpl_error),
        .cpl_error_code (cpl_error_code),
        .cpl_bytes      (cpl_bytes),

        .m_axi_awid     (awid),
        .m_axi_awaddr   (awaddr),
        .m_axi_awlen    (awlen),
        .m_axi_awsize   (awsize),
        .m_axi_awburst  (awburst),
        .m_axi_awlock   (awlock),
        .m_axi_awcache  (awcache),
        .m_axi_awprot   (awprot),
        .m_axi_awqos    (awqos),
        .m_axi_awvalid  (awvalid),
        .m_axi_awready  (awready),

        .m_axi_wdata    (wdata),
        .m_axi_wstrb    (wstrb),
        .m_axi_wlast    (wlast),
        .m_axi_wvalid   (wvalid),
        .m_axi_wready   (wready),

        .m_axi_bid      (bid),
        .m_axi_bresp    (bresp),
        .m_axi_bvalid   (bvalid),
        .m_axi_bready   (bready)
    );

    logic [31:0] lfsr;

    always_ff @(posedge clk) begin
        if (!aresetn)
            lfsr <= 32'h5A17_39C1;
        else
            lfsr <= {
                lfsr[30:0],
                lfsr[31] ^ lfsr[21] ^
                lfsr[1]  ^ lfsr[0]
            };
    end

    /*
     * Error injection:
     * 0 normal
     * 1 SLVERR
     * 2 DECERR
     * 3 BID mismatch
     */
    integer inject_mode;

    logic        burst_active;
    logic [39:0] burst_addr;
    integer      burst_beats;
    integer      burst_index;

    logic        response_pending;
    integer      response_delay;

    integer aw_count;
    integer w_count;
    integer b_count;

    function automatic [63:0] payload_pattern(
        input logic [39:0] address
    );
        payload_pattern =
            64'hA55A_C33C_0000_0000 ^
            {{24{1'b0}}, address};
    endfunction

    assign awready =
        !burst_active &&
        !response_pending &&
        !bvalid &&
        (lfsr[1] | lfsr[5]);

    assign wready =
        burst_active &&
        (lfsr[2] | lfsr[6]);

    /*
     * Behavioral AXI write slave.
     */
    always_ff @(posedge clk) begin

        if (!aresetn) begin

            burst_active    <= 1'b0;
            burst_addr      <= '0;
            burst_beats     <= 0;
            burst_index     <= 0;

            response_pending <= 1'b0;
            response_delay   <= 0;

            bid    <= '0;
            bresp  <= 2'b00;
            bvalid <= 1'b0;

            aw_count <= 0;
            w_count  <= 0;
            b_count  <= 0;

        end
        else begin

            if (awvalid && awready) begin

                if (awid !== 0) begin
                    $display("FAIL: AWID");
                    $fatal;
                end

                if (awsize !== 3'b011) begin
                    $display("FAIL: AWSIZE");
                    $fatal;
                end

                if (awburst !== 2'b01) begin
                    $display("FAIL: AWBURST");
                    $fatal;
                end

                if (
                    (awaddr[11:0] +
                    ((awlen + 1) * 8)) > 4096
                ) begin
                    $display(
                        "FAIL: AW burst crosses 4-KiB boundary"
                    );
                    $fatal;
                end

                burst_active <= 1'b1;
                burst_addr   <= awaddr;
                burst_beats  <= awlen + 1;
                burst_index  <= 0;

                aw_count <= aw_count + 1;
            end

            if (wvalid && wready) begin

                if (!burst_active) begin
                    $display(
                        "FAIL: W transfer without active AW"
                    );
                    $fatal;
                end

                if (wstrb !== 8'hFF) begin
                    $display("FAIL: WSTRB");
                    $fatal;
                end

                if (wdata !==
                    payload_pattern(
                        burst_addr +
                        (burst_index * 8)
                    )) begin

                    $display(
                        "FAIL WDATA address=%h index=%0d got=%h expected=%h",
                        burst_addr,
                        burst_index,
                        wdata,
                        payload_pattern(
                            burst_addr +
                            (burst_index * 8)
                        )
                    );

                    $fatal;
                end

                if (wlast !==
                    (burst_index ==
                     (burst_beats - 1))) begin

                    $display(
                        "FAIL: WLAST position"
                    );
                    $fatal;
                end

                w_count <= w_count + 1;

                if (burst_index ==
                    (burst_beats - 1)) begin

                    burst_active     <= 1'b0;
                    response_pending <= 1'b1;
                    response_delay   <=
                        1 + {29'd0, lfsr[10:8]};

                end
                else begin

                    burst_index <= burst_index + 1;

                end
            end

            if (response_pending &&
                !bvalid) begin

                if (response_delay > 0) begin
                    response_delay <=
                        response_delay - 1;
                end
                else begin

                    bid   <= '0;
                    bresp <= 2'b00;

                    case (inject_mode)

                        1:
                            bresp <= 2'b10;

                        2:
                            bresp <= 2'b11;

                        3:
                            bid <= 4'h7;

                        default: begin
                            bid   <= '0;
                            bresp <= 2'b00;
                        end

                    endcase

                    bvalid <= 1'b1;
                    response_pending <= 1'b0;
                end
            end

            if (bvalid && bready) begin
                bvalid  <= 1'b0;
                b_count <= b_count + 1;
            end
        end
    end

    /*
     * Explicit stability monitors.
     */
    logic       aw_stalled;
    logic [39:0] saved_awaddr;
    logic [7:0]  saved_awlen;

    logic        w_stalled;
    logic [63:0] saved_wdata;
    logic [7:0]  saved_wstrb;
    logic        saved_wlast;

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            aw_stalled <= 1'b0;
            w_stalled  <= 1'b0;

        end
        else begin

            if (awvalid && !awready) begin

                if (aw_stalled) begin

                    if ((awaddr !== saved_awaddr) ||
                        (awlen  !== saved_awlen)) begin

                        $display(
                            "FAIL: AW changed while stalled"
                        );

                        $fatal;
                    end
                end

                saved_awaddr <= awaddr;
                saved_awlen  <= awlen;
                aw_stalled   <= 1'b1;

            end
            else begin

                aw_stalled <= 1'b0;

            end

            if (wvalid && !wready) begin

                if (w_stalled) begin

                    if ((wdata !== saved_wdata) ||
                        (wstrb !== saved_wstrb) ||
                        (wlast !== saved_wlast)) begin

                        $display(
                            "FAIL: W changed while stalled"
                        );

                        $fatal;
                    end
                end

                saved_wdata <= wdata;
                saved_wstrb <= wstrb;
                saved_wlast <= wlast;
                w_stalled   <= 1'b1;

            end
            else begin

                w_stalled <= 1'b0;

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

    task automatic send_payload(
        input logic [39:0] address,
        input logic [31:0] length
    );

        integer offset;

        begin

            offset = 0;

            while (offset < length) begin

                /*
                 * Random source-side gap.
                 */
                while (!(lfsr[8] | lfsr[13]))
                    @(posedge clk);

                @(negedge clk);

                s_data  =
                    payload_pattern(address + offset);

                s_keep  = 8'hFF;
                s_valid = 1'b1;

                do begin
                    @(posedge clk);
                end while (!s_ready);

                @(negedge clk);
                s_valid = 1'b0;

                offset = offset + 8;
            end
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

        integer aw_before;
        integer b_before;

        begin

            inject_mode = 0;

            aw_before = aw_count;
            b_before  = b_count;

            fork

                issue_request(
                    address,
                    length
                );

                send_payload(
                    address,
                    length
                );

            join

            while (!cpl_valid)
                @(posedge clk);

            if (cpl_error) begin

                $display(
                    "FAIL unexpected completion error=%0d",
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

            if (aw_count == aw_before) begin
                $display("FAIL: no AW issued");
                $fatal;
            end

            if (b_count == b_before) begin
                $display("FAIL: no B response accepted");
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

            fork

                issue_request(
                    40'h0000_4000,
                    32'd64
                );

                send_payload(
                    40'h0000_4000,
                    32'd64
                );

            join

            while (!cpl_valid)
                @(posedge clk);

            if (!cpl_error) begin

                $display(
                    "FAIL: expected error mode=%0d",
                    mode
                );

                $fatal;
            end

            if (cpl_error_code !==
                expected_code) begin

                $display(
                    "FAIL error code mode=%0d got=%0d expected=%0d",
                    mode,
                    cpl_error_code,
                    expected_code
                );

                $fatal;
            end

            /*
             * Failed B response means current burst is not
             * counted as committed.
             */
            if (cpl_bytes !== 0) begin

                $display(
                    "FAIL: errored burst counted as committed"
                );

                $fatal;
            end

            consume_completion();

            inject_mode = 0;
        end
    endtask

    task automatic run_invalid_request(
        input logic [39:0] address,
        input logic [31:0] length
    );

        integer aw_before;

        begin

            aw_before = aw_count;

            issue_request(
                address,
                length
            );

            while (!cpl_valid)
                @(posedge clk);

            if (!cpl_error ||
                cpl_error_code !== 4'h1) begin

                $display(
                    "FAIL: invalid request not rejected"
                );

                $fatal;
            end

            if (aw_count != aw_before) begin

                $display(
                    "FAIL: invalid request generated AW"
                );

                $fatal;
            end

            consume_completion();
        end
    endtask

    initial begin

        req_valid   = 1'b0;
        req_addr    = '0;
        req_bytes   = '0;

        s_data      = '0;
        s_keep      = 8'hFF;
        s_valid     = 1'b0;

        cpl_ready   = 1'b0;
        inject_mode = 0;

        repeat (10) @(posedge clk);

        aresetn = 1'b1;

        repeat (5) @(posedge clk);

        run_success(
            40'h0000_1000,
            32'd8
        );

        run_success(
            40'h0000_1800,
            32'd64
        );

        $display(
            "BASIC WRITE TRANSACTIONS: PASS"
        );

        run_success(
            40'h0000_2000,
            32'd4096
        );

        $display(
            "MULTI-BURST WRITE: PASS"
        );

        /*
         * Starts 16 bytes before a 4-KiB boundary.
         */
        run_success(
            40'h0000_1FF0,
            32'd8192
        );

        $display(
            "4-KiB SPLIT WRITE: PASS"
        );

        run_error(1, 4'h2);
        $display("SLVERR DETECTION: PASS");

        run_error(2, 4'h3);
        $display("DECERR DETECTION: PASS");

        run_error(3, 4'h4);
        $display("BID ERROR DETECTION: PASS");

        run_invalid_request(
            40'h0000_1001,
            32'd64
        );

        run_invalid_request(
            40'h0000_1000,
            32'd15
        );

        run_invalid_request(
            40'h0000_1000,
            32'd0
        );

        $display(
            "INVALID REQUEST REJECTION: PASS"
        );

        $display("");
        $display("=============================================");
        $display(" DMA AXI WRITE MASTER: PASS");
        $display(" randomized AWREADY stalls   : PASS");
        $display(" randomized WREADY stalls    : PASS");
        $display(" randomized source gaps      : PASS");
        $display(" AW stability under stall    : PASS");
        $display(" W stability under stall     : PASS");
        $display(" multi-burst operation       : PASS");
        $display(" 4-KiB burst splitting       : PASS");
        $display(" WLAST generation            : PASS");
        $display(" BRESP checking              : PASS");
        $display(" BID checking                : PASS");
        $display(" committed-byte accounting   : PASS");
        $display("=============================================");

        $finish;
    end

    initial begin

        #8_000_000;

        $display(
            "FAIL: simulation timeout / possible AXI deadlock"
        );

        $fatal;
    end

endmodule
