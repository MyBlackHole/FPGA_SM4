`timescale 1ns / 100ps
////////////////////////////////////////////////////////////////////////////////
// UART Receiver
//   Configurable baud rate, 8N1.
//   Samples at mid-bit via a counter oversampler (1x bit-length).
//   received=1 for one clock when a new byte arrives at data_out.
////////////////////////////////////////////////////////////////////////////////
// 备注：UART 8N1 帧格式：
// 备注：  起始位：1 位，逻辑 0
// 备注：  数据位：8 位，LSB 优先发送（bit0 最先）
// 备注：  停止位：1 位，逻辑 1
// 备注：
// 备注：中点采样策略：
// 备注：  检测到 rx 下降沿（起始位开始）后，等待 HALF_BIT 个时钟周期
// 备注：  到达起始位中点位置采样确认，之后每 BIT_CYCLES 个时钟采样一次
// 备注：  确保在每个数据位的中间位置读取，避免边沿附近的信号不稳定
// 备注：
// 备注：两级触发器同步器（rx → rx_d → rx_sync）：
// 备注：  将异步输入的 rx 信号同步到 clk 时钟域，降低亚稳态传播风险
// 备注：
// 备注：4 状态 FSM（IDLE/START/DATA/STOP）：
// 备注：  IDLE  → 检测起始位下降沿
// 备注：  START → 中点采样确认有效起始位，兼做毛刺过滤
// 备注：  DATA  → 按中点采样 8 个数据位存入 shift_reg
// 备注：  STOP  → 等待停止位结束，输出接收字节
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
    // 备注：BIT_CYCLES = 时钟频率 / 波特率，即每个数据位占用的时钟周期数
    // 备注：例如 CLK_FREQ=27MHz, BAUD_RATE=115200 时，BIT_CYCLES ≈ 234
    // 备注：HALF_BIT 用于起始位的中点采样确认
    localparam BIT_CYCLES = CLK_FREQ / BAUD_RATE;
    localparam HALF_BIT = BIT_CYCLES / 2;

    // 备注：FSM 状态定义：
    // 备注：  IDLE  - 空闲态，等待 rx 下降沿检测到起始位
    // 备注：  START - 起始位确认态，中点采样验证是否为有效起始位（去毛刺）
    // 备注：  DATA  - 数据位采集态，按 bit_index 依次采样 8 个数据位
    // 备注：  STOP  - 停止位等待态，完成后将 shift_reg 输出到 data_out
    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    reg [1:0] state;
    reg [15:0] counter;
    reg [2:0] bit_index;
    reg [7:0] shift_reg;
    // 备注：两级触发器同步器，消除亚稳态
    // 备注：rx_d 锁存异步输入，rx_sync 在下一拍同步输出
    // 备注：两级寄存器链可将亚稳态的 MTBF 提升至可接受水平
    reg rx_d, rx_sync;      // synchroniser
    reg idle_guard;          // extra check: rx must be idle 1 before start

    // 备注：主状态机：UART 接收控制
    // 备注：异步复位（reset_n 低有效）进入 IDLE 态
    // 备注：rx_d/rx_sync 复位为 1'bx 后置为 1（空闲高电平）
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
                // 备注：IDLE 态：监听 rx 线路，等待起始位（下降沿）
                // 备注：rx_sync == 0 表示检测到起始位下降沿
                // 备注：设置 HALF_BIT 计数器后转入 START 进行中点确认
                IDLE: begin
                    received <= 1'b0;
                    if (rx_sync == 1'b0) begin
                        // start bit detected – sample at half-bit
                        counter <= HALF_BIT;
                        state <= START;
                    end
                end

                // 备注：START 态：等待到达起始位中点后重新采样确认
                // 备注：若 rx_sync 仍为 0 → 确认有效起始位，转入 DATA
                // 备注：若 rx_sync 变为 1 → 视为毛刺（glitch），退回 IDLE
                // 备注：counter 以 HALF_BIT 为初值递减，到 0 时恰好是起始位中点
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

                // 备注：DATA 态：每个 BIT_CYCLES 采集一个数据位，中点采样
                // 备注：采样值存入 shift_reg[bit_index]，LSB 优先（bit0 最先到达）
                // 备注：bit_index 从 0 递增到 7，采满 8 位后转入 STOP 态
                // 备注：每次采样后重置 counter = BIT_CYCLES - 1
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

                // 备注：STOP 态：等待停止位（高电平）持续结束
                // 备注：counter 归零时，将 shift_reg 锁存到 data_out
                // 备注：产生 received 高电平脉冲（持续 1 拍）通知上层模块
                // 备注：状态回到 IDLE，准备接收下一帧
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
