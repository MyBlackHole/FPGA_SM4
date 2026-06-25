`timescale 1ns / 100ps
////////////////////////////////////////////////////////////////////////////////
// SM4 UART Top — Synthesis wrapper
//   Wraps sm4_uart_top and leaves debug ports (tx_busy_out, sm4_result_out,
//   sm4_ready_out) unconnected so no OBUFs are inferred for them.
////////////////////////////////////////////////////////////////////////////////
module sm4_uart_top_synth (
    input  wire clk,
    input  wire reset_n,
    input  wire rx,
    output wire tx,
    output wire led_busy
);
    sm4_uart_top #(
        .CLK_FREQ(27_000_000),
        .BAUD_RATE(115200)
    ) u_core (
        .clk(clk),
        .reset_n(reset_n),
        .rx(rx),
        .tx(tx),
        .led_busy(led_busy),
        .tx_busy_out(),      // unused — no OBUF inferred
        .sm4_result_out(),   // unused — no OBUF inferred
        .sm4_ready_out()     // unused — no OBUF inferred
    );
endmodule
