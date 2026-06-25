`timescale 1ns / 100ps
////////////////////////////////////////////////////////////////////////////////
// UART Receiver
//   Configurable baud rate, 8N1.
//   Samples at mid-bit via a counter oversampler (1x bit-length).
//   received=1 for one clock when a new byte arrives at data_out.
////////////////////////////////////////////////////////////////////////////////
module uart_rx #(
    parameter CLK_FREQ = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       reset_n,
    input  wire       rx,          // serial input
    output reg  [7:0] data_out,    // received byte
    output reg        received     // pulse when new byte ready
);
    localparam BIT_CYCLES = CLK_FREQ / BAUD_RATE;
    localparam HALF_BIT = BIT_CYCLES / 2;

    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    reg [1:0] state;
    reg [15:0] counter;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;
    reg rx_d, rx_sync;      // synchroniser
    reg idle_guard;          // extra check: rx must be idle 1 before start

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            received <= 1'b0;
            rx_d <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_d <= rx;
            rx_sync <= rx_d;

            case (state)
                IDLE: begin
                    received <= 1'b0;
                    if (rx_sync == 1'b0) begin
                        // start bit detected – sample at half-bit
                        counter <= HALF_BIT;
                        state <= START;
                    end
                end

                START: begin
                    if (counter == 0) begin
                        if (rx_sync == 1'b0) begin
                            // confirmed start bit – begin data
                            counter <= BIT_CYCLES - 1;
                            bit_index <= 3'd0;
                            state <= DATA;
                        end else begin
                            // glitch – back to idle
                            state <= IDLE;
                        end
                    end else begin
                        counter <= counter - 1;
                    end
                end

                DATA: begin
                    if (counter == 0) begin
                        shift_reg[bit_index] <= rx_sync;
                        if (bit_index == 3'd7) begin
                            counter <= BIT_CYCLES - 1;
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                            counter <= BIT_CYCLES - 1;
                        end
                    end else begin
                        counter <= counter - 1;
                    end
                end

                STOP: begin
                    if (counter == 0) begin
                        data_out <= shift_reg;
                        received <= 1'b1;
                        state <= IDLE;
                    end else begin
                        counter <= counter - 1;
                    end
                end
            endcase
        end
    end

endmodule
