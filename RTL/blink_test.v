`timescale 1ns / 100ps
module blink_test (
    input  wire clk,
    input  wire reset_n,
    output wire led_busy
);
    reg [26:0] counter;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            counter <= 27'd0;
        else
            counter <= counter + 1;
    end
    assign led_busy = counter[26];  // Toggle at ~0.5Hz
endmodule
