#!/usr/bin/env python3
import serial, time, sys

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
    port = sys.argv[1] if len(sys.argv) > 1 else '/dev/ttyUSB1'
    N = int(sys.argv[2]) if len(sys.argv) > 2 else 200

    ser = serial.Serial(port, 115200, timeout=2)
    time.sleep(0.3)

    ser.reset_input_buffer()
    ser.write(b'P')
    time.sleep(0.1)
    if ser.read(1) != b'O':
        print('ERROR: Ping failed'); sys.exit(1)

    print(f'=== SM4 UART Benchmark ({N} blocks) ===')
    print()

    bench(ser, N=5)
    bench(ser, N=N)

    print()
    print(f'Theoretical limits @ 115200 baud:')
    print(f'  UART byte:  {1e6/115200*10:.1f} us')
    print(f'  Min block:  {(1+16+16)*1e6/115200*10:.0f} us (cmd+send+recv)')
    print(f'  SM4 core:   ~39 us @ 27 MHz')

    ser.close()

if __name__ == '__main__':
    main()
