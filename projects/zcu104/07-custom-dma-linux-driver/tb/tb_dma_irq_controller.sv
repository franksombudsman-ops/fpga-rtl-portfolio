`timescale 1ns/1ps

module tb_dma_irq_controller;

    logic clk = 1'b0;
    always #5 clk = ~clk;

    logic aresetn;

    logic tx_completion_event;
    logic rx_completion_event;
    logic tx_error_event;
    logic rx_error_event;

    logic [3:0] irq_enable;
    logic [3:0] irq_clear;

    logic [3:0] irq_status;
    logic       irq;

    dma_irq_controller dut (
        .clk                 (clk),
        .aresetn             (aresetn),

        .tx_completion_event (tx_completion_event),
        .rx_completion_event (rx_completion_event),
        .tx_error_event      (tx_error_event),
        .rx_error_event      (rx_error_event),

        .irq_enable          (irq_enable),
        .irq_clear           (irq_clear),

        .irq_status          (irq_status),
        .irq                 (irq)
    );

    task automatic clear_inputs;

        begin

            tx_completion_event = 1'b0;
            rx_completion_event = 1'b0;
            tx_error_event      = 1'b0;
            rx_error_event      = 1'b0;

            irq_clear =
                4'b0000;

        end

    endtask

    task automatic pulse_event(
        input integer bit_number
    );

        begin

            @(negedge clk);

            case (bit_number)

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

                default:
                    $fatal;

            endcase

            @(posedge clk);
            @(negedge clk);

            clear_inputs();

        end

    endtask

    initial begin

        aresetn =
            1'b0;

        irq_enable =
            4'b0000;

        clear_inputs();

        repeat (5)
            @(posedge clk);

        aresetn =
            1'b1;

        repeat (2)
            @(posedge clk);

        /*
         * --------------------------------------------------------
         * RESET STATE
         * --------------------------------------------------------
         */

        if (irq_status !== 4'b0000 ||
            irq !== 1'b0) begin

            $display(
                "FAIL: IRQ reset state"
            );

            $fatal;

        end

        $display(
            "IRQ RESET STATE: PASS"
        );

        /*
         * --------------------------------------------------------
         * MASKED EVENT MUST STILL LATCH
         * --------------------------------------------------------
         */

        pulse_event(0);

        #1;

        if (irq_status !== 4'b0001) begin

            $display(
                "FAIL: masked TX completion was not latched"
            );

            $fatal;

        end

        if (irq !== 1'b0) begin

            $display(
                "FAIL: masked interrupt asserted IRQ"
            );

            $fatal;

        end

        $display(
            "MASKED EVENT LATCHING: PASS"
        );

        /*
         * Enabling a cause that is already pending must immediately
         * assert the external interrupt.
         */

        irq_enable =
            4'b0001;

        #1;

        if (!irq) begin

            $display(
                "FAIL: pending enabled interrupt did not assert IRQ"
            );

            $fatal;

        end

        $display(
            "PENDING EVENT ENABLE: PASS"
        );

        /*
         * --------------------------------------------------------
         * SELECTIVE W1C
         * --------------------------------------------------------
         */

        pulse_event(1);
        pulse_event(2);
        pulse_event(3);

        if (irq_status !== 4'b1111) begin

            $display(
                "FAIL: multiple interrupt causes not latched status=%b",
                irq_status
            );

            $fatal;

        end

        /*
         * Clear RX completion and TX error only.
         *
         * bits 1 and 2.
         */
        @(negedge clk);

        irq_clear =
            4'b0110;

        @(posedge clk);
        @(negedge clk);

        irq_clear =
            4'b0000;

        #1;

        if (irq_status !== 4'b1001) begin

            $display(
                "FAIL: selective W1C status=%b expected=1001",
                irq_status
            );

            $fatal;

        end

        $display(
            "SELECTIVE W1C CLEAR: PASS"
        );

        /*
         * --------------------------------------------------------
         * SET-DOMINANT CLEAR COLLISION
         * --------------------------------------------------------
         *
         * Software clears TX completion on exactly the same cycle
         * a new TX completion event arrives.
         *
         * The new event MUST remain pending.
         */

        @(negedge clk);

        irq_clear =
            4'b0001;

        tx_completion_event =
            1'b1;

        @(posedge clk);
        @(negedge clk);

        clear_inputs();

        #1;

        if (!irq_status[0]) begin

            $display(
                "FAIL: new TX completion lost during W1C collision"
            );

            $fatal;

        end

        $display(
            "SET-DOMINANT W1C COLLISION: PASS"
        );

        /*
         * --------------------------------------------------------
         * MASK BEHAVIOR
         * --------------------------------------------------------
         */

        irq_enable =
            4'b0000;

        #1;

        if (irq) begin

            $display(
                "FAIL: IRQ remained asserted with all causes masked"
            );

            $fatal;

        end

        irq_enable =
            4'b1000;

        #1;

        /*
         * RX error is still pending from status=1001.
         */
        if (!irq) begin

            $display(
                "FAIL: RX error pending but enabled IRQ not asserted"
            );

            $fatal;

        end

        $display(
            "IRQ ENABLE MASKING: PASS"
        );

        /*
         * --------------------------------------------------------
         * CLEAR EVERYTHING
         * --------------------------------------------------------
         */

        @(negedge clk);

        irq_clear =
            4'b1111;

        @(posedge clk);
        @(negedge clk);

        irq_clear =
            4'b0000;

        #1;

        if (irq_status !== 4'b0000 ||
            irq) begin

            $display(
                "FAIL: final interrupt clear"
            );

            $fatal;

        end

        $display(
            "FULL IRQ ACKNOWLEDGEMENT: PASS"
        );

        /*
         * --------------------------------------------------------
         * EACH SOURCE INDEPENDENTLY
         * --------------------------------------------------------
         */

        irq_enable =
            4'b1111;

        pulse_event(0);

        if (irq_status !== 4'b0001 ||
            !irq)
            $fatal;

        @(negedge clk);
        irq_clear = 4'b0001;
        @(posedge clk);
        @(negedge clk);
        irq_clear = 0;

        pulse_event(1);

        if (irq_status !== 4'b0010 ||
            !irq)
            $fatal;

        @(negedge clk);
        irq_clear = 4'b0010;
        @(posedge clk);
        @(negedge clk);
        irq_clear = 0;

        pulse_event(2);

        if (irq_status !== 4'b0100 ||
            !irq)
            $fatal;

        @(negedge clk);
        irq_clear = 4'b0100;
        @(posedge clk);
        @(negedge clk);
        irq_clear = 0;

        pulse_event(3);

        if (irq_status !== 4'b1000 ||
            !irq)
            $fatal;

        $display(
            "ALL FOUR IRQ SOURCES: PASS"
        );

        $display("");
        $display("============================================");
        $display(" DMA IRQ CONTROLLER: PASS");
        $display(" TX completion latching       : PASS");
        $display(" RX completion latching       : PASS");
        $display(" TX error latching            : PASS");
        $display(" RX error latching            : PASS");
        $display(" masked-event preservation    : PASS");
        $display(" IRQ enable masking           : PASS");
        $display(" selective W1C                : PASS");
        $display(" set-dominant clear collision : PASS");
        $display(" explicit acknowledgement     : PASS");
        $display("============================================");

        $finish;

    end

    initial begin

        #1_000_000;

        $display(
            "FAIL: IRQ controller timeout"
        );

        $fatal;

    end

endmodule
