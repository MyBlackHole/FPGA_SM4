`timescale 1ns / 100ps
// UART RX Test - show rx pin value on LED
// If BL616 sends data, LED should flicker when we send bytes
module rx_test (
    input  wire clk,
    input  wire reset_n,
    input  wire rx,
    output wire tx,
    output wire led_busy
);
    // Don't use tx (leave unconnected, but need to declare it)
    assign tx = 1'b1;
    
    // Show RX pin value on LED (LED on = rx idle = high = LED off)
    // LED is active low: led_busy=0 → ON, led_busy=1 → OFF
    // When idle, rx=1, so LED off
    // When data comes, rx toggles → LED flickers
    assign led_busy = ~rx;  // LED ON when rx=0 (start bit or data 0)
endmodule
