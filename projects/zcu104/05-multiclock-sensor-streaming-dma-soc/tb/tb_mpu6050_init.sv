`timescale 1ns/1ps

module tb_mpu6050_init;

    reg clk = 1'b0;
    reg aresetn = 1'b0;

    always #500 clk = ~clk;   // 1 MHz simulation clock

    tri1 scl;
    tri1 sda;

    reg slave_sda_low = 1'b0;
    assign sda = slave_sda_low ? 1'b0 : 1'bz;

    wire [7:0] whoami_data;
    wire       whoami_valid;
    wire       whoami_match;

    wire [7:0] pwr_mgmt_data;
    wire       pwr_mgmt_valid;
    wire       wake_verified;

    wire ack_error;
    wire busy;
    wire transaction_done;
    wire scl_sample;
    wire sda_sample;

    reg [7:0] received_byte;

    mpu6050_i2c_master #(
        .CLK_FREQ_HZ (1000000),
        .I2C_FREQ_HZ (100000)
    ) dut (
        .clk              (clk),
        .aresetn          (aresetn),

        .mpu6050_scl      (scl),
        .mpu6050_sda      (sda),

        .whoami_data      (whoami_data),
        .whoami_valid     (whoami_valid),
        .whoami_match     (whoami_match),

        .ack_error        (ack_error),
        .busy             (busy),
        .transaction_done (transaction_done),

        .pwr_mgmt_data    (pwr_mgmt_data),
        .pwr_mgmt_valid   (pwr_mgmt_valid),
        .wake_verified    (wake_verified),

        .scl_sample       (scl_sample),
        .sda_sample       (sda_sample)
    );

    task automatic wait_start;
        begin
            @(negedge sda);
            while (scl !== 1'b1)
                @(negedge sda);
        end
    endtask

    task automatic wait_stop;
        begin
            @(posedge sda);
            while (scl !== 1'b1)
                @(posedge sda);
        end
    endtask

    task automatic receive_byte(output reg [7:0] value);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                @(posedge scl);
                value[i] = sda;
                @(negedge scl);
            end
        end
    endtask

    task automatic slave_ack;
        begin
            slave_sda_low = 1'b1;
            @(posedge scl);
            @(negedge scl);
            slave_sda_low = 1'b0;
        end
    endtask

    task automatic send_byte(input [7:0] value);
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                slave_sda_low = ~value[i];
                @(posedge scl);
                @(negedge scl);
            end
            slave_sda_low = 1'b0;
        end
    endtask

    task automatic expect_byte(input [7:0] expected);
        begin
            receive_byte(received_byte);

            if (received_byte !== expected) begin
                $display("FAIL: expected %02h, received %02h",
                         expected, received_byte);
                $fatal;
            end

            slave_ack;
        end
    endtask

    initial begin

        repeat (10) @(posedge clk);
        aresetn = 1'b1;

        /*
         * 1. Wake write:
         * D0 -> 6B -> 00
         */
        wait_start;
        expect_byte(8'hD0);
        expect_byte(8'h6B);
        expect_byte(8'h00);
        wait_stop;

        $display("WAKE WRITE: PASS   PWR_MGMT_1 <= 00");

        /*
         * 2. Read PWR_MGMT_1 back.
         */
        wait_start;
        expect_byte(8'hD0);
        expect_byte(8'h6B);

        wait_start;
        expect_byte(8'hD1);

        send_byte(8'h00);
        wait_stop;

        wait (pwr_mgmt_valid == 1'b1);

        if (!wake_verified || pwr_mgmt_data !== 8'h00) begin
            $display("FAIL: PWR_MGMT_1 readback = %02h",
                     pwr_mgmt_data);
            $fatal;
        end

        $display("WAKE READBACK: PASS   PWR_MGMT_1 = %02h",
                 pwr_mgmt_data);

        /*
         * 3. WHO_AM_I regression after wake.
         */
        wait_start;
        expect_byte(8'hD0);
        expect_byte(8'h75);

        wait_start;
        expect_byte(8'hD1);

        send_byte(8'h68);
        wait_stop;

        wait (whoami_valid == 1'b1);

        if (!whoami_match || whoami_data !== 8'h68) begin
            $display("FAIL: WHO_AM_I = %02h", whoami_data);
            $fatal;
        end

        if (ack_error) begin
            $display("FAIL: ACK error detected");
            $fatal;
        end

        $display("");
        $display("==========================================");
        $display(" MPU6050 INITIALIZATION SEQUENCE: PASS");
        $display(" Wake write       : 6B <= 00");
        $display(" Wake readback    : 00");
        $display(" WHO_AM_I         : 68");
        $display(" ACK integrity    : PASS");
        $display("==========================================");

        $finish;
    end

    initial begin
        #300000000;
        $display("FAIL: simulation timeout");
        $fatal;
    end

endmodule
