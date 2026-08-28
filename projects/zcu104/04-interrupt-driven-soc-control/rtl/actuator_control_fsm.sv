`timescale 1ns/1ps

module actuator_control_fsm #(
    parameter int STARTUP_CYCLES = 50_000_000
)(
    input  logic       clk,
    input  logic       rst,
    input  logic       control_request,

    // Runtime RUN duty from AXI register
    input  logic [7:0] run_duty,

    output logic       actuator_enable,
    output logic [7:0] pwm_duty,
    output logic [1:0] state_code
);

    typedef enum logic [1:0] {
        CTRL_OFF     = 2'b00,
        CTRL_STARTUP = 2'b01,
        CTRL_RUN     = 2'b10
    } state_t;

    state_t state_q, state_d;

    localparam int COUNT_WIDTH =
        (STARTUP_CYCLES <= 1) ? 1 : $clog2(STARTUP_CYCLES);

    logic [COUNT_WIDTH-1:0] startup_count;

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q       <= CTRL_OFF;
            startup_count <= '0;
        end
        else begin
            state_q <= state_d;

            if (state_q != CTRL_STARTUP)
                startup_count <= '0;
            else if (startup_count < STARTUP_CYCLES-1)
                startup_count <= startup_count + 1'b1;
        end
    end

    always_comb begin
        state_d = state_q;

        case (state_q)

            CTRL_OFF:
                if (control_request)
                    state_d = CTRL_STARTUP;

            CTRL_STARTUP:
                if (!control_request)
                    state_d = CTRL_OFF;
                else if (startup_count >= STARTUP_CYCLES-1)
                    state_d = CTRL_RUN;

            CTRL_RUN:
                if (!control_request)
                    state_d = CTRL_OFF;

            default:
                state_d = CTRL_OFF;

        endcase
    end

    always_comb begin
        actuator_enable = 1'b0;
        pwm_duty         = 8'd0;

        case (state_q)

            CTRL_STARTUP: begin
                actuator_enable = 1'b1;
                pwm_duty         = 8'hFF;
            end

            CTRL_RUN: begin
                actuator_enable = 1'b1;
                pwm_duty         = run_duty;
            end

            default: begin
                actuator_enable = 1'b0;
                pwm_duty         = 8'd0;
            end

        endcase
    end

    assign state_code = state_q;

endmodule
