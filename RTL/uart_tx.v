`timescale 1ns / 100ps
////////////////////////////////////////////////////////////////////////////////
// UART Transmitter
//   Configurable baud rate, 8N1 format.
//   Trigger: pulse send=1 with 8-bit data_in → sends start+data+stop bits.
//   busy=1 while sending (hold data_in stable).
////////////////////////////////////////////////////////////////////////////////
module uart_tx #(
    parameter CLK_FREQ = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       reset_n,
    input  wire       send,       // pulse to start transmission
    input  wire [7:0] data_in,    // byte to send
    output reg        tx,         // serial output
    output reg        busy        // 1 while transmission in progress
);
    localparam BIT_CYCLES = CLK_FREQ / BAUD_RATE;

    localparam IDLE = 3'd0;
    localparam START = 3'd1;
    localparam DATA = 3'd2;
    localparam STOP = 3'd3;

    reg [2:0] state;
    reg [15:0] counter;
    reg [2:0] bit_index;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            tx <= 1'b1;     // idle high
            busy <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1'b1;
                    busy <= 1'b0;
                    if (send) begin
                        busy <= 1'b1;
                        tx <= 1'b0;         // start bit
                        counter <= BIT_CYCLES - 1;
                        bit_index <= 3'd0;
                        state <= START;
                    end
                end

                START: begin
                    if (counter == 0) begin
                        tx <= data_in[0];
                        counter <= BIT_CYCLES - 1;
                        state <= DATA;
                    end else begin
                        counter <= counter - 1;
                    end
                end

                DATA: begin
                    if (counter == 0) begin
                        if (bit_index == 3'd7) begin
                            tx <= 1'b1;     // stop bit
                            counter <= BIT_CYCLES - 1;
                            state <= STOP;
                        end else begin
                            bit_index <= bit_index + 1;
                            tx <= data_in[bit_index + 1];
                            counter <= BIT_CYCLES - 1;
                        end
                    end else begin
                        counter <= counter - 1;
                    end
                end

                STOP: begin
                    if (counter == 0) begin
                        state <= IDLE;
                        busy <= 1'b0;
                    end else begin
                        counter <= counter - 1;
                    end
                end
            endcase
        end
    end

endmodule
