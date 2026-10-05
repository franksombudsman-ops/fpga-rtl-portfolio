`timescale 1ns/1ps

module tb_dma_ring_manager;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn = 1'b0;

    logic        cfg_load;
    logic [63:0] cfg_ring_base;
    logic [15:0] cfg_ring_size;

    logic        config_valid;
    logic [3:0]  config_error_code;

    logic [31:0] sw_tail;
    logic        advance_head;

    logic [31:0] hw_head;
    logic [31:0] pending_count;

    logic        ring_empty;
    logic        ring_overrun;
    logic        descriptor_available;

    logic [15:0] slot_index;
    logic [39:0] descriptor_addr;

    dma_ring_manager dut (
        .clk                  (clk),
        .aresetn              (aresetn),

        .cfg_load             (cfg_load),
        .cfg_ring_base        (cfg_ring_base),
        .cfg_ring_size        (cfg_ring_size),

        .config_valid         (config_valid),
        .config_error_code    (config_error_code),

        .sw_tail              (sw_tail),
        .advance_head         (advance_head),

        .hw_head              (hw_head),
        .pending_count        (pending_count),

        .ring_empty           (ring_empty),
        .ring_overrun         (ring_overrun),
        .descriptor_available (descriptor_available),

        .slot_index           (slot_index),
        .descriptor_addr      (descriptor_addr)
    );

    task automatic load_config(
        input logic [63:0] base,
        input logic [15:0] size,
        input logic        expected_valid,
        input logic [3:0]  expected_error
    );

        begin

            sw_tail = 0;

            @(negedge clk);

            cfg_ring_base = base;
            cfg_ring_size = size;
            cfg_load      = 1'b1;

            @(posedge clk);
            @(negedge clk);

            cfg_load = 1'b0;

            #1;

            if (config_valid !== expected_valid ||
                config_error_code !== expected_error) begin

                $display(
                    "FAIL config base=%h size=%0d valid=%b/%b error=%0d/%0d",
                    base,
                    size,
                    config_valid,
                    expected_valid,
                    config_error_code,
                    expected_error
                );

                $fatal;
            end
        end
    endtask

    task automatic advance_one;
        begin

            @(negedge clk);
            advance_head = 1'b1;

            @(posedge clk);
            @(negedge clk);

            advance_head = 1'b0;

        end
    endtask

    integer i;
    integer expected_slot;

    initial begin

        cfg_load       = 1'b0;
        cfg_ring_base  = 64'd0;
        cfg_ring_size  = 16'd0;
        sw_tail        = 32'd0;
        advance_head   = 1'b0;

        repeat (5) @(posedge clk);
        aresetn = 1'b1;
        repeat (2) @(posedge clk);

        /*
         * Basic 16-entry ring.
         */
        load_config(
            64'h0000_0000_0010_0000,
            16,
            1'b1,
            4'h0
        );

        #1;

        if (!ring_empty ||
            descriptor_available ||
            hw_head != 0) begin

            $display("FAIL: initial empty-ring state");
            $fatal;
        end

        sw_tail = 1;
        #1;

        if (!descriptor_available ||
            pending_count != 1 ||
            slot_index != 0 ||
            descriptor_addr != 40'h0010_0000) begin

            $display("FAIL: first descriptor address/state");
            $fatal;
        end

        advance_one();
        #1;

        if (hw_head != 1 || !ring_empty) begin
            $display("FAIL: first head advance");
            $fatal;
        end

        $display("BASIC RING OPERATION: PASS");

        /*
         * Three complete wraps through a 16-entry ring.
         * Software exposes one descriptor at a time so the
         * producer never overruns the consumer.
         */
        load_config(
            64'h0000_0000_0020_0000,
            16,
            1'b1,
            4'h0
        );

        for (i = 0; i < 48; i = i + 1) begin

            sw_tail = i + 1;
            #1;

            expected_slot = i & 15;

            if (!descriptor_available ||
                hw_head != i ||
                slot_index != expected_slot ||
                descriptor_addr !=
                    (40'h0020_0000 +
                     (expected_slot * 64))) begin

                $display(
                    "FAIL wrap i=%0d head=%0d slot=%0d addr=%h",
                    i,
                    hw_head,
                    slot_index,
                    descriptor_addr
                );

                $fatal;
            end

            advance_one();
        end

        sw_tail = 48;
        #1;

        if (hw_head != 48 || !ring_empty) begin
            $display("FAIL: multi-wrap completion");
            $fatal;
        end

        $display("MULTIPLE RING WRAPS: PASS");

        /*
         * 64-entry ring traversal.
         */
        load_config(
            64'h0000_0000_0030_0000,
            64,
            1'b1,
            4'h0
        );

        for (i = 0; i < 70; i = i + 1) begin

            sw_tail = i + 1;
            #1;

            expected_slot = i & 63;

            if (slot_index != expected_slot ||
                descriptor_addr !=
                    (40'h0030_0000 +
                     (expected_slot * 64))) begin

                $display("FAIL: 64-entry wrap");
                $fatal;
            end

            advance_one();
        end

        $display("64-ENTRY RING: PASS");

        /*
         * 1024-entry ring traversal including wrap.
         */
        load_config(
            64'h0000_0000_0040_0000,
            1024,
            1'b1,
            4'h0
        );

        for (i = 0; i < 1030; i = i + 1) begin

            sw_tail = i + 1;
            #1;

            expected_slot = i & 1023;

            if (slot_index != expected_slot ||
                descriptor_addr !=
                    (40'h0040_0000 +
                     (expected_slot * 64))) begin

                $display(
                    "FAIL: 1024-entry ring i=%0d",
                    i
                );

                $fatal;
            end

            advance_one();
        end

        $display("1024-ENTRY RING: PASS");

        /*
         * Producer overrun.
         */
        load_config(
            64'h0000_0000_0050_0000,
            16,
            1'b1,
            4'h0
        );

        sw_tail = 17;
        #1;

        if (!ring_overrun ||
            descriptor_available) begin

            $display("FAIL: ring overrun not detected");
            $fatal;
        end

        $display("RING OVERRUN DETECTION: PASS");

        /*
         * Invalid configuration cases.
         */
        load_config(
            64'h0000_0000_0010_0001,
            16,
            1'b0,
            4'h1
        );

        load_config(
            64'h0000_0100_0010_0000,
            16,
            1'b0,
            4'h2
        );

        load_config(
            64'h0000_0000_0010_0000,
            12,
            1'b0,
            4'h3
        );

        load_config(
            64'h0000_0000_0010_0000,
            24,
            1'b0,
            4'h4
        );

        load_config(
            ((64'h1 << 40) - 64),
            16,
            1'b0,
            4'h5
        );

        $display("RING CONFIGURATION VALIDATION: PASS");

        $display("");
        $display("============================================");
        $display(" DMA RING MANAGER: PASS");
        $display(" empty/non-empty state       : PASS");
        $display(" logical head progression    : PASS");
        $display(" slot-index wraparound       : PASS");
        $display(" descriptor address mapping  : PASS");
        $display(" 16/64/1024 entry rings      : PASS");
        $display(" producer-overrun detection  : PASS");
        $display(" configuration validation    : PASS");
        $display("============================================");

        $finish;
    end

    initial begin
        #5_000_000;
        $display("FAIL: ring simulation timeout");
        $fatal;
    end

endmodule
