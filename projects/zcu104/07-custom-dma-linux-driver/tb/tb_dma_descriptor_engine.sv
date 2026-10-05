`timescale 1ns/1ps

module tb_dma_descriptor_engine;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn;

    logic        cfg_load;
    logic [63:0] cfg_ring_base;
    logic [15:0] cfg_ring_size;
    logic [31:0] sw_tail;

    logic        config_valid;
    logic [3:0]  config_error_code;
    logic [31:0] hw_head;
    logic [31:0] pending_count;
    logic        ring_empty;
    logic        ring_overrun;

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

    logic        completion_pulse;
    logic        completion_irq_requested;
    logic [63:0] completion_cookie;
    logic [31:0] completion_status;
    logic [31:0] completion_actual_length;

    logic        fault_valid;
    logic        fault_clear;
    logic [3:0]  fault_code;

    /*
     * Descriptor-engine <-> read-master internal interface.
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
     * Descriptor-engine <-> write-master internal interface.
     */
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

    /*
     * Read-master AXI.
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

    /*
     * Write-master AXI.
     */
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

    dma_descriptor_engine descriptor_engine (
        .clk                      (clk),
        .aresetn                  (aresetn),

        .cfg_load                 (cfg_load),
        .cfg_ring_base            (cfg_ring_base),
        .cfg_ring_size            (cfg_ring_size),
        .sw_tail                  (sw_tail),

        .config_valid             (config_valid),
        .config_error_code        (config_error_code),
        .hw_head                  (hw_head),
        .pending_count            (pending_count),
        .ring_empty               (ring_empty),
        .ring_overrun             (ring_overrun),

        .work_valid               (work_valid),
        .work_ready               (work_ready),
        .work_buffer_addr         (work_buffer_addr),
        .work_length              (work_length),
        .work_control             (work_control),
        .work_cookie              (work_cookie),
        .work_irq_on_completion   (work_irq_on_completion),
        .work_end_of_packet       (work_end_of_packet),

        .retire_valid             (retire_valid),
        .retire_ready             (retire_ready),
        .retire_status            (retire_status),
        .retire_actual_length     (retire_actual_length),

        .completion_pulse         (completion_pulse),
        .completion_irq_requested (completion_irq_requested),
        .completion_cookie        (completion_cookie),
        .completion_status        (completion_status),
        .completion_actual_length (completion_actual_length),

        .fault_valid              (fault_valid),
        .fault_clear              (fault_clear),
        .fault_code               (fault_code),

        .rd_req_valid             (rd_req_valid),
        .rd_req_ready             (rd_req_ready),
        .rd_req_addr              (rd_req_addr),
        .rd_req_bytes             (rd_req_bytes),

        .rd_data                  (rd_data),
        .rd_data_keep             (rd_data_keep),
        .rd_data_valid            (rd_data_valid),
        .rd_data_ready            (rd_data_ready),
        .rd_data_last             (rd_data_last),

        .rd_cpl_valid             (rd_cpl_valid),
        .rd_cpl_ready             (rd_cpl_ready),
        .rd_cpl_error             (rd_cpl_error),
        .rd_cpl_error_code        (rd_cpl_error_code),
        .rd_cpl_bytes             (rd_cpl_bytes),

        .wr_req_valid             (wr_req_valid),
        .wr_req_ready             (wr_req_ready),
        .wr_req_addr              (wr_req_addr),
        .wr_req_bytes             (wr_req_bytes),

        .wr_data                  (wr_data),
        .wr_keep                  (wr_keep),
        .wr_data_valid            (wr_data_valid),
        .wr_data_ready            (wr_data_ready),

        .wr_cpl_valid             (wr_cpl_valid),
        .wr_cpl_ready             (wr_cpl_ready),
        .wr_cpl_error             (wr_cpl_error),
        .wr_cpl_error_code        (wr_cpl_error_code),
        .wr_cpl_bytes             (wr_cpl_bytes)
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

    /*
     * Shared behavioral DDR image.
     * 64 KiB is enough for this unit-level verification.
     */
    logic [7:0] mem [0:65535];

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

    task automatic mem_write64(
        input logic [39:0] address,
        input logic [63:0] value
    );

        integer n;

        begin

            for (n = 0; n < 8; n = n + 1)
                mem[(address[15:0] + n) & 16'hFFFF] =
                    value[n*8 +: 8];

        end
    endtask

    task automatic write_descriptor(
        input integer      slot,
        input logic [63:0] buffer_address,
        input logic [31:0] length,
        input logic [31:0] control,
        input logic [63:0] cookie
    );

        logic [39:0] address;

        begin

            address =
                40'h0000_1000 +
                (slot * 64);

            mem_write64(
                address + 40'h00,
                buffer_address
            );

            mem_write64(
                address + 40'h08,
                {control, length}
            );

            mem_write64(
                address + 40'h10,
                cookie
            );

            mem_write64(
                address + 40'h18,
                64'd0
            );

            mem_write64(
                address + 40'h20,
                64'd0
            );

            mem_write64(
                address + 40'h28,
                64'd0
            );

            mem_write64(
                address + 40'h30,
                64'd0
            );

            mem_write64(
                address + 40'h38,
                64'd0
            );

        end
    endtask

    logic [31:0] lfsr;

    always_ff @(posedge clk) begin

        if (!aresetn)
            lfsr <= 32'h61D3_A57B;
        else
            lfsr <= {
                lfsr[30:0],
                lfsr[31] ^ lfsr[21] ^
                lfsr[1]  ^ lfsr[0]
            };

    end

    /*
     * ---------------------------
     * Behavioral AXI read slave
     * ---------------------------
     */

    logic        rd_active;
    logic [39:0] rd_base;
    integer      rd_beats;
    integer      rd_index;

    integer inject_read_error;

    assign arready =
        !rd_active &&
        (lfsr[1] | lfsr[7]);

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            rd_active <= 1'b0;
            rd_base   <= 40'd0;
            rd_beats  <= 0;
            rd_index  <= 0;

            rid    <= 4'd0;
            rdata  <= 64'd0;
            rresp  <= 2'b00;
            rlast  <= 1'b0;
            rvalid <= 1'b0;

        end
        else begin

            if (arvalid && arready) begin

                if (arsize !== 3'b011 ||
                    arburst !== 2'b01) begin

                    $display(
                        "FAIL: descriptor read AXI attributes"
                    );

                    $fatal;
                end

                if ((araddr[11:0] +
                    ((arlen + 1) * 8)) > 4096) begin

                    $display(
                        "FAIL: descriptor read crosses 4-KiB"
                    );

                    $fatal;
                end

                rd_active <= 1'b1;
                rd_base   <= araddr;
                rd_beats  <= arlen + 1;
                rd_index  <= 0;

            end

            if (rd_active &&
                !rvalid &&
                (lfsr[2] | lfsr[8])) begin

                rid   <= 4'd0;

                rdata <=
                    mem_read64(
                        rd_base +
                        (rd_index * 8)
                    );

                rresp <= 2'b00;

                if (inject_read_error &&
                    rd_index == 2)
                    rresp <= 2'b10;

                rlast <=
                    (rd_index ==
                     (rd_beats - 1));

                rvalid <= 1'b1;

            end

            if (rvalid && rready) begin

                if (rlast) begin

                    rd_active <= 1'b0;

                end
                else begin

                    rd_index <=
                        rd_index + 1;

                end

                rvalid <= 1'b0;

            end
        end
    end

    /*
     * ----------------------------
     * Behavioral AXI write slave
     * ----------------------------
     */

    logic        wr_active;
    logic [39:0] wr_base;
    integer      wr_beats;
    integer      wr_index;

    logic        response_pending;
    integer      response_delay;
    integer      b_count;

    /*
     * 0 = no injection
     * 1 = fail first B response
     * 2 = fail second B response
     * ...
     */
    integer inject_write_error_txn;

    assign awready =
        !wr_active &&
        !response_pending &&
        !bvalid &&
        (lfsr[3] | lfsr[9]);

    assign wready =
        wr_active &&
        (lfsr[4] | lfsr[10]);

    integer byte_index;

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

            b_count <= 0;

        end
        else begin

            if (awvalid && awready) begin

                if (awsize !== 3'b011 ||
                    awburst !== 2'b01) begin

                    $display(
                        "FAIL: descriptor write AXI attributes"
                    );

                    $fatal;
                end

                if ((awaddr[11:0] +
                    ((awlen + 1) * 8)) > 4096) begin

                    $display(
                        "FAIL: descriptor write crosses 4-KiB"
                    );

                    $fatal;
                end

                wr_active <= 1'b1;
                wr_base   <= awaddr;
                wr_beats  <= awlen + 1;
                wr_index  <= 0;

            end

            if (wvalid && wready) begin

                if (!wr_active) begin
                    $display(
                        "FAIL: write data without AW"
                    );
                    $fatal;
                end

                if (wlast !==
                    (wr_index ==
                     (wr_beats - 1))) begin

                    $display(
                        "FAIL: integrated WLAST"
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

                    wr_active       <= 1'b0;
                    response_pending <= 1'b1;
                    response_delay   <=
                        1 + lfsr[12:11];

                end
                else begin

                    wr_index <=
                        wr_index + 1;

                end
            end

            if (response_pending &&
                !bvalid) begin

                if (response_delay > 0) begin

                    response_delay <=
                        response_delay - 1;

                end
                else begin

                    bid   <= 4'd0;
                    bresp <= 2'b00;

                    if ((inject_write_error_txn != 0) &&
                        ((b_count + 1) ==
                         inject_write_error_txn))
                        bresp <= 2'b10;

                    bvalid <= 1'b1;

                    response_pending <= 1'b0;

                end
            end

            if (bvalid && bready) begin

                bvalid <= 1'b0;
                b_count <= b_count + 1;

            end
        end
    end

    integer dispatch_count;

    always_ff @(posedge clk) begin

        if (!aresetn)
            dispatch_count <= 0;
        else if (work_valid &&
                 work_ready)
            dispatch_count <=
                dispatch_count + 1;

    end

    task automatic reset_system;

        begin

            aresetn = 1'b0;

            cfg_load      = 1'b0;
            cfg_ring_base = 64'd0;
            cfg_ring_size = 16'd0;
            sw_tail       = 32'd0;

            work_ready = 1'b0;

            retire_valid         = 1'b0;
            retire_status        = 32'd0;
            retire_actual_length = 32'd0;

            fault_clear = 1'b0;

            inject_read_error      = 0;
            inject_write_error_txn = 0;

            repeat (8) @(posedge clk);

            aresetn = 1'b1;

            repeat (4) @(posedge clk);

        end
    endtask

    task automatic configure_ring;

        begin

            @(negedge clk);

            cfg_ring_base =
                64'h0000_0000_0000_1000;

            cfg_ring_size =
                16;

            cfg_load = 1'b1;

            @(posedge clk);
            @(negedge clk);

            cfg_load = 1'b0;

            #1;

            if (!config_valid ||
                config_error_code != 0) begin

                $display(
                    "FAIL: ring configuration"
                );

                $fatal;
            end

        end
    endtask

    task automatic accept_work(
        input logic [63:0] expected_buffer,
        input logic [31:0] expected_length,
        input logic [31:0] expected_control,
        input logic [63:0] expected_cookie,
        input logic [31:0] expected_head
    );

        integer hold_cycles;

        begin

            while (!work_valid)
                @(posedge clk);

            #1;

            if (hw_head !== expected_head) begin
                $display(
                    "FAIL: HEAD advanced before work"
                );
                $fatal;
            end

            if (work_buffer_addr !== expected_buffer ||
                work_length      !== expected_length ||
                work_control     !== expected_control ||
                work_cookie      !== expected_cookie) begin

                $display(
                    "FAIL: dispatched descriptor fields"
                );

                $fatal;
            end

            /*
             * Deliberately hold downstream backpressure and verify
             * dispatch state remains stable.
             */
            for (hold_cycles = 0;
                 hold_cycles < 4;
                 hold_cycles = hold_cycles + 1) begin

                @(posedge clk);
                #1;

                if (!work_valid ||
                    work_buffer_addr !== expected_buffer ||
                    work_length      !== expected_length ||
                    work_control     !== expected_control ||
                    work_cookie      !== expected_cookie ||
                    hw_head          !== expected_head) begin

                    $display(
                        "FAIL: work changed under backpressure"
                    );

                    $fatal;
                end
            end

            @(negedge clk);
            work_ready = 1'b1;

            @(posedge clk);
            @(negedge clk);

            work_ready = 1'b0;

        end
    endtask

    task automatic send_retirement(
        input logic [31:0] status,
        input logic [31:0] actual
    );

        begin

            while (!retire_ready)
                @(posedge clk);

            repeat (3) @(posedge clk);

            @(negedge clk);

            retire_status        = status;
            retire_actual_length = actual;
            retire_valid         = 1'b1;

            @(posedge clk);
            @(negedge clk);

            retire_valid = 1'b0;

        end
    endtask

    task automatic wait_completion(
        input logic [31:0] old_head,
        input logic [31:0] expected_status,
        input logic [31:0] expected_actual,
        input logic [63:0] expected_cookie
    );

        begin

            while (!completion_pulse) begin

                @(posedge clk);
                #1;

                if (hw_head !== old_head) begin

                    $display(
                        "FAIL: HEAD advanced before ownership release"
                    );

                    $fatal;
                end
            end

            if (completion_status !== expected_status ||
                completion_actual_length !== expected_actual ||
                completion_cookie !== expected_cookie) begin

                $display(
                    "FAIL: completion event contents"
                );

                $fatal;
            end

            /*
             * ADVANCE state is now active. HEAD changes on the
             * following rising edge.
             */
            @(posedge clk);
            #1;

            if (hw_head !==
                (old_head + 1)) begin

                $display(
                    "FAIL: HEAD did not advance after OWN release"
                );

                $fatal;
            end

        end
    endtask

    task automatic process_valid_descriptor(
        input logic [31:0] logical_index,
        input logic [63:0] expected_buffer,
        input logic [31:0] expected_length,
        input logic [31:0] expected_control,
        input logic [63:0] expected_cookie
    );

        logic [39:0] desc_addr;
        logic [63:0] status_word;
        logic [63:0] ownership_word;

        begin

            accept_work(
                expected_buffer,
                expected_length,
                expected_control,
                expected_cookie,
                logical_index
            );

            send_retirement(
                32'h0000_0001,
                expected_length
            );

            wait_completion(
                logical_index,
                32'h0000_0001,
                expected_length,
                expected_cookie
            );

            desc_addr =
                40'h0000_1000 +
                ((logical_index & 15) * 64);

            status_word =
                mem_read64(
                    desc_addr + 40'h18
                );

            ownership_word =
                mem_read64(
                    desc_addr + 40'h08
                );

            if (status_word !==
                {
                    expected_length,
                    32'h0000_0001
                }) begin

                $display(
                    "FAIL: STATUS/ACTUAL writeback"
                );

                $fatal;
            end

            if (ownership_word !==
                {
                    (expected_control &
                     32'hFFFF_FFFE),
                    expected_length
                }) begin

                $display(
                    "FAIL: OWN release writeback"
                );

                $fatal;
            end

        end
    endtask

    integer i;
    integer dispatch_before;

    logic [63:0] expected_buffer;
    logic [63:0] expected_cookie;

    initial begin

        for (i = 0; i < 65536; i = i + 1)
            mem[i] = 8'd0;

        reset_system();
        configure_ring();

        /*
         * -------------------------------------------------------
         * Basic descriptor fetch -> dispatch -> retire -> writeback
         * -------------------------------------------------------
         */

        write_descriptor(
            0,
            64'h0000_0000_0000_8000,
            32'd64,
            32'h0000_0007,
            64'h1111_2222_3333_4444
        );

        sw_tail = 1;

        process_valid_descriptor(
            0,
            64'h0000_0000_0000_8000,
            32'd64,
            32'h0000_0007,
            64'h1111_2222_3333_4444
        );

        $display(
            "BASIC DESCRIPTOR LIFECYCLE: PASS"
        );

        /*
         * -------------------------------------------------------
         * Fill remainder of a 16-entry ring.
         * -------------------------------------------------------
         */

        for (i = 1; i < 16; i = i + 1) begin

            expected_buffer =
                64'h0000_0000_0000_8000 +
                (i * 16);

            expected_cookie =
                64'hA000_0000_0000_0000 +
                i;

            write_descriptor(
                i,
                expected_buffer,
                32'd64,
                32'h0000_0003,
                expected_cookie
            );

        end

        sw_tail = 16;

        for (i = 1; i < 16; i = i + 1) begin

            expected_buffer =
                64'h0000_0000_0000_8000 +
                (i * 16);

            expected_cookie =
                64'hA000_0000_0000_0000 +
                i;

            process_valid_descriptor(
                i,
                expected_buffer,
                32'd64,
                32'h0000_0003,
                expected_cookie
            );

        end

        /*
         * Logical descriptor 16 wraps back to physical slot 0.
         */
        write_descriptor(
            0,
            64'h0000_0000_0000_A000,
            32'd128,
            32'h0000_0003,
            64'hB000_0000_0000_0010
        );

        sw_tail = 17;

        process_valid_descriptor(
            16,
            64'h0000_0000_0000_A000,
            32'd128,
            32'h0000_0003,
            64'hB000_0000_0000_0010
        );

        $display(
            "INTEGRATED RING WRAPAROUND: PASS"
        );

        /*
         * -------------------------------------------------------
         * Invalid but HW-owned descriptor.
         *
         * Zero length must NOT reach payload work.
         * It is completed with ERROR + LENGTH_ERROR.
         * -------------------------------------------------------
         */

        dispatch_before = dispatch_count;

        write_descriptor(
            1,
            64'h0000_0000_0000_B000,
            32'd0,
            32'h0000_0001,
            64'hDEAD_0000_0000_0011
        );

        sw_tail = 18;

        while (!completion_pulse) begin

            @(posedge clk);
            #1;

            if (work_valid) begin

                $display(
                    "FAIL: invalid descriptor dispatched"
                );

                $fatal;
            end

            if (hw_head != 17) begin

                $display(
                    "FAIL: invalid descriptor advanced early"
                );

                $fatal;
            end
        end

        @(posedge clk);
        #1;

        if (hw_head != 18 ||
            dispatch_count != dispatch_before) begin

            $display(
                "FAIL: invalid descriptor retirement"
            );

            $fatal;
        end

        if (mem_read64(40'h0000_1058) !==
            {32'd0, 32'h0000_0023}) begin

            /*
             * COMPLETE + ERROR + LENGTH_ERROR:
             *
             * bit0 = 1
             * bit1 = 1
             * bit5 = 1
             *
             * 0x23
             */
            $display(
                "FAIL: invalid descriptor STATUS"
            );

            $fatal;
        end

        if (mem_read64(40'h0000_1048) !==
            {32'h0000_0000, 32'd0}) begin

            $display(
                "FAIL: invalid descriptor OWN not cleared"
            );

            $fatal;
        end

        $display(
            "INVALID DESCRIPTOR COMPLETION: PASS"
        );

        /*
         * -------------------------------------------------------
         * Ownership violation.
         *
         * OWN=0 means hardware must not modify or retire the
         * descriptor.
         * -------------------------------------------------------
         */

        reset_system();
        configure_ring();

        write_descriptor(
            0,
            64'h0000_0000_0000_C000,
            32'd64,
            32'h0000_0000,
            64'hCAFE_0000_0000_0001
        );

        sw_tail = 1;

        while (!fault_valid)
            @(posedge clk);

        #1;

        if (fault_code != 4'h2 ||
            hw_head != 0) begin

            $display(
                "FAIL: ownership violation handling"
            );

            $fatal;
        end

        if (mem_read64(40'h0000_1008) !==
            {32'h0000_0000, 32'd64}) begin

            $display(
                "FAIL: unowned descriptor modified"
            );

            $fatal;
        end

        $display(
            "OWNERSHIP VIOLATION: PASS"
        );

        /*
         * -------------------------------------------------------
         * Descriptor-read AXI failure.
         * -------------------------------------------------------
         */

        reset_system();
        configure_ring();

        write_descriptor(
            0,
            64'h0000_0000_0000_D000,
            32'd64,
            32'h0000_0001,
            64'hCAFE_0000_0000_0002
        );

        inject_read_error = 1;
        sw_tail = 1;

        while (!fault_valid)
            @(posedge clk);

        #1;

        if (fault_code != 4'h1 ||
            hw_head != 0) begin

            $display(
                "FAIL: descriptor-read error handling"
            );

            $fatal;
        end

        $display(
            "DESCRIPTOR READ ERROR PROPAGATION: PASS"
        );

        /*
         * -------------------------------------------------------
         * STATUS writeback AXI failure.
         *
         * HEAD must remain unchanged.
         * -------------------------------------------------------
         */

        reset_system();
        configure_ring();

        write_descriptor(
            0,
            64'h0000_0000_0000_E000,
            32'd64,
            32'h0000_0001,
            64'hCAFE_0000_0000_0003
        );

        inject_write_error_txn = 1;

        sw_tail = 1;

        accept_work(
            64'h0000_0000_0000_E000,
            32'd64,
            32'h0000_0001,
            64'hCAFE_0000_0000_0003,
            0
        );

        send_retirement(
            32'h0000_0001,
            32'd64
        );

        while (!fault_valid)
            @(posedge clk);

        #1;

        if (fault_code != 4'h3 ||
            hw_head != 0) begin

            $display(
                "FAIL: status-write error handling"
            );

            $fatal;
        end

        $display(
            "STATUS WRITE ERROR PROPAGATION: PASS"
        );

        /*
         * -------------------------------------------------------
         * OWN-release write AXI failure.
         *
         * First writeback succeeds.
         * Second writeback (CONTROL with OWN=0) fails.
         *
         * HEAD must remain unchanged because software ownership
         * has not been safely returned.
         * -------------------------------------------------------
         */

        reset_system();
        configure_ring();

        write_descriptor(
            0,
            64'h0000_0000_0000_F000,
            32'd64,
            32'h0000_0001,
            64'hCAFE_0000_0000_0004
        );

        /*
         * Fail the SECOND B response:
         *
         * B #1 = STATUS / ACTUAL_LENGTH
         * B #2 = OWN clear
         */
        inject_write_error_txn = 2;

        sw_tail = 1;

        accept_work(
            64'h0000_0000_0000_F000,
            32'd64,
            32'h0000_0001,
            64'hCAFE_0000_0000_0004,
            0
        );

        send_retirement(
            32'h0000_0001,
            32'd64
        );

        while (!fault_valid)
            @(posedge clk);

        #1;

        if (fault_code != 4'h4 ||
            hw_head != 0) begin

            $display(
                "FAIL: OWN-release write error handling"
            );

            $fatal;
        end

        /*
         * STATUS write must already have succeeded.
         */
        if (mem_read64(40'h0000_1018) !==
            {32'd64, 32'h0000_0001}) begin

            $display(
                "FAIL: STATUS not committed before OWN failure"
            );

            $fatal;
        end

        /*
         * IMPORTANT AXI FAILURE SEMANTICS
         *
         * Do NOT assert that descriptor memory still contains
         * OWN=1 here.
         *
         * The write-data beat may already have reached the slave
         * before the slave returns an error BRESP. A failed BRESP
         * therefore does not provide transactional rollback of the
         * memory side effect.
         *
         * The architectural safety invariant is instead:
         *
         *   HW_HEAD MUST NOT advance.
         *
         * HW_HEAD is the authoritative software-visible publication
         * that descriptor ownership has been successfully retired.
         *
         * Descriptor memory contents after a failed ownership-release
         * transaction are considered untrusted until software recovery.
         */

        if (hw_head != 0) begin

            $display(
                "FAIL: HEAD advanced after failed OWN release"
            );

            $fatal;
        end

        if (completion_pulse) begin

            $display(
                "FAIL: completion published after failed OWN release"
            );

            $fatal;
        end

        $display(
            "OWN RELEASE WRITE ERROR PROPAGATION: PASS"
        );

        $display("");
        $display("================================================");
        $display(" DMA DESCRIPTOR ENGINE: PASS");
        $display(" DDR descriptor fetch             : PASS");
        $display(" 64-byte descriptor assembly      : PASS");
        $display(" parser integration               : PASS");
        $display(" ring-address generation          : PASS");
        $display(" work backpressure stability      : PASS");
        $display(" payload retirement               : PASS");
        $display(" STATUS/ACTUAL writeback          : PASS");
        $display(" OWN release ordering             : PASS");
        $display(" HEAD-after-writeback invariant   : PASS");
        $display(" integrated ring wraparound       : PASS");
        $display(" invalid descriptor completion    : PASS");
        $display(" ownership violation detection    : PASS");
        $display(" AXI read failure propagation     : PASS");
        $display(" STATUS write failure propagation : PASS");
        $display(" OWN-write failure propagation    : PASS");
        $display("================================================");

        $finish;
    end

    initial begin

        #20_000_000;

        $display(
            "FAIL: descriptor engine timeout / possible deadlock"
        );

        $fatal;

    end

endmodule
