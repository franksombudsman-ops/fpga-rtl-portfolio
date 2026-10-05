`timescale 1ns/1ps

module tb_dma_arbiters;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn;

    /*
     * READ ARBITER SIGNALS
     */
    logic        r0_req_valid, r0_req_ready;
    logic [39:0] r0_req_addr;
    logic [31:0] r0_req_bytes;
    logic [63:0] r0_data;
    logic [7:0]  r0_keep;
    logic        r0_data_valid, r0_data_ready, r0_data_last;
    logic        r0_cpl_valid, r0_cpl_ready, r0_cpl_error;
    logic [3:0]  r0_cpl_error_code;
    logic [31:0] r0_cpl_bytes;

    logic        r1_req_valid, r1_req_ready;
    logic [39:0] r1_req_addr;
    logic [31:0] r1_req_bytes;
    logic [63:0] r1_data;
    logic [7:0]  r1_keep;
    logic        r1_data_valid, r1_data_ready, r1_data_last;
    logic        r1_cpl_valid, r1_cpl_ready, r1_cpl_error;
    logic [3:0]  r1_cpl_error_code;
    logic [31:0] r1_cpl_bytes;

    logic        r2_req_valid, r2_req_ready;
    logic [39:0] r2_req_addr;
    logic [31:0] r2_req_bytes;
    logic [63:0] r2_data;
    logic [7:0]  r2_keep;
    logic        r2_data_valid, r2_data_ready, r2_data_last;
    logic        r2_cpl_valid, r2_cpl_ready, r2_cpl_error;
    logic [3:0]  r2_cpl_error_code;
    logic [31:0] r2_cpl_bytes;

    logic        rm_req_valid, rm_req_ready;
    logic [39:0] rm_req_addr;
    logic [31:0] rm_req_bytes;

    logic [63:0] rm_data;
    logic [7:0]  rm_keep;
    logic        rm_data_valid, rm_data_ready, rm_data_last;

    logic        rm_cpl_valid, rm_cpl_ready, rm_cpl_error;
    logic [3:0]  rm_cpl_error_code;
    logic [31:0] rm_cpl_bytes;

    dma_read_arbiter read_arbiter (
        .clk(clk),
        .aresetn(aresetn),

        .c0_req_valid(r0_req_valid),
        .c0_req_ready(r0_req_ready),
        .c0_req_addr(r0_req_addr),
        .c0_req_bytes(r0_req_bytes),
        .c0_data(r0_data),
        .c0_keep(r0_keep),
        .c0_data_valid(r0_data_valid),
        .c0_data_ready(r0_data_ready),
        .c0_data_last(r0_data_last),
        .c0_cpl_valid(r0_cpl_valid),
        .c0_cpl_ready(r0_cpl_ready),
        .c0_cpl_error(r0_cpl_error),
        .c0_cpl_error_code(r0_cpl_error_code),
        .c0_cpl_bytes(r0_cpl_bytes),

        .c1_req_valid(r1_req_valid),
        .c1_req_ready(r1_req_ready),
        .c1_req_addr(r1_req_addr),
        .c1_req_bytes(r1_req_bytes),
        .c1_data(r1_data),
        .c1_keep(r1_keep),
        .c1_data_valid(r1_data_valid),
        .c1_data_ready(r1_data_ready),
        .c1_data_last(r1_data_last),
        .c1_cpl_valid(r1_cpl_valid),
        .c1_cpl_ready(r1_cpl_ready),
        .c1_cpl_error(r1_cpl_error),
        .c1_cpl_error_code(r1_cpl_error_code),
        .c1_cpl_bytes(r1_cpl_bytes),

        .c2_req_valid(r2_req_valid),
        .c2_req_ready(r2_req_ready),
        .c2_req_addr(r2_req_addr),
        .c2_req_bytes(r2_req_bytes),
        .c2_data(r2_data),
        .c2_keep(r2_keep),
        .c2_data_valid(r2_data_valid),
        .c2_data_ready(r2_data_ready),
        .c2_data_last(r2_data_last),
        .c2_cpl_valid(r2_cpl_valid),
        .c2_cpl_ready(r2_cpl_ready),
        .c2_cpl_error(r2_cpl_error),
        .c2_cpl_error_code(r2_cpl_error_code),
        .c2_cpl_bytes(r2_cpl_bytes),

        .m_req_valid(rm_req_valid),
        .m_req_ready(rm_req_ready),
        .m_req_addr(rm_req_addr),
        .m_req_bytes(rm_req_bytes),

        .m_data(rm_data),
        .m_keep(rm_keep),
        .m_data_valid(rm_data_valid),
        .m_data_ready(rm_data_ready),
        .m_data_last(rm_data_last),

        .m_cpl_valid(rm_cpl_valid),
        .m_cpl_ready(rm_cpl_ready),
        .m_cpl_error(rm_cpl_error),
        .m_cpl_error_code(rm_cpl_error_code),
        .m_cpl_bytes(rm_cpl_bytes)
    );

    /*
     * WRITE ARBITER SIGNALS
     */
    logic        w0_req_valid, w0_req_ready;
    logic [39:0] w0_req_addr;
    logic [31:0] w0_req_bytes;
    logic [63:0] w0_data;
    logic [7:0]  w0_keep;
    logic        w0_data_valid, w0_data_ready;
    logic        w0_cpl_valid, w0_cpl_ready, w0_cpl_error;
    logic [3:0]  w0_cpl_error_code;
    logic [31:0] w0_cpl_bytes;

    logic        w1_req_valid, w1_req_ready;
    logic [39:0] w1_req_addr;
    logic [31:0] w1_req_bytes;
    logic [63:0] w1_data;
    logic [7:0]  w1_keep;
    logic        w1_data_valid, w1_data_ready;
    logic        w1_cpl_valid, w1_cpl_ready, w1_cpl_error;
    logic [3:0]  w1_cpl_error_code;
    logic [31:0] w1_cpl_bytes;

    logic        w2_req_valid, w2_req_ready;
    logic [39:0] w2_req_addr;
    logic [31:0] w2_req_bytes;
    logic [63:0] w2_data;
    logic [7:0]  w2_keep;
    logic        w2_data_valid, w2_data_ready;
    logic        w2_cpl_valid, w2_cpl_ready, w2_cpl_error;
    logic [3:0]  w2_cpl_error_code;
    logic [31:0] w2_cpl_bytes;

    logic        wm_req_valid, wm_req_ready;
    logic [39:0] wm_req_addr;
    logic [31:0] wm_req_bytes;

    logic [63:0] wm_data;
    logic [7:0]  wm_keep;
    logic        wm_data_valid, wm_data_ready;

    logic        wm_cpl_valid, wm_cpl_ready, wm_cpl_error;
    logic [3:0]  wm_cpl_error_code;
    logic [31:0] wm_cpl_bytes;

    dma_write_arbiter write_arbiter (
        .clk(clk),
        .aresetn(aresetn),

        .c0_req_valid(w0_req_valid),
        .c0_req_ready(w0_req_ready),
        .c0_req_addr(w0_req_addr),
        .c0_req_bytes(w0_req_bytes),
        .c0_data(w0_data),
        .c0_keep(w0_keep),
        .c0_data_valid(w0_data_valid),
        .c0_data_ready(w0_data_ready),
        .c0_cpl_valid(w0_cpl_valid),
        .c0_cpl_ready(w0_cpl_ready),
        .c0_cpl_error(w0_cpl_error),
        .c0_cpl_error_code(w0_cpl_error_code),
        .c0_cpl_bytes(w0_cpl_bytes),

        .c1_req_valid(w1_req_valid),
        .c1_req_ready(w1_req_ready),
        .c1_req_addr(w1_req_addr),
        .c1_req_bytes(w1_req_bytes),
        .c1_data(w1_data),
        .c1_keep(w1_keep),
        .c1_data_valid(w1_data_valid),
        .c1_data_ready(w1_data_ready),
        .c1_cpl_valid(w1_cpl_valid),
        .c1_cpl_ready(w1_cpl_ready),
        .c1_cpl_error(w1_cpl_error),
        .c1_cpl_error_code(w1_cpl_error_code),
        .c1_cpl_bytes(w1_cpl_bytes),

        .c2_req_valid(w2_req_valid),
        .c2_req_ready(w2_req_ready),
        .c2_req_addr(w2_req_addr),
        .c2_req_bytes(w2_req_bytes),
        .c2_data(w2_data),
        .c2_keep(w2_keep),
        .c2_data_valid(w2_data_valid),
        .c2_data_ready(w2_data_ready),
        .c2_cpl_valid(w2_cpl_valid),
        .c2_cpl_ready(w2_cpl_ready),
        .c2_cpl_error(w2_cpl_error),
        .c2_cpl_error_code(w2_cpl_error_code),
        .c2_cpl_bytes(w2_cpl_bytes),

        .m_req_valid(wm_req_valid),
        .m_req_ready(wm_req_ready),
        .m_req_addr(wm_req_addr),
        .m_req_bytes(wm_req_bytes),

        .m_data(wm_data),
        .m_keep(wm_keep),
        .m_data_valid(wm_data_valid),
        .m_data_ready(wm_data_ready),

        .m_cpl_valid(wm_cpl_valid),
        .m_cpl_ready(wm_cpl_ready),
        .m_cpl_error(wm_cpl_error),
        .m_cpl_error_code(wm_cpl_error_code),
        .m_cpl_bytes(wm_cpl_bytes)
    );

    task automatic read_accept(
        input integer client,
        input logic [39:0] expected_addr
    );
        begin

            rm_req_ready = 1'b0;

            repeat (3) begin
                @(posedge clk);
                #1;

                if (!rm_req_valid ||
                    rm_req_addr !== expected_addr) begin

                    $display(
                        "FAIL: read grant/request changed while stalled"
                    );
                    $fatal;
                end
            end

            @(negedge clk);
            rm_req_ready = 1'b1;

            @(posedge clk);
            @(negedge clk);
            rm_req_ready = 1'b0;

            case (client)
                0: r0_req_valid = 1'b0;
                1: r1_req_valid = 1'b0;
                2: r2_req_valid = 1'b0;
            endcase

            @(posedge clk);
            #1;

            /*
             * Other queued clients must not reach the master while
             * this transaction owns it.
             */
            if (rm_req_valid) begin
                $display(
                    "FAIL: read request interleaving while owner active"
                );
                $fatal;
            end
        end
    endtask

    task automatic read_service(
        input integer client,
        input logic [63:0] value
    );
        begin

            r0_data_ready = 1'b0;
            r1_data_ready = 1'b0;
            r2_data_ready = 1'b0;

            rm_data       = value;
            rm_keep       = 8'hFF;
            rm_data_last  = 1'b1;
            rm_data_valid = 1'b1;

            #1;

            if (rm_data_ready) begin
                $display("FAIL: read data accepted while owner stalled");
                $fatal;
            end

            case (client)
                0: r0_data_ready = 1'b1;
                1: r1_data_ready = 1'b1;
                2: r2_data_ready = 1'b1;
            endcase

            #1;

            if (!rm_data_ready) begin
                $display("FAIL: owner read ready not routed");
                $fatal;
            end

            if ((client == 0 &&
                 (!r0_data_valid || r1_data_valid || r2_data_valid ||
                  r0_data !== value)) ||
                (client == 1 &&
                 (!r1_data_valid || r0_data_valid || r2_data_valid ||
                  r1_data !== value)) ||
                (client == 2 &&
                 (!r2_data_valid || r0_data_valid || r1_data_valid ||
                  r2_data !== value))) begin

                $display("FAIL: read data routed to wrong client");
                $fatal;
            end

            @(posedge clk);
            @(negedge clk);

            rm_data_valid = 1'b0;

            r0_data_ready = 1'b0;
            r1_data_ready = 1'b0;
            r2_data_ready = 1'b0;

            /*
             * Completion backpressure must retain ownership.
             */
            rm_cpl_error      = 1'b0;
            rm_cpl_error_code = 4'd0;
            rm_cpl_bytes      = 32'd8;
            rm_cpl_valid      = 1'b1;

            r0_cpl_ready = 1'b0;
            r1_cpl_ready = 1'b0;
            r2_cpl_ready = 1'b0;

            repeat (2) begin
                @(posedge clk);
                #1;

                if (rm_cpl_ready || rm_req_valid) begin
                    $display(
                        "FAIL: read ownership released before completion handshake"
                    );
                    $fatal;
                end
            end

            case (client)
                0: r0_cpl_ready = 1'b1;
                1: r1_cpl_ready = 1'b1;
                2: r2_cpl_ready = 1'b1;
            endcase

            #1;

            if (!rm_cpl_ready) begin
                $display("FAIL: read completion ready not routed");
                $fatal;
            end

            if ((client == 0 &&
                 (!r0_cpl_valid || r1_cpl_valid || r2_cpl_valid)) ||
                (client == 1 &&
                 (!r1_cpl_valid || r0_cpl_valid || r2_cpl_valid)) ||
                (client == 2 &&
                 (!r2_cpl_valid || r0_cpl_valid || r1_cpl_valid))) begin

                $display("FAIL: read completion routed to wrong client");
                $fatal;
            end

            @(posedge clk);
            @(negedge clk);

            rm_cpl_valid = 1'b0;

            r0_cpl_ready = 1'b0;
            r1_cpl_ready = 1'b0;
            r2_cpl_ready = 1'b0;
        end
    endtask

    task automatic write_accept(
        input integer client,
        input logic [39:0] expected_addr
    );
        begin

            wm_req_ready = 1'b0;

            repeat (3) begin
                @(posedge clk);
                #1;

                if (!wm_req_valid ||
                    wm_req_addr !== expected_addr) begin

                    $display(
                        "FAIL: write grant/request changed while stalled"
                    );
                    $fatal;
                end
            end

            @(negedge clk);
            wm_req_ready = 1'b1;

            @(posedge clk);
            @(negedge clk);
            wm_req_ready = 1'b0;

            case (client)
                0: w0_req_valid = 1'b0;
                1: w1_req_valid = 1'b0;
                2: w2_req_valid = 1'b0;
            endcase

            @(posedge clk);
            #1;

            if (wm_req_valid) begin
                $display(
                    "FAIL: write request interleaving while owner active"
                );
                $fatal;
            end
        end
    endtask

    task automatic write_service(
        input integer client,
        input logic [63:0] expected_data
    );
        begin

            /*
             * All clients deliberately assert data VALID.
             * Only the current owner may reach the shared master.
             */
            w0_data_valid = 1'b1;
            w1_data_valid = 1'b1;
            w2_data_valid = 1'b1;

            wm_data_ready = 1'b0;

            #1;

            if (!wm_data_valid ||
                wm_data !== expected_data) begin

                $display(
                    "FAIL: write data from wrong owner"
                );
                $fatal;
            end

            if (w0_data_ready ||
                w1_data_ready ||
                w2_data_ready) begin

                $display(
                    "FAIL: write client ready asserted while master stalled"
                );
                $fatal;
            end

            wm_data_ready = 1'b1;
            #1;

            case (client)
                0:
                    if (!w0_data_ready ||
                        w1_data_ready ||
                        w2_data_ready) begin
                        $display("FAIL: write ready routing client0");
                        $fatal;
                    end

                1:
                    if (!w1_data_ready ||
                        w0_data_ready ||
                        w2_data_ready) begin
                        $display("FAIL: write ready routing client1");
                        $fatal;
                    end

                2:
                    if (!w2_data_ready ||
                        w0_data_ready ||
                        w1_data_ready) begin
                        $display("FAIL: write ready routing client2");
                        $fatal;
                    end
            endcase

            @(posedge clk);
            @(negedge clk);

            wm_data_ready = 1'b0;

            w0_data_valid = 1'b0;
            w1_data_valid = 1'b0;
            w2_data_valid = 1'b0;

            wm_cpl_error      = 1'b0;
            wm_cpl_error_code = 4'd0;
            wm_cpl_bytes      = 32'd8;
            wm_cpl_valid      = 1'b1;

            w0_cpl_ready = 1'b0;
            w1_cpl_ready = 1'b0;
            w2_cpl_ready = 1'b0;

            repeat (2) begin
                @(posedge clk);
                #1;

                if (wm_cpl_ready || wm_req_valid) begin
                    $display(
                        "FAIL: write ownership released before completion"
                    );
                    $fatal;
                end
            end

            case (client)
                0: w0_cpl_ready = 1'b1;
                1: w1_cpl_ready = 1'b1;
                2: w2_cpl_ready = 1'b1;
            endcase

            #1;

            if (!wm_cpl_ready) begin
                $display("FAIL: write completion ready routing");
                $fatal;
            end

            if ((client == 0 &&
                 (!w0_cpl_valid || w1_cpl_valid || w2_cpl_valid)) ||
                (client == 1 &&
                 (!w1_cpl_valid || w0_cpl_valid || w2_cpl_valid)) ||
                (client == 2 &&
                 (!w2_cpl_valid || w0_cpl_valid || w1_cpl_valid))) begin

                $display(
                    "FAIL: write completion routed to wrong client"
                );
                $fatal;
            end

            @(posedge clk);
            @(negedge clk);

            wm_cpl_valid = 1'b0;

            w0_cpl_ready = 1'b0;
            w1_cpl_ready = 1'b0;
            w2_cpl_ready = 1'b0;
        end
    endtask

    initial begin

        aresetn = 1'b0;

        r0_req_valid = 0;
        r1_req_valid = 0;
        r2_req_valid = 0;

        r0_req_addr  = 40'h1000;
        r1_req_addr  = 40'h2000;
        r2_req_addr  = 40'h3000;

        r0_req_bytes = 32'd8;
        r1_req_bytes = 32'd8;
        r2_req_bytes = 32'd8;

        r0_data_ready = 0;
        r1_data_ready = 0;
        r2_data_ready = 0;

        r0_cpl_ready = 0;
        r1_cpl_ready = 0;
        r2_cpl_ready = 0;

        rm_req_ready = 0;

        rm_data       = 0;
        rm_keep       = 8'hFF;
        rm_data_valid = 0;
        rm_data_last  = 0;

        rm_cpl_valid      = 0;
        rm_cpl_error      = 0;
        rm_cpl_error_code = 0;
        rm_cpl_bytes      = 0;

        w0_req_valid = 0;
        w1_req_valid = 0;
        w2_req_valid = 0;

        w0_req_addr = 40'h4000;
        w1_req_addr = 40'h5000;
        w2_req_addr = 40'h6000;

        w0_req_bytes = 32'd8;
        w1_req_bytes = 32'd8;
        w2_req_bytes = 32'd8;

        w0_data = 64'hAAAA_0000_0000_0000;
        w1_data = 64'hBBBB_0000_0000_0001;
        w2_data = 64'hCCCC_0000_0000_0002;

        w0_keep = 8'hFF;
        w1_keep = 8'hFF;
        w2_keep = 8'hFF;

        w0_data_valid = 0;
        w1_data_valid = 0;
        w2_data_valid = 0;

        w0_cpl_ready = 0;
        w1_cpl_ready = 0;
        w2_cpl_ready = 0;

        wm_req_ready = 0;
        wm_data_ready = 0;

        wm_cpl_valid      = 0;
        wm_cpl_error      = 0;
        wm_cpl_error_code = 0;
        wm_cpl_bytes      = 0;

        repeat (8) @(posedge clk);

        aresetn = 1'b1;

        repeat (3) @(posedge clk);

        /*
         * READ:
         * All three request simultaneously.
         * Reset round-robin order must be 0 -> 1 -> 2.
         */
        r0_req_valid = 1'b1;
        r1_req_valid = 1'b1;
        r2_req_valid = 1'b1;

        read_accept(0, 40'h1000);
        read_service(0, 64'h1111_1111_1111_1111);

        read_accept(1, 40'h2000);
        read_service(1, 64'h2222_2222_2222_2222);

        read_accept(2, 40'h3000);
        read_service(2, 64'h3333_3333_3333_3333);

        $display(
            "READ ROUND-ROBIN FAIRNESS: PASS"
        );

        /*
         * Pointer wraps back to client 0.
         */
        r0_req_valid = 1'b1;
        r1_req_valid = 1'b1;
        r2_req_valid = 1'b1;

        read_accept(0, 40'h1000);
        read_service(0, 64'h4444_4444_4444_4444);

        r1_req_valid = 1'b0;
        r2_req_valid = 1'b0;

        $display(
            "READ OWNERSHIP / ROUTING: PASS"
        );

        /*
         * WRITE:
         * All three request simultaneously.
         */
        w0_req_valid = 1'b1;
        w1_req_valid = 1'b1;
        w2_req_valid = 1'b1;

        write_accept(0, 40'h4000);
        write_service(0, 64'hAAAA_0000_0000_0000);

        write_accept(1, 40'h5000);
        write_service(1, 64'hBBBB_0000_0000_0001);

        write_accept(2, 40'h6000);
        write_service(2, 64'hCCCC_0000_0000_0002);

        $display(
            "WRITE ROUND-ROBIN FAIRNESS: PASS"
        );

        w0_req_valid = 1'b1;
        w1_req_valid = 1'b1;
        w2_req_valid = 1'b1;

        write_accept(0, 40'h4000);
        write_service(0, 64'hAAAA_0000_0000_0000);

        w1_req_valid = 1'b0;
        w2_req_valid = 1'b0;

        $display(
            "WRITE OWNERSHIP / ROUTING: PASS"
        );

        $display("");
        $display("============================================");
        $display(" DMA MEMORY ARBITERS: PASS");
        $display(" 3-client read round-robin      : PASS");
        $display(" 3-client write round-robin     : PASS");
        $display(" request stability under stall  : PASS");
        $display(" request-level ownership        : PASS");
        $display(" no transaction interleaving    : PASS");
        $display(" read-data owner routing        : PASS");
        $display(" write-data owner routing       : PASS");
        $display(" completion owner routing       : PASS");
        $display(" completion backpressure        : PASS");
        $display(" fairness pointer wraparound    : PASS");
        $display("============================================");

        $finish;

    end

    initial begin

        #2_000_000;

        $display(
            "FAIL: arbiter simulation timeout"
        );

        $fatal;
    end

endmodule
