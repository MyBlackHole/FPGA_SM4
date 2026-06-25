`timescale 1ns / 100ps
// 备注：文件说明：SM4 UART 综合顶层封装
// 备注：
// 备注：本模块是 sm4_uart_top 的综合封装层，解决以下两个硬件实现问题：
// 备注：
// 备注：1. OBUF 资源节约：
// 备注：   FPGA 综合工具会为每个连接到顶层端口的输出信号自动推断
// 备注：   OBUF（输出缓冲器），这会消耗 I/O 资源和功耗。
// 备注：   tx_busy_out、sm4_result_out、sm4_ready_out 仅为调试/仿真
// 备注：   用途，在综合实现中不需要物理引脚。将它们悬空 (不连接) 即可
// 备注：   阻止综合工具为这些信号创建 OBUF，节省 FPGA 资源。
// 备注：
// 备注：2. 复位极性适配：
// 备注：   Tang Nano 20K 开发板的用户按钮 (pin 88) 在按下时输出高电平，
// 备注：   而 sm4_uart_top 核心模块的复位信号 reset_n 为低电平有效。
// 备注：   本模块通过 wire 取反操作将按钮电平转换为核心所需的极性。
// 备注：
////////////////////////////////////////////////////////////////////////////////
// SM4 UART Top — Synthesis wrapper
//   Wraps sm4_uart_top and leaves debug ports (tx_busy_out, sm4_result_out,
//   sm4_ready_out) unconnected so no OBUFs are inferred for them.
////////////////////////////////////////////////////////////////////////////////
module sm4_uart_top_synth (
    input  wire clk,
    input  wire reset_n,   // active-high from pin 88 (Sipeed button)
    input  wire rx,
    output wire tx,
    output wire led_busy
);
    // 备注：复位极性反转
    // 备注：Tang Nano 20K pin 88 按钮按下 = 高电平 (1)，
    // 备注：sm4_uart_top 核心模块要求低电平有效复位 (reset_n = 0 表示复位)。
    // 备注：取反后映射关系：
    // 备注：  按钮按下 (high, 1) → rst_n = 0 → 复位有效
    // 备注：  按钮松开 (low, 0)  → rst_n = 1 → 复位无效
    wire rst_n = !reset_n;  // invert: pin88 high=not-pressed → rst_n low=not-reset

    sm4_uart_top #(
        .CLK_FREQ(27_000_000),
        .BAUD_RATE(115200)
    ) u_core (
        .clk(clk),
        .reset_n(rst_n),
        .rx(rx),
        .tx(tx),
        .led_busy(led_busy),
        // 备注：调试端口悬空 — 防止 OBUF 推断
        // 备注：这些信号仅在仿真/调试时使用，在综合实现中不需要
        // 备注：物理引脚输出。端口留空 (不连信号线) 后，综合工具
        // 备注：不会为它们插入 OBUF，从而节约 I/O 资源和功耗。
        .tx_busy_out(),      // unused — no OBUF inferred
        .sm4_result_out(),   // unused — no OBUF inferred
        .sm4_ready_out()     // unused — no OBUF inferred
    );
endmodule
