`timescale 1ns/1ps

module pwm_generator #(
    parameter int PWM_DIVIDER = 25
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       enable,
    input  logic [7:0] duty,

    output logic       pwm_out
);

    localparam int DIV_WIDTH =
        (PWM_DIVIDER <= 1) ? 1 : $clog2(PWM_DIVIDER);

    logic [DIV_WIDTH-1:0] divider_count;
    logic [7:0]           pwm_counter;

    always_ff @(posedge clk) begin
        if (rst) begin
            divider_count <= '0;
            pwm_counter   <= '0;
        end else begin
            if (PWM_DIVIDER <= 1) begin
                divider_count <= '0;
                pwm_counter   <= pwm_counter + 1'b1;
            end
            else if (divider_count == PWM_DIVIDER-1) begin
                divider_count <= '0;
                pwm_counter   <= pwm_counter + 1'b1;
            end
            else begin
                divider_count <= divider_count + 1'b1;
            end
        end
    end

    always_comb begin
        if (!enable)
            pwm_out = 1'b0;
        else if (duty == 8'hFF)
            pwm_out = 1'b1;
        else
            pwm_out = (pwm_counter < duty);
    end

endmodule
