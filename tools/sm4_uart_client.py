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

import sys
import time
import struct
import serial
import argparse

# ── Defaults ──────────────────────────────────────────────────────────────────
DEFAULT_PORT = "/dev/ttyUSB0"        # Tang Nano 20K (typically ttyUSB0)
DEFAULT_BAUD = 115200
CMD_TIMEOUT  = 5.0                    # seconds, for SM4 operation


def open_serial(port: str, baud: int) -> serial.Serial:
    """Open serial port with 8N1 configuration."""
    ser = serial.Serial(
        port=port,
        baudrate=baud,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE,
        timeout=1.0,
    )
    # Flush any stale data
    ser.reset_input_buffer()
    ser.reset_output_buffer()
    return ser


def hex_to_bytes(hexstr: str) -> bytes:
    """Convert hex string to bytes, stripping 0x prefix if present."""
    hexstr = hexstr.strip()
    if hexstr.startswith("0x") or hexstr.startswith("0X"):
        hexstr = hexstr[2:]
    return bytes.fromhex(hexstr)


def bytes_to_hex(data: bytes) -> str:
    """Convert bytes to lowercase hex string."""
    return data.hex()


def cmd_ping(ser: serial.Serial) -> bool:
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
    """Send SET_KEY command (key = 16 bytes)."""
    if len(key) != 16:
        raise ValueError(f"Key must be 16 bytes, got {len(key)}")
    ser.write(b"K" + key)
    time.sleep(0.05)   # allow FPGA to process
    print(f"[OK] Key set: {bytes_to_hex(key)}")
    return True


def cmd_encrypt(ser: serial.Serial, plaintext: bytes) -> bytes:
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

def pkcs7_pad(data: bytes, block_size: int = 16) -> bytes:
    pad_len = block_size - (len(data) % block_size)
    return data + bytes([pad_len] * pad_len)


def pkcs7_unpad(data: bytes) -> bytes:
    pad_len = data[-1]
    if pad_len < 1 or pad_len > 16:
        raise ValueError("Invalid padding")
    # Verify all padding bytes
    if data[-pad_len:] != bytes([pad_len] * pad_len):
        raise ValueError("Invalid PKCS7 padding")
    return data[:-pad_len]


def encrypt_file(ser: serial.Serial, infile: str, outfile: str):
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
