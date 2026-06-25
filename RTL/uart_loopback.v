`timescale 1ns / 100ps
// UART loopback test - echoes back received bytes
// Use for verifying BL616-FPGA UART communication
module uart_loopback (
    input  wire clk,
    input  wire reset_n,
    input  wire rx,
    output wire tx,
    output wire led_busy
);
    parameter CLK_FREQ = 27_000_000;
    parameter BAUD_RATE = 115200;

    wire [7:0] rx_data;
    wire       rx_received;
    wire       tx_send;
    wire [7:0] tx_data;
    wire       tx_busy;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE))
    u_rx (.clk(clk), .reset_n(reset_n), .rx(rx),
           .data_out(rx_data), .received(rx_received));

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE))
    u_tx (.clk(clk), .reset_n(reset_n), .send(tx_send),
           .data_in(tx_data), .tx(tx), .busy(tx_busy));

    reg tx_send_r;
    reg [7:0] tx_data_r;
    reg rx_received_d;
    wire rx_received_rising = rx_received && !rx_received_d;

    assign tx_send = tx_send_r;
    assign tx_data = tx_data_r;
    assign led_busy = tx_busy;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            tx_send_r <= 1'b0;
            tx_data_r <= 8'd0;
            rx_received_d <= 1'b0;
        end else begin
            rx_received_d <= rx_received;
            tx_send_r <= 1'b0;  // default: no send

            if (rx_received_rising) begin
                tx_data_r <= rx_data;
                tx_send_r <= 1'b1;
            end
        end
    end
endmodule
