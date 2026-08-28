`timescale 1ns/1ps

module soc_control_axi_peripheral #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 32
)(
    input  logic                      s_axi_aclk,
    input  logic                      s_axi_aresetn,

    // AXI4-Lite write address channel
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    // AXI4-Lite write data channel
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [3:0]                s_axi_wstrb,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,

    // AXI4-Lite write response channel
    output logic [1:0]                s_axi_bresp,
    output logic                      s_axi_bvalid,
    input  logic                      s_axi_bready,

    // AXI4-Lite read address channel
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    // AXI4-Lite read data channel
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready,

    // Configuration outputs to control engine
    output logic                      engine_enable,
    output logic [11:0]               threshold_high,
    output logic [11:0]               threshold_low,
    output logic [7:0]                pwm_duty,

    // Live hardware status inputs
    input  logic                      control_request,
    input  logic                      actuator_enable,
    input  logic [1:0]                state_code,
    input  logic                      overrun,
    input  logic [11:0]               sensor_raw,
    input  logic [11:0]               sensor_filtered,

    // Interrupt interface
    input  logic                      event_pulse,
    output logic                      irq_out
);

    // ------------------------------------------------------------
    // Register offsets
    // ------------------------------------------------------------

    localparam logic [5:0] ADDR_CONTROL         = 6'h00;
    localparam logic [5:0] ADDR_STATUS          = 6'h04;
    localparam logic [5:0] ADDR_THRESHOLD_HIGH  = 6'h08;
    localparam logic [5:0] ADDR_THRESHOLD_LOW   = 6'h0C;
    localparam logic [5:0] ADDR_PWM_DUTY        = 6'h10;
    localparam logic [5:0] ADDR_SENSOR_RAW      = 6'h14;
    localparam logic [5:0] ADDR_SENSOR_FILTERED = 6'h18;
    localparam logic [5:0] ADDR_VERSION         = 6'h1C;
    localparam logic [5:0] ADDR_IRQ_ENABLE      = 6'h20;
    localparam logic [5:0] ADDR_IRQ_STATUS      = 6'h24;
    localparam logic [5:0] ADDR_IRQ_CLEAR       = 6'h28;
    localparam logic [5:0] ADDR_EVENT_COUNT     = 6'h2C;

    localparam logic [31:0] VERSION_VALUE       = 32'h0001_0000;

    // ------------------------------------------------------------
    // AXI write-channel holding registers
    // AW and W channels are independent in AXI4-Lite.
    // ------------------------------------------------------------

    logic                      aw_pending;
    logic [AXI_ADDR_WIDTH-1:0] awaddr_reg;

    logic                      w_pending;
    logic [31:0]               wdata_reg;
    logic [3:0]                wstrb_reg;

    logic [31:0] merged_write;

    logic        irq_enable;
    logic        irq_clear;
    logic        irq_pending;
    logic [31:0] event_count;

    irq_controller u_irq_controller (
        .clk         (s_axi_aclk),
        .rst_n       (s_axi_aresetn),
        .event_pulse (event_pulse),
        .irq_enable  (irq_enable),
        .irq_clear   (irq_clear),
        .irq_pending (irq_pending),
        .irq_out     (irq_out),
        .event_count (event_count)
    );

    // ------------------------------------------------------------
    // Byte-write helper
    // ------------------------------------------------------------

    function automatic logic [31:0] apply_wstrb(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  strb
    );
        logic [31:0] result;
        int i;
        begin
            result = old_value;

            for (i = 0; i < 4; i = i + 1) begin
                if (strb[i])
                    result[i*8 +: 8] = new_value[i*8 +: 8];
            end

            return result;
        end
    endfunction

    // ------------------------------------------------------------
    // AXI ready signals
    // One outstanding write transaction at a time.
    // ------------------------------------------------------------

    assign s_axi_awready = !aw_pending && !s_axi_bvalid;
    assign s_axi_wready  = !w_pending  && !s_axi_bvalid;

    assign s_axi_bresp   = 2'b00; // OKAY

    // ------------------------------------------------------------
    // Write transaction handling
    // ------------------------------------------------------------

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            aw_pending   <= 1'b0;
            awaddr_reg   <= '0;

            w_pending    <= 1'b0;
            wdata_reg    <= '0;
            wstrb_reg    <= '0;

            s_axi_bvalid <= 1'b0;

            engine_enable <= 1'b0;
            threshold_high <= 12'hC00;
            threshold_low  <= 12'hB80;
            pwm_duty       <= 8'h99;

            irq_enable     <= 1'b0;
            irq_clear      <= 1'b0;
        end
        else begin

            // IRQ_CLEAR is write-one-to-clear and pulses for one clock.
            irq_clear <= 1'b0;

            // Capture write address independently.
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_reg <= s_axi_awaddr;
                aw_pending <= 1'b1;
            end

            // Capture write data independently.
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
                w_pending <= 1'b1;
            end

            // Perform register write when both channels have arrived.
            if (aw_pending && w_pending && !s_axi_bvalid) begin

                case (awaddr_reg[5:0])

                    ADDR_CONTROL: begin
                        merged_write =
                            apply_wstrb(
                                {31'd0, engine_enable},
                                wdata_reg,
                                wstrb_reg
                            );

                        engine_enable <= merged_write[0];
                    end

                    ADDR_THRESHOLD_HIGH: begin
                        merged_write =
                            apply_wstrb(
                                {20'd0, threshold_high},
                                wdata_reg,
                                wstrb_reg
                            );

                        threshold_high <= merged_write[11:0];
                    end

                    ADDR_THRESHOLD_LOW: begin
                        merged_write =
                            apply_wstrb(
                                {20'd0, threshold_low},
                                wdata_reg,
                                wstrb_reg
                            );

                        threshold_low <= merged_write[11:0];
                    end

                    ADDR_PWM_DUTY: begin
                        merged_write =
                            apply_wstrb(
                                {24'd0, pwm_duty},
                                wdata_reg,
                                wstrb_reg
                            );

                        pwm_duty <= merged_write[7:0];
                    end

                    ADDR_IRQ_ENABLE: begin
                        merged_write =
                            apply_wstrb(
                                {31'd0, irq_enable},
                                wdata_reg,
                                wstrb_reg
                            );

                        irq_enable <= merged_write[0];
                    end

                    ADDR_IRQ_CLEAR: begin
                        if (wstrb_reg[0] && wdata_reg[0])
                            irq_clear <= 1'b1;
                    end

                    default: begin
                        // Writes to RO or undefined addresses are ignored.
                    end

                endcase

                aw_pending   <= 1'b0;
                w_pending    <= 1'b0;
                s_axi_bvalid <= 1'b1;
            end

            // Master accepts write response.
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end

    // ------------------------------------------------------------
    // Read channel
    // ------------------------------------------------------------

    assign s_axi_arready = !s_axi_rvalid;
    assign s_axi_rresp   = 2'b00; // OKAY

    always_ff @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
        end
        else begin

            if (s_axi_arvalid && s_axi_arready) begin

                case (s_axi_araddr[5:0])

                    ADDR_CONTROL:
                        s_axi_rdata <=
                            {31'd0, engine_enable};

                    ADDR_STATUS:
                        s_axi_rdata <=
                            {
                                27'd0,
                                overrun,
                                state_code,
                                actuator_enable,
                                control_request
                            };

                    ADDR_THRESHOLD_HIGH:
                        s_axi_rdata <=
                            {20'd0, threshold_high};

                    ADDR_THRESHOLD_LOW:
                        s_axi_rdata <=
                            {20'd0, threshold_low};

                    ADDR_PWM_DUTY:
                        s_axi_rdata <=
                            {24'd0, pwm_duty};

                    ADDR_SENSOR_RAW:
                        s_axi_rdata <=
                            {20'd0, sensor_raw};

                    ADDR_SENSOR_FILTERED:
                        s_axi_rdata <=
                            {20'd0, sensor_filtered};

                    ADDR_VERSION:
                        s_axi_rdata <= VERSION_VALUE;

                    ADDR_IRQ_ENABLE:
                        s_axi_rdata <= {31'd0, irq_enable};

                    ADDR_IRQ_STATUS:
                        s_axi_rdata <= {31'd0, irq_pending};

                    ADDR_IRQ_CLEAR:
                        s_axi_rdata <= 32'd0;

                    ADDR_EVENT_COUNT:
                        s_axi_rdata <= event_count;

                    default:
                        s_axi_rdata <= 32'd0;

                endcase

                s_axi_rvalid <= 1'b1;
            end
            else if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule
