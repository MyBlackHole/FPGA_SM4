`timescale 1ns / 100ps
// LED test
module blink_test (
    input  wire clk,
    input  wire reset_n,
    output wire led_busy
);
    // led_busy=0 turns LED ON (active low output)
    assign led_busy = 1'b0;  // Force LED ON to verify pin works
endmodule
