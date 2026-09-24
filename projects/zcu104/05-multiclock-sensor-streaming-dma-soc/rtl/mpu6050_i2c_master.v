/*
 * Frank Ouma
 * FPGA / SoC / Digital Hardware Engineering
 * Email: frankotieno254@gmail.com
 * Contact: +254725582132
 * Copyright (c) 2026 Frank Ouma. All rights reserved.
 *
 * Project 05 - Multi-Clock Sensor Streaming & DMA SoC
 *
 * MPU6050 I2C hardware bring-up master.
 *
 * Initial function:
 *   Read MPU6050 WHO_AM_I register 0x75.
 *
 * Expected response:
 *   0x68
 *
 * Bus:
 *   25 MHz PL clock
 *   100 kHz I2C
 *
 * SCL and SDA are open-drain:
 *   logic 0 = actively drive low
 *   logic 1 = release line to external pull-up
 */

module mpu6050_i2c_master #(
    parameter integer CLK_FREQ_HZ = 25000000,
    parameter integer I2C_FREQ_HZ = 100000
)(
    input  wire       clk,
    input  wire       aresetn,

    inout  wire       mpu6050_scl,
    inout  wire       mpu6050_sda,

    output reg  [7:0] whoami_data,
    output reg        whoami_valid,
    output wire       whoami_match,

    output reg        ack_error,
    output reg        busy,
    output reg        transaction_done,

    output reg  [7:0] pwr_mgmt_data,
    output reg        pwr_mgmt_valid,
    output wire       wake_verified,

    // 14-byte motion frame, first byte in bits [111:104].
    output reg [111:0] motion_frame,
    output reg         motion_valid,

    output wire       scl_sample,
    output wire       sda_sample
);

    localparam integer HALF_PERIOD_CYCLES =
        CLK_FREQ_HZ / (I2C_FREQ_HZ * 2);

    /* Poll WHO_AM_I approximately every 100 ms. */
    localparam integer POLL_CYCLES =
        CLK_FREQ_HZ / 10;

    /*
     * MPU6050 default 7-bit address = 0x68
     *
     * Write address byte = 0xD0
     * Read  address byte = 0xD1
     */
    localparam [7:0] MPU_ADDR_WRITE = 8'hD0;
    localparam [7:0] MPU_ADDR_READ  = 8'hD1;

    localparam [7:0] MOTION_BASE_REG = 8'h3B;
    localparam [7:0] WHO_AM_I_REG   = 8'h75;
    localparam [7:0] PWR_MGMT_1_REG = 8'h6B;
    localparam [7:0] WAKE_DATA       = 8'h00;

    /* Allow 10 ms after the wake write before readback. */
    localparam integer INIT_DELAY_CYCLES =
        CLK_FREQ_HZ / 100;

    localparam [1:0]
        OP_WAKE_WRITE = 2'd0,
        OP_PWR_READ   = 2'd1,
        OP_WHOAMI     = 2'd2,
        OP_MOTION     = 2'd3;

    localparam [4:0]
        ST_IDLE          = 5'd0,
        ST_START_A       = 5'd1,
        ST_START_B       = 5'd2,
        ST_START_C       = 5'd3,
        ST_SEND_SETUP    = 5'd4,
        ST_SEND_HIGH     = 5'd5,
        ST_SEND_LOW      = 5'd6,
        ST_ACK_SETUP     = 5'd7,
        ST_ACK_HIGH      = 5'd8,
        ST_ACK_LOW       = 5'd9,
        ST_RESTART_A     = 5'd10,
        ST_RESTART_B     = 5'd11,
        ST_RESTART_C     = 5'd12,
        ST_READ_SETUP    = 5'd13,
        ST_READ_HIGH     = 5'd14,
        ST_NACK_SETUP    = 5'd15,
        ST_NACK_HIGH     = 5'd16,
        ST_NACK_LOW      = 5'd17,
        ST_STOP_A        = 5'd18,
        ST_STOP_B        = 5'd19,
        ST_STOP_C        = 5'd20,
        ST_STOP_D        = 5'd21,
        ST_RX_ACK_SETUP  = 5'd22,
        ST_RX_ACK_HIGH   = 5'd23,
        ST_RX_ACK_LOW    = 5'd24;

    localparam [1:0]
        TX_ADDR_WRITE = 2'd0,
        TX_REGISTER   = 2'd1,
        TX_ADDR_READ  = 2'd2,
        TX_WRITE_DATA = 2'd3;

    reg [4:0] state;

    reg [31:0] half_count;
    reg [31:0] poll_count;

    reg scl_drive_low;
    reg sda_drive_low;

    reg [7:0] tx_byte;
    reg [7:0] rx_byte;

    reg [2:0] bit_index;
    reg [1:0] tx_stage;
    reg [1:0] operation;

    reg [3:0] rx_index;
    reg [111:0] motion_shift;

    reg ack_sample;
    reg abort_transaction;

    wire scl_in;
    wire sda_in;

    /*
     * Open-drain implementation.
     * Never actively drive logic HIGH.
     */
    /*
     * Explicit FPGA bidirectional buffers.
     *
     * I = 0 because I2C devices only actively drive LOW.
     * T = 0 -> drive LOW.
     * T = 1 -> release line to external pull-up.
     */
    IOBUF mpu6050_scl_iobuf (
        .I  (1'b0),
        .T  (~scl_drive_low),
        .O  (scl_in),
        .IO (mpu6050_scl)
    );

    IOBUF mpu6050_sda_iobuf (
        .I  (1'b0),
        .T  (~sda_drive_low),
        .O  (sda_in),
        .IO (mpu6050_sda)
    );

    assign scl_sample = scl_in;
    assign sda_sample = sda_in;

    assign whoami_match =
        whoami_valid && (whoami_data == 8'h68);

    assign wake_verified =
        pwr_mgmt_valid && (pwr_mgmt_data == 8'h00);

    wire [31:0] idle_wait_cycles;

    assign idle_wait_cycles =
        ((operation == OP_PWR_READ) ||
         (operation == OP_MOTION)) ?
        INIT_DELAY_CYCLES : POLL_CYCLES;

    always @(posedge clk) begin

        if (!aresetn) begin

            state               <= ST_IDLE;

            half_count          <= 32'd0;
            poll_count          <= 32'd0;

            scl_drive_low       <= 1'b0;
            sda_drive_low       <= 1'b0;

            tx_byte             <= 8'd0;
            rx_byte             <= 8'd0;

            bit_index           <= 3'd7;
            tx_stage            <= TX_ADDR_WRITE;
            operation           <= OP_WAKE_WRITE;
            rx_index            <= 4'd0;
            motion_shift        <= 112'd0;
            motion_frame        <= 112'd0;
            motion_valid        <= 1'b0;

            ack_sample          <= 1'b0;
            abort_transaction   <= 1'b0;

            whoami_data         <= 8'd0;
            whoami_valid        <= 1'b0;

            pwr_mgmt_data       <= 8'd0;
            pwr_mgmt_valid      <= 1'b0;

            ack_error           <= 1'b0;
            busy                <= 1'b0;
            transaction_done    <= 1'b0;

        end
        else begin

            transaction_done <= 1'b0;
            motion_valid     <= 1'b0;

            /*
             * ------------------------------------------------
             * Idle / poll interval
             * ------------------------------------------------
             */
            if (state == ST_IDLE) begin

                half_count <= 32'd0;

                scl_drive_low <= 1'b0;
                sda_drive_low <= 1'b0;

                busy <= 1'b0;

                if (poll_count >= (idle_wait_cycles - 1)) begin

                    poll_count <= 32'd0;

                    busy              <= 1'b1;
                    ack_error         <= 1'b0;
                    abort_transaction <= 1'b0;
                    if (operation == OP_WHOAMI)
                        whoami_valid <= 1'b0;

                    if (operation == OP_PWR_READ)
                        pwr_mgmt_valid <= 1'b0;

                    tx_byte   <= MPU_ADDR_WRITE;
                    tx_stage  <= TX_ADDR_WRITE;
                    bit_index <= 3'd7;

                    state <= ST_START_A;

                end
                else begin
                    poll_count <= poll_count + 1'b1;
                end
            end

            /*
             * ------------------------------------------------
             * Active I2C transaction
             * ------------------------------------------------
             */
            else begin

                if (half_count >=
                    (HALF_PERIOD_CYCLES - 1)) begin

                    half_count <= 32'd0;

                    case (state)

                        /*
                         * START:
                         *
                         * SDA falls while SCL is HIGH.
                         */
                        ST_START_A: begin
                            scl_drive_low <= 1'b0;
                            sda_drive_low <= 1'b1;
                            state <= ST_START_B;
                        end

                        ST_START_B: begin
                            scl_drive_low <= 1'b1;
                            state <= ST_START_C;
                        end

                        ST_START_C: begin
                            bit_index <= 3'd7;
                            state <= ST_SEND_SETUP;
                        end

                        /*
                         * ------------------------------------------------
                         * Transmit one byte MSB first
                         * ------------------------------------------------
                         */
                        ST_SEND_SETUP: begin

                            scl_drive_low <= 1'b1;

                            if (tx_byte[bit_index] == 1'b0)
                                sda_drive_low <= 1'b1;
                            else
                                sda_drive_low <= 1'b0;

                            state <= ST_SEND_HIGH;
                        end

                        ST_SEND_HIGH: begin
                            scl_drive_low <= 1'b0;
                            state <= ST_SEND_LOW;
                        end

                        ST_SEND_LOW: begin

                            scl_drive_low <= 1'b1;

                            if (bit_index == 3'd0) begin

                                sda_drive_low <= 1'b0;
                                state <= ST_ACK_SETUP;

                            end
                            else begin

                                bit_index <= bit_index - 1'b1;
                                state <= ST_SEND_SETUP;
                            end
                        end

                        /*
                         * ------------------------------------------------
                         * Slave ACK
                         * ------------------------------------------------
                         */
                        ST_ACK_SETUP: begin

                            sda_drive_low <= 1'b0;
                            scl_drive_low <= 1'b0;

                            state <= ST_ACK_HIGH;
                        end

                        ST_ACK_HIGH: begin

                            ack_sample <= sda_in;

                            scl_drive_low <= 1'b1;

                            state <= ST_ACK_LOW;
                        end

                        ST_ACK_LOW: begin

                            if (ack_sample != 1'b0) begin

                                ack_error         <= 1'b1;
                                abort_transaction <= 1'b1;

                                state <= ST_STOP_A;

                            end
                            else begin

                                case (tx_stage)

                                    TX_ADDR_WRITE: begin

                                        if (operation == OP_WHOAMI)
                                            tx_byte <= WHO_AM_I_REG;
                                        else if (operation == OP_MOTION)
                                            tx_byte <= MOTION_BASE_REG;
                                        else
                                            tx_byte <= PWR_MGMT_1_REG;

                                        tx_stage <= TX_REGISTER;
                                        bit_index <= 3'd7;
                                        state <= ST_SEND_SETUP;
                                    end

                                    TX_REGISTER: begin

                                        if (operation == OP_WAKE_WRITE) begin

                                            tx_byte   <= WAKE_DATA;
                                            tx_stage  <= TX_WRITE_DATA;
                                            bit_index <= 3'd7;
                                            state     <= ST_SEND_SETUP;

                                        end
                                        else begin

                                            tx_stage <= TX_ADDR_READ;
                                            state    <= ST_RESTART_A;
                                        end
                                    end

                                    TX_WRITE_DATA: begin

                                        state <= ST_STOP_A;
                                    end

                                    TX_ADDR_READ: begin

                                        rx_byte   <= 8'd0;
                                        bit_index <= 3'd7;

                                        if (operation == OP_MOTION) begin
                                            rx_index     <= 4'd0;
                                            motion_shift <= 112'd0;
                                        end

                                        state <= ST_READ_SETUP;
                                    end

                                    default: begin

                                        abort_transaction <= 1'b1;
                                        state <= ST_STOP_A;
                                    end
                                endcase
                            end
                        end

                        /*
                         * ------------------------------------------------
                         * Repeated START
                         * ------------------------------------------------
                         */
                        ST_RESTART_A: begin

                            sda_drive_low <= 1'b0;
                            scl_drive_low <= 1'b0;

                            state <= ST_RESTART_B;
                        end

                        ST_RESTART_B: begin

                            /*
                             * SDA falls while SCL remains HIGH.
                             */
                            sda_drive_low <= 1'b1;

                            state <= ST_RESTART_C;
                        end

                        ST_RESTART_C: begin

                            scl_drive_low <= 1'b1;

                            tx_byte   <= MPU_ADDR_READ;
                            bit_index <= 3'd7;

                            state <= ST_SEND_SETUP;
                        end

                        /*
                         * ------------------------------------------------
                         * Read one byte MSB first
                         * ------------------------------------------------
                         */
                        ST_READ_SETUP: begin

                            sda_drive_low <= 1'b0;
                            scl_drive_low <= 1'b0;

                            state <= ST_READ_HIGH;
                        end

                        ST_READ_HIGH: begin

                            rx_byte[bit_index] <= sda_in;

                            scl_drive_low <= 1'b1;

                            if (bit_index == 3'd0) begin

                                if ((operation == OP_MOTION) &&
                                    (rx_index < 4'd13))
                                    state <= ST_RX_ACK_SETUP;
                                else
                                    state <= ST_NACK_SETUP;

                            end
                            else begin

                                bit_index <= bit_index - 1'b1;
                                state <= ST_READ_SETUP;
                            end
                        end

                        /*
                         * ------------------------------------------------
                         * Master NACK after final read byte
                         * ------------------------------------------------
                         */
                        // Store each received byte, then ACK so that
                        // the MPU6050 sends the next register byte.
                        ST_RX_ACK_SETUP: begin

                            motion_shift[111 - (rx_index * 8) -: 8]
                                <= rx_byte;

                            scl_drive_low <= 1'b1;
                            sda_drive_low <= 1'b1;
                            state <= ST_RX_ACK_HIGH;
                        end

                        ST_RX_ACK_HIGH: begin

                            scl_drive_low <= 1'b0;
                            state <= ST_RX_ACK_LOW;
                        end

                        ST_RX_ACK_LOW: begin

                            scl_drive_low <= 1'b1;
                            sda_drive_low <= 1'b0;

                            rx_index  <= rx_index + 1'b1;
                            bit_index <= 3'd7;
                            rx_byte   <= 8'd0;

                            state <= ST_READ_SETUP;
                        end

                        // NACK the final byte to end the burst read.
                        ST_NACK_SETUP: begin

                            if (operation == OP_MOTION)
                                motion_shift[111 - (rx_index * 8) -: 8]
                                    <= rx_byte;

                            sda_drive_low <= 1'b0;
                            scl_drive_low <= 1'b0;

                            state <= ST_NACK_HIGH;
                        end

                        ST_NACK_HIGH: begin

                            scl_drive_low <= 1'b1;

                            state <= ST_NACK_LOW;
                        end

                        ST_NACK_LOW: begin
                            state <= ST_STOP_A;
                        end

                        /*
                         * ------------------------------------------------
                         * STOP:
                         *
                         * SDA rises while SCL is HIGH.
                         * ------------------------------------------------
                         */
                        ST_STOP_A: begin

                            scl_drive_low <= 1'b1;
                            sda_drive_low <= 1'b1;

                            state <= ST_STOP_B;
                        end

                        ST_STOP_B: begin

                            scl_drive_low <= 1'b0;

                            state <= ST_STOP_C;
                        end

                        ST_STOP_C: begin

                            sda_drive_low <= 1'b0;

                            state <= ST_STOP_D;
                        end

                        ST_STOP_D: begin

                            busy <= 1'b0;

                            transaction_done <= 1'b1;

                            if (!abort_transaction) begin

                                case (operation)

                                    OP_WAKE_WRITE: begin
                                        operation <= OP_PWR_READ;
                                    end

                                    OP_PWR_READ: begin

                                        pwr_mgmt_data  <= rx_byte;
                                        pwr_mgmt_valid <= 1'b1;

                                        if (rx_byte == 8'h00)
                                            operation <= OP_WHOAMI;
                                        else
                                            operation <= OP_WAKE_WRITE;
                                    end

                                    OP_WHOAMI: begin

                                        whoami_data  <= rx_byte;
                                        whoami_valid <= 1'b1;

                                        if (rx_byte == 8'h68)
                                            operation <= OP_MOTION;
                                    end

                                    OP_MOTION: begin

                                        motion_frame <= motion_shift;
                                        motion_valid <= 1'b1;
                                    end

                                    default:
                                        operation <= OP_WAKE_WRITE;

                                endcase
                            end
                            else begin

                                if (operation == OP_WHOAMI)
                                    whoami_valid <= 1'b0;

                                if (operation == OP_PWR_READ)
                                    pwr_mgmt_valid <= 1'b0;
                            end

                            poll_count <= 32'd0;
                            state <= ST_IDLE;
                        end

                        default: begin

                            scl_drive_low <= 1'b0;
                            sda_drive_low <= 1'b0;

                            busy <= 1'b0;

                            state <= ST_IDLE;
                        end

                    endcase
                end
                else begin

                    half_count <= half_count + 1'b1;
                end
            end
        end
    end

endmodule
