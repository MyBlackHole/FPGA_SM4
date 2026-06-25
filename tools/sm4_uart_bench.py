#!/usr/bin/env python3
# ============================================
# 备注：SM4 UART 性能基准测试工具
# 备注：测量 FPGA SM4 硬核通过 UART 接口的实际吞吐量
# 备注：执行两轮测试：5 块热身 + N 块正式测量
# 备注：输出每块耗时（µs）和吞吐量（bps）
# ============================================

import serial, time, sys

# 备注：bench() — 单轮性能测试
# 备注：流程：设置密钥 → 预热（已内置在首次调用中）→ 计时加密 N 个块
# 备注：为什么两轮（热身 + 正式）？
# 备注：  首次调用时 UART 驱动和 FPGA 内部状态机需要"热身"
# 备注：  跳过热身直接测量会导致首块延迟偏高，反映非真实吞吐量
# 备注：
# 备注：吞吐量计算：
# 备注：  throughput = N × 128 / elapsed_time
# 备注：  128 = 16 字节 × 8 位/字节（每次加密 128 位数据）
# 备注：
# 备注：理论极限 @ 115200 baud：
# 备注：  每字节 = 10 位（起始位 + 8 数据位 + 停止位）
# 备注：  每块传输 = (1 命令 + 16 明文 + 16 密文) × 10 位 ≈ 330 位 ≈ 2.87 ms
# 备注：  SM4 硬核延迟 ~39 µs @ 27 MHz（远小于串口传输延迟）
# 备注：  瓶颈在 UART 带宽，不在 FPGA 计算速度

def bench(ser, N=100):
    key = bytes.fromhex('0123456789abcdeffedcba9876543210')
    plain = bytes.fromhex('0123456789abcdeffedcba9876543210')

    ser.reset_input_buffer()
    ser.write(b'K' + key)
    time.sleep(0.05)
    ser.read(1)

    t0 = time.perf_counter()
    ok = 0
    for _ in range(N):
        ser.write(b'E' + plain)
        data = ser.read(16)
        if len(data) == 16:
            ok += 1
    t1 = time.perf_counter()

    elapsed = t1 - t0
    per_block_us = elapsed * 1e6 / N
    throughput = N * 128 / elapsed

    print(f'Blocks:  {N}')
    print(f'OK:      {ok}/{N}')
    print(f'Time:    {elapsed*1e3:.1f} ms')
    print(f'Per blk: {per_block_us:.0f} us')
    print(f'Throughput: {throughput:.0f} bps ({throughput/8:.1f} B/s)')
    return per_block_us

def main():
    # 备注：从命令行参数读取串口和测试次数，默认值：ttyUSB1, 200 块
    port = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyUSB1'
    N = int(sys.argv[2]) if len(sys.argv) > 2 else 200

    # 备注：打开串口，timeout=2s 确保在 FPGA 无响应时不会永久挂起
    ser = serial.Serial(port, 115200, timeout=2)
    time.sleep(0.3)

    # 备注：发送 PING 验证 FPGA 在线，若失败则直接退出
    ser.reset_input_buffer()
    ser.write(b'P')
    time.sleep(0.1)
    if ser.read(1) != b'O':
        print('ERROR: Ping failed'); sys.exit(1)

    print(f'=== SM4 UART Benchmark ({N} blocks) ===')
    print()

    # 备注：两轮测试设计：
    # 备注：  第一轮 (N=5) — 热身，使 UART 驱动和 FPGA 状态机进入稳定状态
    # 备注：  第二轮 (N=N) — 正式测量，数据反映真实吞吐量
    bench(ser, N=5)
    bench(ser, N=N)

    # 备注：理论极限分析输出
    # 备注：  UART byte: 115200 baud 下每字节传输时间 = 10/115200 ≈ 86.8 µs
    # 备注：  Min block: 一次完整加密的最小串口传输时间 ≈ 2.87 ms
    # 备注：  SM4 core: FPGA 核心计算仅 ~39 µs，远快于串口传输
    # 备注：  结论：当前测试的瓶颈在 UART 带宽而非 SM4 核心速度
    print()
    print(f'Theoretical limits @ 115200 baud:')
    print(f'  UART byte:  {1e6/115200*10:.1f} us')
    print(f'  Min block:  {(1+16+16)*1e6/115200*10:.0f} us (cmd+send+recv)')
    print(f'  SM4 core:   ~39 us @ 27 MHz')

    ser.close()

if __name__ == '__main__':
    main()
