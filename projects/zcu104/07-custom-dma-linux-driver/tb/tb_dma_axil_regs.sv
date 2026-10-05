`timescale 1ns/1ps

module tb_dma_axil_regs;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn;

    logic [11:0] awaddr;
    logic [2:0]  awprot;
    logic        awvalid;
    logic        awready;

    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;

    logic [1:0] bresp;
    logic       bvalid;
    logic       bready;

    logic [11:0] araddr;
    logic [2:0]  arprot;
    logic        arvalid;
    logic        arready;

    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

    logic global_enable;
    logic soft_reset_pulse;
    logic counter_clear_pulse;

    logic [31:0] global_status;

    logic tx_completion_event;
    logic rx_completion_event;
    logic tx_error_event;
    logic rx_error_event;

    logic [3:0] irq_status;
    logic [3:0] irq_enable;
    logic       irq;

    logic [31:0] error_set;
    logic [31:0] error_info;
    logic [63:0] error_addr;
    logic [31:0] error_status;

    logic        tx_enable;
    logic        tx_halt;
    logic [63:0] tx_ring_base;
    logic [15:0] tx_ring_size;
    logic [31:0] tx_tail;
    logic        tx_cfg_load_pulse;

    logic [31:0] tx_status;
    logic [31:0] tx_head;
    logic [63:0] tx_bytes;
    logic [31:0] tx_desc_count;
    logic [63:0] tx_active_cycles;
    logic [63:0] tx_axi_stall;
    logic [63:0] tx_axis_stall;

    logic        rx_enable;
    logic        rx_halt;
    logic [63:0] rx_ring_base;
    logic [15:0] rx_ring_size;
    logic [31:0] rx_tail;
    logic        rx_cfg_load_pulse;

    logic [31:0] rx_status;
    logic [31:0] rx_head;
    logic [63:0] rx_bytes;
    logic [31:0] rx_desc_count;
    logic [63:0] rx_active_cycles;
    logic [63:0] rx_axi_stall;
    logic [63:0] rx_axis_stall;

    logic [31:0] scratch;
    logic        scratch_write_pulse;

    integer soft_reset_count;
    integer counter_clear_count;
    integer tx_cfg_count;
    integer rx_cfg_count;
    integer scratch_write_count;

    dma_axil_regs dut (
        .clk                     (clk),
        .aresetn                 (aresetn),

        .s_axil_awaddr           (awaddr),
        .s_axil_awprot           (awprot),
        .s_axil_awvalid          (awvalid),
        .s_axil_awready          (awready),

        .s_axil_wdata            (wdata),
        .s_axil_wstrb            (wstrb),
        .s_axil_wvalid           (wvalid),
        .s_axil_wready           (wready),

        .s_axil_bresp            (bresp),
        .s_axil_bvalid           (bvalid),
        .s_axil_bready           (bready),

        .s_axil_araddr           (araddr),
        .s_axil_arprot           (arprot),
        .s_axil_arvalid          (arvalid),
        .s_axil_arready          (arready),

        .s_axil_rdata            (rdata),
        .s_axil_rresp            (rresp),
        .s_axil_rvalid           (rvalid),
        .s_axil_rready           (rready),

        .global_enable           (global_enable),
        .soft_reset_pulse        (soft_reset_pulse),
        .counter_clear_pulse     (counter_clear_pulse),
        .global_status           (global_status),

        .tx_completion_event     (tx_completion_event),
        .rx_completion_event     (rx_completion_event),
        .tx_error_event          (tx_error_event),
        .rx_error_event          (rx_error_event),

        .irq_status              (irq_status),
        .irq_enable              (irq_enable),
        .irq                     (irq),

        .error_set               (error_set),
        .error_info              (error_info),
        .error_addr              (error_addr),
        .error_status            (error_status),

        .tx_enable               (tx_enable),
        .tx_halt                 (tx_halt),
        .tx_ring_base            (tx_ring_base),
        .tx_ring_size            (tx_ring_size),
        .tx_tail                 (tx_tail),
        .tx_cfg_load_pulse       (tx_cfg_load_pulse),

        .tx_status               (tx_status),
        .tx_head                 (tx_head),
        .tx_bytes                (tx_bytes),
        .tx_desc_count           (tx_desc_count),
        .tx_active_cycles        (tx_active_cycles),
        .tx_axi_stall            (tx_axi_stall),
        .tx_axis_stall           (tx_axis_stall),

        .rx_enable               (rx_enable),
        .rx_halt                 (rx_halt),
        .rx_ring_base            (rx_ring_base),
        .rx_ring_size            (rx_ring_size),
        .rx_tail                 (rx_tail),
        .rx_cfg_load_pulse       (rx_cfg_load_pulse),

        .rx_status               (rx_status),
        .rx_head                 (rx_head),
        .rx_bytes                (rx_bytes),
        .rx_desc_count           (rx_desc_count),
        .rx_active_cycles        (rx_active_cycles),
        .rx_axi_stall            (rx_axi_stall),
        .rx_axis_stall           (rx_axis_stall),

        .scratch                 (scratch),
        .scratch_write_pulse     (scratch_write_pulse)
    );

    always_ff @(posedge clk) begin

        if (!aresetn) begin

            soft_reset_count    <= 0;
            counter_clear_count <= 0;
            tx_cfg_count        <= 0;
            rx_cfg_count        <= 0;
            scratch_write_count <= 0;

        end
        else begin

            if (soft_reset_pulse)
                soft_reset_count <=
                    soft_reset_count + 1;

            if (counter_clear_pulse)
                counter_clear_count <=
                    counter_clear_count + 1;

            if (tx_cfg_load_pulse)
                tx_cfg_count <=
                    tx_cfg_count + 1;

            if (rx_cfg_load_pulse)
                rx_cfg_count <=
                    rx_cfg_count + 1;

            if (scratch_write_pulse)
                scratch_write_count <=
                    scratch_write_count + 1;

        end

    end

    task automatic drive_aw(
        input logic [11:0] address,
        input integer delay_cycles
    );

        begin

            repeat (delay_cycles)
                @(posedge clk);

            @(negedge clk);

            awaddr  = address;
            awvalid = 1'b1;

            do begin
                @(posedge clk);
            end while (!awready);

            @(negedge clk);

            awvalid = 1'b0;

        end

    endtask

    task automatic drive_w(
        input logic [31:0] value,
        input logic [3:0]  strobes,
        input integer delay_cycles
    );

        begin

            repeat (delay_cycles)
                @(posedge clk);

            @(negedge clk);

            wdata  = value;
            wstrb  = strobes;
            wvalid = 1'b1;

            do begin
                @(posedge clk);
            end while (!wready);

            @(negedge clk);

            wvalid = 1'b0;

        end

    endtask

    task automatic axil_write(
        input logic [11:0] address,
        input logic [31:0] value,
        input logic [3:0]  strobes,
        input integer      aw_delay,
        input integer      w_delay,
        input logic [1:0]  expected_resp
    );

        logic [1:0] saved_resp;
        integer hold_cycle;

        begin

            bready =
                1'b0;

            fork

                drive_aw(
                    address,
                    aw_delay
                );

                drive_w(
                    value,
                    strobes,
                    w_delay
                );

            join

            while (!bvalid)
                @(posedge clk);

            saved_resp =
                bresp;

            /*
             * Force B-channel backpressure and verify stability.
             */
            for (hold_cycle = 0;
                 hold_cycle < 3;
                 hold_cycle = hold_cycle + 1) begin

                @(posedge clk);
                #1;

                if (!bvalid ||
                    bresp !== saved_resp) begin

                    $display(
                        "FAIL: BVALID/BRESP unstable under backpressure"
                    );
                    $fatal;

                end

            end

            if (saved_resp !==
                expected_resp) begin

                $display(
                    "FAIL WRITE address=%h BRESP=%b expected=%b",
                    address,
                    saved_resp,
                    expected_resp
                );
                $fatal;

            end

            @(negedge clk);

            bready =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            bready =
                1'b0;

        end

    endtask

    task automatic axil_read(
        input logic [11:0] address,
        input logic [31:0] expected_data,
        input logic [1:0]  expected_resp
    );

        logic [31:0] saved_data;
        logic [1:0]  saved_resp;
        integer hold_cycle;

        begin

            rready =
                1'b0;

            @(negedge clk);

            araddr  =
                address;

            arvalid =
                1'b1;

            do begin
                @(posedge clk);
            end while (!arready);

            @(negedge clk);

            arvalid =
                1'b0;

            while (!rvalid)
                @(posedge clk);

            saved_data =
                rdata;

            saved_resp =
                rresp;

            /*
             * Force R-channel backpressure and verify stability.
             */
            for (hold_cycle = 0;
                 hold_cycle < 3;
                 hold_cycle = hold_cycle + 1) begin

                @(posedge clk);
                #1;

                if (!rvalid ||
                    rdata !== saved_data ||
                    rresp !== saved_resp) begin

                    $display(
                        "FAIL: RVALID/RDATA/RRESP unstable under backpressure"
                    );
                    $fatal;

                end

            end

            if (saved_data !==
                expected_data ||
                saved_resp !==
                expected_resp) begin

                $display(
                    "FAIL READ address=%h data=%h expected=%h resp=%b expected_resp=%b",
                    address,
                    saved_data,
                    expected_data,
                    saved_resp,
                    expected_resp
                );
                $fatal;

            end

            @(negedge clk);

            rready =
                1'b1;

            @(posedge clk);
            @(negedge clk);

            rready =
                1'b0;

        end

    endtask

    task automatic pulse_irq_event(
        input integer source
    );

        begin

            @(negedge clk);

            case (source)

                0:
                    tx_completion_event =
                        1'b1;

                1:
                    rx_completion_event =
                        1'b1;

                2:
                    tx_error_event =
                        1'b1;

                3:
                    rx_error_event =
                        1'b1;

            endcase

            @(posedge clk);
            @(negedge clk);

            tx_completion_event =
                1'b0;

            rx_completion_event =
                1'b0;

            tx_error_event =
                1'b0;

            rx_error_event =
                1'b0;

        end

    endtask

    initial begin

        aresetn = 1'b0;

        awaddr  = 12'd0;
        awprot  = 3'd0;
        awvalid = 1'b0;

        wdata   = 32'd0;
        wstrb   = 4'd0;
        wvalid  = 1'b0;

        bready  = 1'b0;

        araddr  = 12'd0;
        arprot  = 3'd0;
        arvalid = 1'b0;

        rready  = 1'b0;

        global_status =
            32'h1357_2468;

        tx_completion_event =
            1'b0;

        rx_completion_event =
            1'b0;

        tx_error_event =
            1'b0;

        rx_error_event =
            1'b0;

        error_set =
            32'd0;

        error_info =
            32'hCAFE_BABE;

        error_addr =
            64'h0000_0001_2345_6780;

        tx_status =
            32'h0000_00A5;

        tx_head =
            32'h0000_0021;

        tx_bytes =
            64'h1122_3344_5566_7788;

        tx_desc_count =
            32'h1234_5678;

        tx_active_cycles =
            64'h0102_0304_0506_0708;

        tx_axi_stall =
            64'h1112_1314_1516_1718;

        tx_axis_stall =
            64'h2122_2324_2526_2728;

        rx_status =
            32'h0000_005A;

        rx_head =
            32'h0000_0042;

        rx_bytes =
            64'h8877_6655_4433_2211;

        rx_desc_count =
            32'h8765_4321;

        rx_active_cycles =
            64'h3132_3334_3536_3738;

        rx_axi_stall =
            64'h4142_4344_4546_4748;

        rx_axis_stall =
            64'h5152_5354_5556_5758;

        repeat (8)
            @(posedge clk);

        aresetn =
            1'b1;

        repeat (3)
            @(posedge clk);

        /*
         * --------------------------------------------------------
         * IDENTIFICATION / READ BACKPRESSURE
         * --------------------------------------------------------
         */

        axil_read(
            12'h000,
            32'h4344_4D41,
            2'b00
        );

        axil_read(
            12'h004,
            32'h0001_0000,
            2'b00
        );

        $display(
            "ID / VERSION READBACK: PASS"
        );

        /*
         * --------------------------------------------------------
         * AW BEFORE W
         * --------------------------------------------------------
         */

        axil_write(
            12'h3FC,
            32'h1122_3344,
            4'b1111,
            0,
            4,
            2'b00
        );

        axil_read(
            12'h3FC,
            32'h1122_3344,
            2'b00
        );

        /*
         * --------------------------------------------------------
         * W BEFORE AW
         * --------------------------------------------------------
         */

        axil_write(
            12'h3FC,
            32'hAABB_CCDD,
            4'b1111,
            4,
            0,
            2'b00
        );

        axil_read(
            12'h3FC,
            32'hAABB_CCDD,
            2'b00
        );

        /*
         * Partial byte strobes.
         *
         * AABBCCDD with byte0+byte2 replaced by 44 and 22:
         * AA22CC44
         */
        axil_write(
            12'h3FC,
            32'h1122_3344,
            4'b0101,
            0,
            0,
            2'b00
        );

        axil_read(
            12'h3FC,
            32'hAA22_CC44,
            2'b00
        );

        if (scratch_write_count != 3) begin

            $display(
                "FAIL: scratch write pulse count=%0d",
                scratch_write_count
            );
            $fatal;

        end

        $display(
            "AXIL AW/W INDEPENDENCE + WSTRB: PASS"
        );

        /*
         * --------------------------------------------------------
         * GLOBAL CONTROL PULSES
         * --------------------------------------------------------
         */

        axil_write(
            12'h008,
            32'h0000_0007,
            4'b0001,
            0,
            0,
            2'b00
        );

        if (!global_enable ||
            soft_reset_count != 1 ||
            counter_clear_count != 1) begin

            $display(
                "FAIL: GLOBAL_CONTROL behavior"
            );
            $fatal;

        end

        repeat (3)
            @(posedge clk);

        if (soft_reset_pulse ||
            counter_clear_pulse) begin

            $display(
                "FAIL: command pulse persisted"
            );
            $fatal;

        end

        axil_read(
            12'h008,
            32'h0000_0001,
            2'b00
        );

        $display(
            "GLOBAL CONTROL / ONE-CYCLE COMMANDS: PASS"
        );

        /*
         * --------------------------------------------------------
         * IRQ INTEGRATION
         * --------------------------------------------------------
         */

        axil_write(
            12'h014,
            32'h0000_000F,
            4'b0001,
            0,
            0,
            2'b00
        );

        pulse_irq_event(0);

        axil_read(
            12'h010,
            32'h0000_0001,
            2'b00
        );

        if (!irq) begin

            $display(
                "FAIL: enabled TX completion did not assert IRQ"
            );
            $fatal;

        end

        /*
         * RW1C interrupt acknowledgement.
         */
        axil_write(
            12'h010,
            32'h0000_0001,
            4'b0001,
            0,
            0,
            2'b00
        );

        repeat (2)
            @(posedge clk);

        axil_read(
            12'h010,
            32'h0000_0000,
            2'b00
        );

        if (irq) begin

            $display(
                "FAIL: IRQ remained asserted after acknowledgement"
            );
            $fatal;

        end

        /*
         * Masked cause still latches.
         */
        axil_write(
            12'h014,
            32'h0000_0000,
            4'b0001,
            0,
            0,
            2'b00
        );

        pulse_irq_event(3);

        if (irq) begin

            $display(
                "FAIL: masked RX error asserted IRQ"
            );
            $fatal;

        end

        axil_read(
            12'h010,
            32'h0000_0008,
            2'b00
        );

        axil_write(
            12'h014,
            32'h0000_0008,
            4'b0001,
            0,
            0,
            2'b00
        );

        if (!irq) begin

            $display(
                "FAIL: enabling pending RX error did not assert IRQ"
            );
            $fatal;

        end

        axil_write(
            12'h010,
            32'h0000_0008,
            4'b0001,
            0,
            0,
            2'b00
        );

        repeat (2)
            @(posedge clk);

        $display(
            "IRQ STATUS / ENABLE / RW1C: PASS"
        );

        /*
         * --------------------------------------------------------
         * ERROR STATUS RW1C
         * --------------------------------------------------------
         */

        @(negedge clk);

        error_set =
            32'h0000_0005;

        @(posedge clk);
        @(negedge clk);

        error_set =
            32'd0;

        axil_read(
            12'h018,
            32'h0000_0005,
            2'b00
        );

        axil_read(
            12'h01C,
            32'hCAFE_BABE,
            2'b00
        );

        axil_read(
            12'h020,
            32'h2345_6780,
            2'b00
        );

        axil_read(
            12'h024,
            32'h0000_0001,
            2'b00
        );

        axil_write(
            12'h018,
            32'h0000_0001,
            4'b1111,
            0,
            0,
            2'b00
        );

        repeat (2)
            @(posedge clk);

        axil_read(
            12'h018,
            32'h0000_0004,
            2'b00
        );

        $display(
            "GLOBAL ERROR RW1C: PASS"
        );

        /*
         * --------------------------------------------------------
         * TX REGISTER BANK
         * --------------------------------------------------------
         */

        axil_write(
            12'h108,
            32'h89AB_C000,
            4'b1111,
            0,
            0,
            2'b00
        );

        axil_write(
            12'h10C,
            32'h0000_0001,
            4'b1111,
            0,
            0,
            2'b00
        );

        axil_write(
            12'h110,
            32'd256,
            4'b0011,
            0,
            0,
            2'b00
        );

        axil_write(
            12'h114,
            32'h1234_5678,
            4'b1111,
            0,
            0,
            2'b00
        );

        axil_write(
            12'h100,
            32'h0000_0003,
            4'b0001,
            0,
            0,
            2'b00
        );

        if (tx_ring_base !==
            64'h0000_0001_89AB_C000 ||
            tx_ring_size !== 16'd256 ||
            tx_tail !== 32'h1234_5678 ||
            !tx_enable ||
            !tx_halt ||
            tx_cfg_count != 1) begin

            $display(
                "FAIL: TX writable register bank"
            );
            $fatal;

        end

        axil_read(
            12'h108,
            32'h89AB_C000,
            2'b00
        );

        axil_read(
            12'h10C,
            32'h0000_0001,
            2'b00
        );

        axil_read(
            12'h110,
            32'd256,
            2'b00
        );

        axil_read(
            12'h114,
            32'h1234_5678,
            2'b00
        );

        axil_read(
            12'h118,
            32'h0000_0021,
            2'b00
        );

        axil_read(
            12'h11C,
            32'h5566_7788,
            2'b00
        );

        axil_read(
            12'h120,
            32'h1122_3344,
            2'b00
        );

        axil_read(
            12'h124,
            32'h1234_5678,
            2'b00
        );

        axil_read(
            12'h128,
            32'h0506_0708,
            2'b00
        );

        axil_read(
            12'h12C,
            32'h0102_0304,
            2'b00
        );

        axil_read(
            12'h130,
            32'h1516_1718,
            2'b00
        );

        axil_read(
            12'h134,
            32'h1112_1314,
            2'b00
        );

        axil_read(
            12'h138,
            32'h2526_2728,
            2'b00
        );

        axil_read(
            12'h13C,
            32'h2122_2324,
            2'b00
        );

        $display(
            "TX REGISTER BANK: PASS"
        );

        /*
         * --------------------------------------------------------
         * RX REGISTER BANK
         * --------------------------------------------------------
         */

        axil_write(
            12'h208,
            32'h7654_3000,
            4'b1111,
            0,
            0,
            2'b00
        );

        axil_write(
            12'h20C,
            32'h0000_0002,
            4'b1111,
            0,
            0,
            2'b00
        );

        axil_write(
            12'h210,
            32'd512,
            4'b0011,
            0,
            0,
            2'b00
        );

        axil_write(
            12'h214,
            32'h8765_4321,
            4'b1111,
            0,
            0,
            2'b00
        );

        axil_write(
            12'h200,
            32'h0000_0001,
            4'b0001,
            0,
            0,
            2'b00
        );

        if (rx_ring_base !==
            64'h0000_0002_7654_3000 ||
            rx_ring_size !== 16'd512 ||
            rx_tail !== 32'h8765_4321 ||
            !rx_enable ||
            rx_halt ||
            rx_cfg_count != 1) begin

            $display(
                "FAIL: RX writable register bank"
            );
            $fatal;

        end

        axil_read(
            12'h218,
            32'h0000_0042,
            2'b00
        );

        axil_read(
            12'h21C,
            32'h4433_2211,
            2'b00
        );

        axil_read(
            12'h220,
            32'h8877_6655,
            2'b00
        );

        axil_read(
            12'h224,
            32'h8765_4321,
            2'b00
        );

        axil_read(
            12'h228,
            32'h3536_3738,
            2'b00
        );

        axil_read(
            12'h22C,
            32'h3132_3334,
            2'b00
        );

        axil_read(
            12'h230,
            32'h4546_4748,
            2'b00
        );

        axil_read(
            12'h234,
            32'h4142_4344,
            2'b00
        );

        axil_read(
            12'h238,
            32'h5556_5758,
            2'b00
        );

        axil_read(
            12'h23C,
            32'h5152_5354,
            2'b00
        );

        $display(
            "RX REGISTER BANK: PASS"
        );

        /*
         * --------------------------------------------------------
         * RO PROTECTION
         * --------------------------------------------------------
         */

        axil_write(
            12'h000,
            32'hDEAD_BEEF,
            4'b1111,
            0,
            0,
            2'b10
        );

        axil_read(
            12'h000,
            32'h4344_4D41,
            2'b00
        );

        axil_write(
            12'h118,
            32'hFFFF_FFFF,
            4'b1111,
            0,
            0,
            2'b10
        );

        axil_read(
            12'h118,
            32'h0000_0021,
            2'b00
        );

        $display(
            "READ-ONLY REGISTER PROTECTION: PASS"
        );

        /*
         * --------------------------------------------------------
         * UNMAPPED ACCESS
         * --------------------------------------------------------
         */

        axil_write(
            12'h300,
            32'hABCD_EF01,
            4'b1111,
            0,
            0,
            2'b11
        );

        axil_read(
            12'h300,
            32'h0000_0000,
            2'b11
        );

        $display(
            "UNMAPPED ACCESS DECERR: PASS"
        );

        /*
         * Global RO status read.
         */
        axil_read(
            12'h00C,
            32'h1357_2468,
            2'b00
        );

        $display("");
        $display("================================================");
        $display(" DMA AXI-LITE REGISTER BANK: PASS");
        $display(" ID constant                    : PASS");
        $display(" VERSION constant               : PASS");
        $display(" AW-before-W                    : PASS");
        $display(" W-before-AW                    : PASS");
        $display(" simultaneous AW/W              : PASS");
        $display(" BVALID/BRESP backpressure      : PASS");
        $display(" RVALID/RDATA backpressure      : PASS");
        $display(" WSTRB byte writes              : PASS");
        $display(" SCRATCH round-trip             : PASS");
        $display(" GLOBAL_ENABLE                  : PASS");
        $display(" SOFT_RESET one-cycle pulse     : PASS");
        $display(" COUNTER_CLEAR one-cycle pulse  : PASS");
        $display(" IRQ controller integration     : PASS");
        $display(" IRQ_STATUS RW1C                : PASS");
        $display(" IRQ_ENABLE                     : PASS");
        $display(" ERROR_STATUS RW1C              : PASS");
        $display(" TX register bank               : PASS");
        $display(" RX register bank               : PASS");
        $display(" counter/status readback        : PASS");
        $display(" read-only protection           : PASS");
        $display(" unmapped DECERR                : PASS");
        $display("================================================");

        $finish;

    end

    initial begin

        #10_000_000;

        $display(
            "FAIL: AXI-Lite register test timeout"
        );

        $fatal;

    end

endmodule
