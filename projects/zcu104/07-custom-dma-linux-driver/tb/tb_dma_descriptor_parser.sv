`timescale 1ns/1ps

module tb_dma_descriptor_parser;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn = 1'b0;

    logic         desc_valid;
    logic         desc_ready;
    logic [511:0] desc_data;

    logic         parsed_valid;
    logic         parsed_ready;

    logic [63:0]  buffer_addr;
    logic [31:0]  length;
    logic [31:0]  control;
    logic [63:0]  cookie;

    logic own;
    logic irq_on_completion;
    logic end_of_packet;

    logic descriptor_ok;
    logic [5:0] error_flags;

    dma_descriptor_parser dut (
        .clk               (clk),
        .aresetn           (aresetn),

        .desc_valid        (desc_valid),
        .desc_ready        (desc_ready),
        .desc_data         (desc_data),

        .parsed_valid      (parsed_valid),
        .parsed_ready      (parsed_ready),

        .buffer_addr       (buffer_addr),
        .length            (length),
        .control           (control),
        .cookie            (cookie),

        .own               (own),
        .irq_on_completion (irq_on_completion),
        .end_of_packet     (end_of_packet),

        .descriptor_ok     (descriptor_ok),
        .error_flags       (error_flags)
    );

    function automatic [511:0] make_descriptor(
        input logic [63:0] addr,
        input logic [31:0] len,
        input logic [31:0] ctrl,
        input logic [63:0] tag
    );

        logic [511:0] d;

        begin

            d = 512'd0;

            d[63:0]    = addr;
            d[95:64]   = len;
            d[127:96]  = ctrl;
            d[191:128] = tag;

            make_descriptor = d;

        end
    endfunction

    task automatic send_and_check(
        input logic [511:0] d,
        input logic         expected_ok,
        input logic [5:0]   expected_errors
    );

        begin

            @(negedge clk);

            desc_data  = d;
            desc_valid = 1'b1;

            do begin
                @(posedge clk);
            end while (!desc_ready);

            #1;

            if (!parsed_valid) begin
                $display("FAIL: parsed_valid missing");
                $fatal;
            end

            if (descriptor_ok !== expected_ok) begin
                $display(
                    "FAIL descriptor_ok got=%b expected=%b",
                    descriptor_ok,
                    expected_ok
                );
                $fatal;
            end

            if (error_flags !== expected_errors) begin
                $display(
                    "FAIL error flags got=%b expected=%b",
                    error_flags,
                    expected_errors
                );
                $fatal;
            end

            @(negedge clk);
            desc_valid = 1'b0;

            @(posedge clk);

        end
    endtask

    initial begin

        desc_valid   = 1'b0;
        desc_data    = 512'd0;
        parsed_ready = 1'b1;

        repeat (5) @(posedge clk);
        aresetn = 1'b1;
        repeat (2) @(posedge clk);

        send_and_check(
            make_descriptor(
                64'h0000_0000_0010_0000,
                32'd4096,
                32'h0000_0007,
                64'h1122_3344_5566_7788
            ),
            1'b1,
            6'b000000
        );

        if (buffer_addr !== 64'h0000_0000_0010_0000 ||
            length      !== 32'd4096 ||
            cookie      !== 64'h1122_3344_5566_7788 ||
            !own ||
            !irq_on_completion ||
            !end_of_packet) begin

            $display("FAIL: valid descriptor field mapping");
            $fatal;

        end

        $display("VALID DESCRIPTOR PARSE: PASS");

        /*
         * OWN missing.
         */
        send_and_check(
            make_descriptor(
                64'h0000_0000_0010_0000,
                32'd64,
                32'h0000_0000,
                64'd1
            ),
            1'b0,
            6'b000001
        );

        /*
         * Zero length.
         */
        send_and_check(
            make_descriptor(
                64'h0000_0000_0010_0000,
                32'd0,
                32'h0000_0001,
                64'd2
            ),
            1'b0,
            6'b000010
        );

        /*
         * Length alignment.
         */
        send_and_check(
            make_descriptor(
                64'h0000_0000_0010_0000,
                32'd15,
                32'h0000_0001,
                64'd3
            ),
            1'b0,
            6'b000100
        );

        /*
         * Buffer alignment.
         */
        send_and_check(
            make_descriptor(
                64'h0000_0000_0010_0001,
                32'd64,
                32'h0000_0001,
                64'd4
            ),
            1'b0,
            6'b001000
        );

        /*
         * Unsupported address bits above 40 bits.
         */
        send_and_check(
            make_descriptor(
                64'h0000_0100_0010_0000,
                32'd64,
                32'h0000_0001,
                64'd5
            ),
            1'b0,
            6'b010000
        );

        /*
         * Reserved CONTROL bit.
         */
        send_and_check(
            make_descriptor(
                64'h0000_0000_0010_0000,
                32'd64,
                32'h0000_0009,
                64'd6
            ),
            1'b0,
            6'b100000
        );

        $display("DESCRIPTOR VALIDATION ERRORS: PASS");

        /*
         * Backpressure stability.
         */
        parsed_ready = 1'b0;

        @(negedge clk);

        desc_data =
            make_descriptor(
                64'h0000_0000_0020_0000,
                32'd128,
                32'h0000_0003,
                64'hCAFE_BABE_1234_5678
            );

        desc_valid = 1'b1;

        @(posedge clk);
        #1;

        if (!parsed_valid || !descriptor_ok) begin
            $display("FAIL: stalled descriptor not captured");
            $fatal;
        end

        desc_valid = 1'b0;

        repeat (5) begin

            @(posedge clk);
            #1;

            if (!parsed_valid ||
                buffer_addr !==
                    64'h0000_0000_0020_0000 ||
                length !== 32'd128 ||
                cookie !==
                    64'hCAFE_BABE_1234_5678) begin

                $display(
                    "FAIL: parser output changed under backpressure"
                );

                $fatal;
            end
        end

        parsed_ready = 1'b1;

        @(posedge clk);
        @(posedge clk);

        $display("PARSER BACKPRESSURE STABILITY: PASS");

        $display("");
        $display("============================================");
        $display(" DMA DESCRIPTOR PARSER: PASS");
        $display(" field extraction             : PASS");
        $display(" ownership validation         : PASS");
        $display(" length validation            : PASS");
        $display(" address validation           : PASS");
        $display(" reserved-field validation    : PASS");
        $display(" output backpressure stability: PASS");
        $display("============================================");

        $finish;
    end

    initial begin
        #1_000_000;
        $display("FAIL: parser simulation timeout");
        $fatal;
    end

endmodule
