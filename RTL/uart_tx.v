`timescale 1ns / 100ps
////////////////////////////////////////////////////////////////////////////////
// UART Transmitter
//   Configurable baud rate, 8N1 format.
//   Trigger: pulse send=1 with 8-bit data_in → sends start+data+stop bits.
//   busy=1 while sending (hold data_in stable).
////////////////////////////////////////////////////////////////////////////////
// 备注：UART 发送序列（8N1）：
// 备注：  空闲态：tx = 1（高电平，线路空闲）
// 备注：  起始位：tx = 0，持续 1 个位时间（BIT_CYCLES 个时钟周期）
// 备注：  数据位：依次发送 data_in[0] ~ data_in[7]（LSB 优先）
// 备注：  停止位：tx = 1，持续 1 个位时间
// 备注：
// 备注：busy 握手协议：
// 备注：  send 为高电平时触发发送，busy 立即置 1
// 备注：  发送期间外部模块必须保持 data_in 稳定不变
// 备注：  停止位发送完毕后 busy 归零，表示可接收下一个字节
// 备注：
// 备注：与 uart_rx 的对比：
// 备注：  uart_tx 使用 BIT_CYCLES 计数器控制每位持续时间
// 备注：  uart_rx 则用 BIT_CYCLES 做中点采样，两者计数器用法不同
// 备注：  uart_tx 主动驱动 tx 引脚，uart_rx 被动采样 rx 引脚
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
    // 备注：BIT_CYCLES = 时钟频率 / 波特率
    // 备注：决定每个数据位的持续时间（时钟周期数）
    // 备注：发送器用此值作为计数器的重载值，每位精确持续一个位时间
    localparam BIT_CYCLES = CLK_FREQ / BAUD_RATE;

    // 备注：FSM 状态定义：
    // 备注：  IDLE  - 空闲态，等待 send 脉冲触发发送
    // 备注：  START - 发送起始位（低电平），持续 1 个位时间
    // 备注：  DATA  - 按 bit_index 依次发送 8 个数据位（LSB 优先）
    // 备注：  STOP  - 发送停止位（高电平），持续 1 个位时间
    localparam IDLE = 3'd0;
    localparam START = 3'd1;
    localparam DATA = 3'd2;
    localparam STOP = 3'd3;

    reg [2:0] state;
    reg [15:0] counter;
    reg [2:0] bit_index;

    // 备注：主状态机：UART 发送控制
    // 备注：异步复位（reset_n 低有效）时将 tx 置 1（空闲高电平）、busy 置 0
    // 备注：与 uart_rx 不同，发送器无需同步器，控制内部逻辑直接驱动 tx 引脚
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state <= IDLE;
            tx <= 1'b1;     // idle high
            busy <= 1'b0;
        end else begin
            case (state)
                // 备注：IDLE 态：tx 保持高电平（空闲状态），busy 输出 0
                // 备注：收到 send=1 脉冲后立即将 busy 拉高，表示开始发送
                // 备注：同时输出起始位 0，设置 BIT_CYCLES 计数器，转入 START
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

                // 备注：START 态：保持起始位（低电平），等待 counter 递减到 0
                // 备注：counter 归零时表明起始位已持续满 1 个位时间
                // 备注：切换输出 data_in[0]（第一个数据位，LSB），转入 DATA
                START: begin
                    if (counter == 0) begin
                        tx <= data_in[0];
                        counter <= BIT_CYCLES - 1;
                        state <= DATA;
                    end else begin
                        counter <= counter - 1;
                    end
                end

                // 备注：DATA 态：每个 BIT_CYCLES 切换一个数据位
                // 备注：tx <= data_in[bit_index]，当前位发送完毕后索引 +1
                // 备注：bit_index 从 0→1→...→7，共发送 8 个数据位
                // 备注：发送完 bit7（最后一个数据位）后 tx 置 1，转入 STOP
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

                // 备注：STOP 态：发送停止位（高电平），持续 1 个位时间
                // 备注：counter 归零后回到 IDLE 态，busy 归零
                // 备注：外部模块检测到 busy 下降沿后即可发起下一帧发送
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
