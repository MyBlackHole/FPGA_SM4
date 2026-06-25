#!/usr/bin/env python3
"""
SM4 UART Client — Tang Nano 20K FPGA UART Interface

Commands:
  ping                  Test connectivity (expects 'O' response)
  set-key <hexkey>      Set 128-bit key (32 hex chars)
  encrypt <hexdata>     Encrypt 128-bit block (32 hex chars)
  decrypt <hexdata>     Decrypt 128-bit block (32 hex chars)
  encrypt-file <in> <out>  Encrypt file (appends padding)
  decrypt-file <in> <out>  Decrypt file

Examples:
  python3 sm4_uart_client.py ping
  python3 sm4_uart_client.py set-key 0123456789abcdeffedcba9876543210
  python3 sm4_uart_client.py encrypt 0123456789abcdeffedcba9876543210
  python3 sm4_uart_client.py decrypt 681edf34d206965e86b3e94f536e4246
"""
# ============================================
# 备注：SM4 UART 命令行客户端 — 与 Tang Nano 20K FPGA 通信
# 备注：通过串口发送命令字节与 FPGA 上的 SM4 硬核交互
# 备注：支持单块加解密、密钥设置、文件加解密操作
# 备注：
# 备注：UART 通信协议（1 字节命令 + 变长负载）：
# 备注：  'P' (0x50) = Ping     → FPGA 回复 'O' (0x4F)
# 备注：  'K' (0x4B) + 16字节   → 设置 128 位密钥
# 备注：  'E' (0x45) + 16字节   → 加密明文块 → 返回 16 字节密文
# 备注：  'D' (0x44) + 16字节   → 解密密文块 → 返回 16 字节明文
# 备注：
# 备注：串口配置：115200 baud, 8N1 (8 数据位, 无校验, 1 停止位)
# 备注：波特率限制：115200 = ~86.8 µs/字节，每块约需 2.87 ms
# ============================================

import sys
import time
import struct
import serial
import argparse

# ── Defaults ──────────────────────────────────────────────────────────────────
# 备注：默认串口参数
# 备注：DEFAULT_PORT — Tang Nano 20K 在 Linux 下通常识别为 /dev/ttyUSB0
# 备注：DEFAULT_BAUD — 115200 是 FPGA UART IP 核支持的常用最高稳定波特率
# 备注：CMD_TIMEOUT — 单次 SM4 操作超时（含串口传输 + FPGA 计算），设为 5 秒
DEFAULT_PORT = "/dev/ttyUSB0"        # Tang Nano 20K (typically ttyUSB0)
DEFAULT_BAUD = 115200
CMD_TIMEOUT  = 5.0                    # seconds, for SM4 operation


def open_serial(port: str, baud: int) -> serial.Serial:
    # 备注：打开串口并配置为 8N1 模式
    # 备注：8 数据位 + 无校验 + 1 停止位是 UART 最通用的配置
    # 备注：timeout=1.0s — 读操作最多等待 1 秒，避免 FPGA 无响应时永久阻塞
    """Open serial port with 8N1 configuration."""
    ser = serial.Serial(
        port=port,
        baudrate=baud,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=1.0,
    )
    # 备注：清空输入/输出缓冲区，丢弃上电或前次操作残留的脏数据
    # Flush any stale data
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    return ser


# 备注：十六进制字符串与字节数组互转工具函数
# 备注：支持用户习惯的 "0x" 前缀格式，自动去除后再解析

def hex_to_bytes(hexstr: str) -> bytes:
    """Convert hex string to bytes, stripping 0x prefix if present."""
    hexstr = hexstr.strip()
    if hexstr.startswith("0x") or hexstr.startswith("0X"):
        hexstr = hexstr[2:]
    return bytes.fromhex(hexstr)


def bytes_to_hex(data: bytes) -> str:
    """Convert bytes to lowercase hex string."""
    return data.hex()


# 备注：UART 命令函数 — 遵循 1 字节命令 + 16 字节负载的协议格式
# 备注：所有操作前建议先执行 ping 确认 FPGA 在线（参见 main 中的安全检查）

def cmd_ping(ser: serial.Serial) -> bool:
    # 备注：发送 'P'（0x50）命令，FPGA 固件收到后回复 'O'（0x4F）
    # 备注：这是最简单的连通性测试，不涉及加解密逻辑
    """Send PING command; returns True if 'O' received."""
    ser.write(b"P")
    resp = ser.read(1)
    if resp == b"O":
        print("[OK] PING successful")
        return True
    else:
        print(f"[FAIL] Expected 'O', got {resp.hex() if resp else '(timeout)'}")
        return False


def cmd_set_key(ser: serial.Serial, key: bytes) -> bool:
    # 备注：发送 'K'（0x4B）+ 16 字节密钥
    # 备注：FPGA 收到后执行密钥扩展（key expansion），将原始密钥展开为 32 轮轮密钥
    # 备注：time.sleep(0.05) — 给 FPGA 足够的处理时间，避免后续操作时密钥尚未就绪
    """Send SET_KEY command (key = 16 bytes)."""
    if len(key) != 16:
        raise ValueError(f"Key must be 16 bytes, got {len(key)}")
    ser.write(b"K" + key)
    time.sleep(0.05)   # allow FPGA to process
    print(f"[OK] Key set: {bytes_to_hex(key)}")
    return True


def cmd_encrypt(ser: serial.Serial, plaintext: bytes) -> bytes:
    # 备注：发送 'E'（0x45）+ 16 字节明文 → FPGA 执行 SM4 加密 → 返回 16 字节密文
    # 备注：重试逻辑：首次 read(16) 可能未收全（FPGA 响应延迟），
    # 备注：sleep(0.5) 后再读剩余字节，确保收到完整 16 字节密文
    """Encrypt 16-byte block; returns 16-byte ciphertext."""
    if len(plaintext) != 16:
        raise ValueError(f"Plaintext must be 16 bytes, got {len(plaintext)}")
    ser.write(b"E" + plaintext)
    ciphertext = ser.read(16)
    if len(ciphertext) < 16:
        print(f"[WARN] Expected 16 bytes, got {len(ciphertext)} — retrying...")
        time.sleep(0.5)
        ciphertext += ser.read(16 - len(ciphertext))
    return ciphertext


def cmd_decrypt(ser: serial.Serial, ciphertext: bytes) -> bytes:
    # 备注：发送 'D'（0x44）+ 16 字节密文 → FPGA 执行 SM4 解密 → 返回 16 字节明文
    # 备注：重试逻辑与 cmd_encrypt 相同，处理 FPGA 响应延迟导致的读取不完整
    """Decrypt 16-byte block; returns 16-byte plaintext."""
    if len(ciphertext) != 16:
        raise ValueError(f"Ciphertext must be 16 bytes, got {len(ciphertext)}")
    ser.write(b"D" + ciphertext)
    plaintext = ser.read(16)
    if len(plaintext) < 16:
        print(f"[WARN] Expected 16 bytes, got {len(plaintext)} — retrying...")
        time.sleep(0.5)
        plaintext += ser.read(16 - len(plaintext))
    return plaintext


# ── PKCS7 Padding for file operations ─────────────────────────────────────────
# 备注：SM4 是 128 位（16 字节）分组密码，要求输入为 16 字节的整数倍
# 备注：PKCS7 填充方案：在数据末尾填充 N 个值为 N 的字节（1 ≤ N ≤ 16）
# 备注：例如 15 字节数据 → 填充 1 个 0x01；16 字节数据 → 补充 16 个 0x10

def pkcs7_pad(data: bytes, block_size: int = 16) -> bytes:
    # 备注：计算需要填充的字节数，使总长度为 block_size 的整数倍
    pad_len = block_size - (len(data) % block_size)
    return data + bytes([pad_len] * pad_len)


def pkcs7_unpad(data: bytes) -> bytes:
    # 备注：取最后一个字节作为填充长度，验证所有填充字节是否正确
    # 备注：若 padding 损坏，说明数据可能在传输中出错或被篡改
    pad_len = data[-1]
    if pad_len < 1 or pad_len > 16:
        raise ValueError("Invalid padding")
    # Verify all padding bytes
    if data[-pad_len:] != bytes([pad_len] * pad_len):
        raise ValueError("Invalid PKCS7 padding")
    return data[:-pad_len]


def encrypt_file(ser: serial.Serial, infile: str, outfile: str):
    # 备注：文件加密 — 先为明文添加 PKCS7 填充，再逐块调用 FPGA 加密
    # 备注：每加密一块即立即写入输出文件，避免内存中缓存整个密文
    # 备注：进度条格式：当前块号 / 总块数（利用 \r 覆盖同一行）
    """Encrypt file with PKCS7 padding."""
    with open(infile, "rb") as f:
        plaintext = f.read()
    padded = pkcs7_pad(plaintext)
    print(f"  Input:  {len(plaintext)} bytes → padded to {len(padded)} bytes")

    with open(outfile, "wb") as f:
        for block_idx in range(0, len(padded), 16):
            block = padded[block_idx:block_idx + 16]
            ct = cmd_encrypt(ser, block)
            f.write(ct)
            # Progress indicator
            sys.stdout.write(f"\r  Block {block_idx // 16 + 1}/{(len(padded) // 16)}")
            sys.stdout.flush()
    print(f"\n[OK] Encrypted: {infile} → {outfile}")


def decrypt_file(ser: serial.Serial, infile: str, outfile: str):
    # 备注：文件解密 — 逐块从 FPGA 读取解密结果，暂存 padded 缓冲区
    # 备注：所有块解密完成后统一调用 pkcs7_unpad 去除填充
    # 备注：注意：密文长度必须是 16 的倍数，否则说明文件损坏
    """Decrypt file and remove PKCS7 padding."""
    with open(infile, "rb") as f:
        ciphertext = f.read()
    if len(ciphertext) % 16 != 0:
        raise ValueError("Ciphertext length must be multiple of 16")

    with open(outfile, "wb") as f:
        padded = b""
        for block_idx in range(0, len(ciphertext), 16):
            block = ciphertext[block_idx:block_idx + 16]
            pt = cmd_decrypt(ser, block)
            padded += pt
            sys.stdout.write(f"\r  Block {block_idx // 16 + 1}/{(len(ciphertext) // 16)}")
            sys.stdout.flush()
    plaintext = pkcs7_unpad(padded)
    f.write(plaintext)
    print(f"\n[OK] Decrypted: {infile} → {outfile} ({len(plaintext)} bytes)")


# ── Main ──────────────────────────────────────────────────────────────────────
# 备注：主入口 — 使用 argparse 构建子命令式 CLI
# 备注：子命令结构：
# 备注：  ping          连通性测试
# 备注：  set-key       设置 128 位密钥
# 备注：  encrypt       加密一个 128 位数据块
# 备注：  decrypt       解密一个 128 位数据块
# 备注：  encrypt-file  文件加密（自动 PKCS7 填充）
# 备注：  decrypt-file  文件解密（自动去除 PKCS7 填充）

def main():
    parser = argparse.ArgumentParser(
        description="SM4 UART Client — Tang Nano 20K FPGA",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("-p", "--port", default=DEFAULT_PORT,
                        help=f"Serial port (default: {DEFAULT_PORT})")
    parser.add_argument("-b", "--baud", type=int, default=DEFAULT_BAUD,
                        help=f"Baud rate (default: {DEFAULT_BAUD})")

    subparsers = parser.add_subparsers(dest="command", required=True)

    # ping
    subparsers.add_parser("ping", help="Test connectivity")

    # set-key
    pk = subparsers.add_parser("set-key", help="Set 128-bit encryption key")
    pk.add_argument("key", help="32-hex-char key (e.g. 0123456789abcdeffedcba9876543210)")

    # encrypt
    pe = subparsers.add_parser("encrypt", help="Encrypt one 128-bit block")
    pe.add_argument("data", help="32-hex-char plaintext")

    # decrypt
    pd = subparsers.add_parser("decrypt", help="Decrypt one 128-bit block")
    pd.add_argument("data", help="32-hex-char ciphertext")

    # encrypt-file
    pef = subparsers.add_parser("encrypt-file",
                                help="Encrypt file (PKCS7 padding)")
    pef.add_argument("infile", help="Input file (plaintext)")
    pef.add_argument("outfile", help="Output file (ciphertext)")

    # decrypt-file
    pdf = subparsers.add_parser("decrypt-file",
                                help="Decrypt file (PKCS7 padding)")
    pdf.add_argument("infile", help="Input file (ciphertext)")
    pdf.add_argument("outfile", help="Output file (plaintext)")

    args = parser.parse_args()
    ser = open_serial(args.port, args.baud)

    try:
        # 备注：操作前安全检测 — 对需要 FPGA 响应的命令先执行 ping
        # 备注：避免在 FPGA 未就绪时发送密钥/数据导致静默失败
        # Always verify connectivity first (for data operations)
        if args.command in ("encrypt", "decrypt", "encrypt-file", "decrypt-file", "set-key"):
            if not cmd_ping(ser):
                print("[ERROR] No response from FPGA. Check connection and bitstream.")
                sys.exit(1)

        if args.command == "ping":
            cmd_ping(ser)

        elif args.command == "set-key":
            key = hex_to_bytes(args.key)
            cmd_set_key(ser, key)

        elif args.command == "encrypt":
            pt = hex_to_bytes(args.data)
            ct = cmd_encrypt(ser, pt)
            print(f"[OK] Ciphertext: {bytes_to_hex(ct)}")

        elif args.command == "decrypt":
            ct = hex_to_bytes(args.data)
            pt = cmd_decrypt(ser, ct)
            print(f"[OK] Plaintext:  {bytes_to_hex(pt)}")

        elif args.command == "encrypt-file":
            encrypt_file(ser, args.infile, args.outfile)

        elif args.command == "decrypt-file":
            decrypt_file(ser, args.infile, args.outfile)

    finally:
        ser.close()


if __name__ == "__main__":
    main()
