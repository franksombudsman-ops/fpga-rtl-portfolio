`timescale 1ns/1ps

module tb_threshold_hysteresis;

logic clk = 0;
logic rst;
logic [11:0] sample_in;
logic sample_valid;
logic control_request;

always #4 clk = ~clk;   // 125 MHz

threshold_hysteresis dut (
    .clk(clk),
    .rst(rst),
    .sample_in(sample_in),
    .sample_valid(sample_valid),
    .control_request(control_request)
);

task send_sample(input logic [11:0] value);
begin
    @(negedge clk);
    sample_in    = value;
    sample_valid = 1'b1;

    @(negedge clk);
    sample_valid = 1'b0;
end
endtask

initial begin
    rst          = 1'b1;
    sample_in    = 12'h000;
    sample_valid = 1'b0;

    repeat (3) @(posedge clk);
    rst = 1'b0;

    // Below threshold: remain OFF
    send_sample(12'hB50);
    if (control_request !== 1'b0)
        $fatal(1, "FAIL: should remain OFF below high threshold");

    // Enter hysteresis band: still OFF
    send_sample(12'hBA0);
    if (control_request !== 1'b0)
        $fatal(1, "FAIL: should remain OFF inside hysteresis band");

    // Cross HIGH threshold: turn ON
    send_sample(12'hC10);
    if (control_request !== 1'b1)
        $fatal(1, "FAIL: should turn ON above high threshold");

    // Fall into hysteresis band: remain ON
    send_sample(12'hBC0);
    if (control_request !== 1'b1)
        $fatal(1, "FAIL: should remain ON inside hysteresis band");

    // Cross LOW threshold: turn OFF
    send_sample(12'hB70);
    if (control_request !== 1'b0)
        $fatal(1, "FAIL: should turn OFF below low threshold");

    $display("PASS: threshold hysteresis verification complete");
    $finish;
end

endmodule
