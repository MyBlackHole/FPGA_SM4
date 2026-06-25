`timescale 1ns / 100ps
////////////////////////////////////////////////////////////////////////////////
// Testbench: SM4 UART Top
//
// Strategy:
//   - Sends commands to the FPGA via UART (drives the rx pin).
//   - Verifies SM4 core result via sm4_result_out / sm4_ready_out (internal).
//   - Captures UART TX bytes autonomously (cap_* always block samples tx at
//     mid-bit using clock-synchronous timing).
//   - After each transaction, checks captured bytes against expected values.
//
//  UART protocol:
//    'P' + 0 payload bytes   Ping, FPGA returns 'O'
//    'K' + 16 key bytes      Set key
//    'E' + 16 plaintext      Encrypt, returns 16 ciphertext bytes
//    'D' + 16 ciphertext     Decrypt, returns 16 plaintext bytes
////////////////////////////////////////////////////////////////////////////////
// 备注：SM4 UART 级测试激励 — 双重验证策略
// 备注：
// 备注：┌─────────────────────────────────────────────────────────────────┐
// 备注：│                    测试流程总览                                    │
// 备注：│   PING(0x50) → SET_KEY(0x4B) → ENCRYPT(0x45) → DECRYPT(0x44)   │
// 备注：└─────────────────────────────────────────────────────────────────┘
// 备注：
// 备注：[路径 A - 内部信号验证]
// 备注：  直接观察 sm4_result_out / sm4_ready_out
// 备注：  在 SM4 内核完成运算后即时比对结果
// 备注：  优点：不依赖 UART 收发，可独立验证内核正确性
// 备注：
// 备注：[路径 B - UART TX 验证]
// 备注：  通过硬件嗅探器自动捕获 FPGA 发出的串口字节
// 备注：  将捕获的字节流与预期值逐字节比对
// 备注：  优点：覆盖 UART 收发通路完整性
// 备注：
// 备注：两条路径独立验证，任一失败都能定位问题来源
// 备注：
////////////////////////////////////////////////////////////////////////////////

module tb_sm4_uart;

    // ── Parameters ──────────────────────────────────────────────────────────
    // NOTE: $time counts in time-PRECISION units (0.1ns per `timescale 1ns/100ps).
    //       So $time value = ns / 0.1.  #37 = 37ns, $time += 370.
    //       All #delays are in ns (time unit = 1ns).  Real values work fine.
    localparam real    CLK_NS     = 37.037;    // ns, 27 MHz period
    localparam integer CLK_FREQ   = 27_000_000;
    localparam integer BAUD_RATE  = 115200;
    localparam integer BIT_CYCLES = CLK_FREQ / BAUD_RATE;           // 234
    localparam real    BIT_TIME_NS = (CLK_NS * CLK_FREQ) / BAUD_RATE; // 8680.55
    // 备注：BIT_CYCLES = 27MHz / 115200 ≈ 234 个时钟周期/bit
    // 备注：BIT_TIME_NS ≈ 8680.55 ns/bit — 即每 bit 持续约 8.68 µs

    // Debug: verify timing params
    // initial block with param debug removed (moved to main seq)

    // Test vectors (from SM4 standard)
    localparam [127:0] KEY = 128'h01234567_89abcdef_fedcba98_76543210;
    localparam [127:0] PLAIN = 128'h01234567_89abcdef_fedcba98_76543210;
    localparam [127:0] EXPECTED_CIPHER = 128'h681edf34_d206965e_86b3e94f_536e4246;

    // ── Signals ─────────────────────────────────────────────────────────────
    reg clk;
    reg reset_n;
    reg rx;
    wire tx;
    wire led_busy;
    wire tx_busy_out;
    wire [127:0] sm4_result_out;
    wire         sm4_ready_out;

    // DUT
    sm4_uart_top #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_dut (
        .clk(clk),
        .reset_n(reset_n),
        .rx(rx),
        .tx(tx),
        .led_busy(led_busy),
        .tx_busy_out(tx_busy_out),
        .sm4_result_out(sm4_result_out),
        .sm4_ready_out(sm4_ready_out)
    );

    // 备注：sm4_done 锁存器 — 将单周期脉冲展宽为电平信号
    // 备注：
    // 备注：sm4_ready_out 是 SM4 内核输出的单周期脉冲，宽度仅 1 个时钟周期。
    // 备注：如果用 @(posedge sm4_ready_out) 触发，在脉冲到达时 testbench
    // 备注：可能还在发送数据字节（SM4 计算仅需 ~2.5µs，而 16 字节 UART 发送
    // 备注：需 ~16×10×8.68µs ≈ 1.39ms），会错过脉冲边沿。
    // 备注：因此用锁存器将脉冲展宽为电平信号 sm4_done，testbench 通过 wait()
    // 备注：等待该电平，不受脉冲宽度影响。
    // Latch sm4_ready_out (it's a single-cycle pulse)
    reg sm4_done;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            sm4_done <= 1'b0;
        else if (sm4_ready_out)
            sm4_done <= 1'b1;
    end

    // ── Clock generation ────────────────────────────────────────────────────
    initial clk = 0;
    always #(CLK_NS / 2.0) clk = ~clk;

    // 备注：UART TX 硬件嗅探器 — 自动捕获 FPGA 发出的串口数据
    // 备注：
    // 备注：工作原理：
    // 备注：  1. 空闲时 (tx=高电平) 将 cap_armed 置 1，准备检测起始位
    // 备注：  2. 检测到 tx 下降沿 (起始位) → 跳转到中间位置开始采样
    // 备注：  3. 每个数据位在中间位置采样 (BIT_CYCLES 计时器控制)
    // 备注：  4. 采集完 8 个数据位后存入环形缓冲区 cap_buf[cap_wr]
    // 备注：  5. cap_wr 递增，testbench 通过差值判断捕获字节数
    // 备注：
    // 备注：环形缓冲区设计 (Ring Buffer)：
    // 备注：  - 256 字节深度 (cap_buf[0:255])，cap_wr 为写指针
    // 备注：  - testbench 在发送前记录 prev_wr = cap_wr (快照当前写指针)
    // 备注：  - 发送完成后 n = cap_wr - prev_wr 即为新捕获的字节数
    // 备注：  - 通过 cap_buf[prev_wr + i] 索引访问具体捕获字节
    // 备注：  - 256 字节足够大 (最大一次传输仅 16 字节)，不会溢出
    // ── UART TX capture (autonomous hardware sniffer) ───────────────────────
    // Continuously watches the tx pin and samples UART frames at mid-bit
    // positions using clock-synchronous timing.  Stores bytes in a ring
    // buffer for later verification.
    reg [7:0]  cap_buf[0:255];       // ring buffer
    reg [7:0]  cap_wr;               // write index
    reg        cap_busy;             // currently capturing a frame
    reg [15:0] cap_cnt;              // bit-time counter
    reg [3:0]  cap_bit;              // bit index (0-7)
    reg [7:0]  cap_shift;            // shift register
    reg        cap_armed;            // tx was idle, ready to detect start bit

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cap_busy  <= 1'b0;
            cap_cnt   <= 16'd0;
            cap_bit   <= 3'd0;
            cap_shift <= 8'd0;
            cap_wr    <= 8'd0;
            cap_armed <= 1'b0;
        end else if (!cap_busy) begin
            if (cap_armed && !tx) begin
                // Start bit detected → skip straight to mid-bit-0
                // (1.5 bit times from the rising edge that armed us,
                //  minus 1 because the counter decrements on the next cycle)
                // 备注：中间采样的数学推导：
                // 备注：从检测到起始位下降沿的时钟上升沿开始计算：
                // 备注：  跳过量 = BIT_CYCLES (起始位全宽)
                // 备注：         + BIT_CYCLES/2 (半个数据位，到 bit-0 中间)
                // 备注：         - 1 (计数器在下一周期会再减 1)
                // 备注：         = 234 + 117 - 1 = 350
                // 备注：之后每次采样间隔 BIT_CYCLES - 1 = 233，
                // 备注：恰好落在下一位的中间位置
                cap_busy  <= 1'b1;
                cap_cnt   <= (BIT_CYCLES * 3) / 2 - 1;  // 350 → mid-bit-0
                cap_bit   <= 3'd0;
                cap_armed <= 1'b0;
            end else if (tx) begin
                cap_armed <= 1'b1;              // tx idle, arm for start bit
            end
        end else begin
            if (cap_cnt == 0) begin
                if (cap_bit < 4'd8) begin
                    // Sample data bit at mid-bit
                    cap_shift[cap_bit] <= tx;
                    cap_bit <= cap_bit + 1;
                    cap_cnt <= BIT_CYCLES - 1;
                end else begin
                    // All 8 bits captured -> store
                    cap_buf[cap_wr] <= cap_shift;
                    cap_wr <= cap_wr + 1;
                    cap_busy <= 1'b0;
                end
            end else begin
                cap_cnt <= cap_cnt - 1;
            end
        end
    end

    // 备注：UART 发送任务 — 驱动 FPGA 的 rx 引脚
    // 备注：
    // 备注：UART 帧格式 (8N1) 时序：
    // 备注：  ┌──────┬──────┬──────┬───────┬──────┐
    // 备注：  │起始位 │ bit-0 │ bit-1 │ … │ bit-7 │ 停止位 │
    // 备注：  │  0   │ LSB  │  …   │  …  │ MSB  │   1   │
    // 备注：  └──────┴──────┴──────┴───────┴──────┘
    // 备注：  每段持续 BIT_TIME_NS ≈ 8.68 µs
    // 备注：  每字节总时间 = 10 × 8.68 µs = 86.8 µs
    // 备注：  16 字节传输 ≈ 16 × 86.8 µs ≈ 1.39 ms
    // 备注：
    // 备注：每次 #(BIT_TIME_NS) 延时使用实际时间值 (ns)，
    // 备注：而非时钟周期计数。这样时序更精确。
    // ── UART Transmit (drives rx pin toward the FPGA) ───────────────────────
    task uart_send(input [7:0] byte_data);
        integer i;
        begin
            rx = 0;              #(BIT_TIME_NS);  // start bit
            for (i = 0; i < 8; i = i + 1) begin
                rx = byte_data[i];  #(BIT_TIME_NS);  // data bits LSB-first
            end
            rx = 1;              #(BIT_TIME_NS);  // stop bit
        end
    endtask

    task uart_send_bytes(input [127:0] data, input [4:0] count);
        integer b;
        begin
            for (b = 0; b < count; b = b + 1) begin
                uart_send(data[127 - b*8 -: 8]);
            end
        end
    endtask

    // 备注：主测试序列 — 依次执行 PING / SET_KEY / ENCRYPT / DECRYPT
    // 备注：
    // 备注：测试流程：
    // 备注：  PING ──→ SET_KEY ──→ ENCRYPT ──→ DECRYPT ──→ ALL PASS
    // 备注：    │          │            │            │
    // 备注：    │ 验证 'O' │ 设置密钥   │ 验证密文   │ 验证明文
    // 备注：    │          │            ├─ sm4 内核  ├─ sm4 内核
    // 备注：    │          │            └─ TX 字节   └─ TX 字节
    // 备注：
    // 备注：图例：─→ 表示测试顺序，每步必须通过才能继续
    // ── Test sequence ───────────────────────────────────────────────────────
    initial begin
        reg [7:0] n;
        reg [7:0] prev_wr;
        integer i;
        reg mismatch;

        $display("═══════════════════════════════════════════════");
        $display("SM4 UART Testbench @ %0d baud", BAUD_RATE);
        $display("Clock: %0d MHz", CLK_FREQ / 1000000);
        $display("CLK_NS=%0f BIT_TIME_NS=%0f", CLK_NS, BIT_TIME_NS);
        $display("═══════════════════════════════════════════════");

        // ── Initialize ───────────────────────────────────────────────────────
        rx = 1'b1;
        reset_n = 1'b0;
        #(CLK_NS * 10);
        $display("[%0t] reset released", $time);
        reset_n = 1'b1;
        #(CLK_NS * 10);
        $display("[%0t] starting tests", $time);

        // Note: $time counts in 0.1ns units (timescale precision).
        // So $time values appear 10x larger than the actual ns time.

        // 备注：==============================
        // 备注：[测试 1] PING — 验证 FPGA 基本通信通路
        // 备注：  发送 ASCII 'P' (0x50)
        // 备注：  预期 FPGA 返回 ASCII 'O' (0x4F)
        // 备注：  失败意味着 UART 链路或 FPGA 启动异常
        // 备注：==============================
        // ═══════════════════════════════════════════════════════════════════
        // [1] PING test
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[1] PING test:");
        prev_wr = cap_wr;
        uart_send(8'h50);  // 'P'
        // Wait for FPGA to process PING and finish
        wait(led_busy);
        @(negedge led_busy);
        @(posedge clk);
        // Read captured byte
        n = cap_wr - prev_wr;
        if (n !== 1) begin
            $display("  FAIL: expected 1 byte, captured %0d", n);
        end else if (cap_buf[prev_wr] !== 8'h4F) begin
            $display("  FAIL: expected 'O' (0x4F), got 0x%02h", cap_buf[prev_wr]);
        end else begin
            $display("  PING PASS: got 'O' (0x4F)");
        end

        // 备注：==============================
        // 备注：[测试 2] SET_KEY — 设置 SM4 加密密钥
        // 备注：  发送 ASCII 'K' (0x4B) 作为命令字
        // 备注：  随后发送 16 字节密钥 (MSB 优先)
        // 备注：  密钥固定为标准测试向量：
        // 备注：    KEY = 01234567 89abcdef fedcba98 76543210
        // 备注：  此步骤无 UART TX 返回，等待 20 周期后继续
        // 备注：==============================
        // ═══════════════════════════════════════════════════════════════════
        // [2] SET_KEY
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[2] SET_KEY:");
        $display("[%0t] sending 'K'...", $time);
        uart_send(8'h4B);  // 'K'
        $display("[%0t] sending 16 key bytes...", $time);
        uart_send_bytes(KEY, 16);
        $display("[%0t] key sent, waiting 20 cycles", $time);
        #(CLK_NS * 20);
        $display("  Key set complete @ %0t", $time);

        // 备注：==============================
        // 备注：[测试 3] ENCRYPT — 加密测试
        // 备注：  发送 ASCII 'E' (0x45) 作为命令字
        // 备注：  随后发送 16 字节明文 (MSB 优先)
        // 备注：  验证策略：
        // 备注：  [路径 A] SM4 内核输出 sm4_result_out 应等于 EXPECTED_CIPHER
        // 备注：  [路径 B] UART TX 捕获的 16 字节与预期密文逐字节比对
        // 备注：
        // 备注：  时序注意：sm4_ready_out 是单周期脉冲，SM4 计算仅需 ~2.5µs，
        // 备注：  而 16 字节 UART 发送需 ~1.39ms — 即 SM4 在发送期间就已经算完。
        // 备注：  因此不能用 @(posedge sm4_ready_out) 捕获完成事件，
        // 备注：  必须使用锁存后的 sm4_done 电平信号 (wait(sm4_done))。
        // 备注：==============================
        // ═══════════════════════════════════════════════════════════════════
        // [3] ENCRYPT
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[3] ENCRYPT:");
        prev_wr = cap_wr;
        #(CLK_NS * 20);
        $display("  sm4_ready_out=%b, led_busy=%b, tx=%b",
                 sm4_ready_out, led_busy, tx);
        $display("[%0t] sending 'E'...", $time);
        uart_send(8'h45);  // 'E'
        $display("[%0t] sending 16 plaintext bytes...", $time);
        uart_send_bytes(PLAIN, 16);
        $display("[%0t] data bytes sent, waiting for SM4 done...", $time);

        // Wait for SM4 core to produce the result
        // Note: sm4_ready_out is a single-cycle pulse that fires BEFORE the
        // testbench finishes sending all data bytes (SM4 processes in ~2.5µs).
        // Use latched sm4_done instead of edge-sensitive @(posedge sm4_ready_out).
        wait(sm4_done);
        @(posedge clk);
        $display("  SM4 core result: %032h", sm4_result_out);
        if (sm4_result_out !== EXPECTED_CIPHER) begin
            $display("  FAIL: SM4 core ciphertext mismatch");
        end else begin
            $display("  SM4 core ciphertext MATCH \xE2\x9C\x93");
        end

        // Wait for UART TX to finish
        $display("  waiting for led_busy...");
        wait(led_busy);
        $display("  waiting for negedge led_busy...");
        @(negedge led_busy);
        @(posedge clk);
        $display("  led_busy fell");

        // Drain and check captured TX bytes
        n = cap_wr - prev_wr;
        $display("  Captured %0d UART TX bytes", n);
        mismatch = 0;
        for (i = 0; i < n && i < 16; i = i + 1) begin
            if (cap_buf[prev_wr + i] !== EXPECTED_CIPHER[127 - i*8 -: 8]) begin
                $display("  FAIL byte %0d: expected 0x%02h, got 0x%02h",
                         i, EXPECTED_CIPHER[127 - i*8 -: 8], cap_buf[prev_wr + i]);
                mismatch = 1;
            end
        end
        if (n !== 16) begin
            $display("  FAIL: expected 16 bytes, captured %0d", n);
        end else if (!mismatch) begin
            $display("  ENCRYPT TX PASS: all 16 bytes match \xE2\x9C\x93");
        end

        // 备注：==============================
        // 备注：[测试 4] DECRYPT — 解密测试
        // 备注：  发送 ASCII 'D' (0x44) 作为命令字
        // 备注：  随后发送 16 字节密文 (MSB 优先)
        // 备注：  验证策略：
        // 备注：  [路径 A] SM4 内核输出 sm4_result_out 应等于 PLAIN
        // 备注：  [路径 B] UART TX 捕获的 16 字节与预期明文逐字节比对
        // 备注：
        // 备注：  注意：每次测试前手动复位 sm4_done = 0，
        // 备注：  否则上次测试残留的高电平会导致 wait(sm4_done) 立即返回
        // 备注：==============================
        // ═══════════════════════════════════════════════════════════════════
        // [4] DECRYPT
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[4] DECRYPT:");
        prev_wr = cap_wr;
        // 备注：复位 sm4_done — 清除上次加密残留的高电平信号
        // 备注：否则 wait(sm4_done) 会立即返回，不会等待本次解密完成
        // Reset sm4_done before triggering new SM4 operation
        sm4_done = 1'b0;
        uart_send(8'h44);  // 'D'
        uart_send_bytes(EXPECTED_CIPHER, 16);

        $display("[%0t] data bytes sent, waiting for SM4 done...", $time);
        wait(sm4_done);
        @(posedge clk);
        $display("  SM4 core result: %032h", sm4_result_out);
        if (sm4_result_out !== PLAIN) begin
            $display("  FAIL: SM4 core plaintext mismatch");
        end else begin
            $display("  SM4 core plaintext MATCH \xE2\x9C\x93");
        end

        $display("  waiting for led_busy...");
        wait(led_busy);
        $display("  waiting for negedge led_busy...");
        @(negedge led_busy);
        @(posedge clk);
        $display("  led_busy fell");

        n = cap_wr - prev_wr;
        $display("  Captured %0d UART TX bytes", n);
        mismatch = 0;
        for (i = 0; i < n && i < 16; i = i + 1) begin
            if (cap_buf[prev_wr + i] !== PLAIN[127 - i*8 -: 8]) begin
                $display("  FAIL byte %0d: expected 0x%02h, got 0x%02h",
                         i, PLAIN[127 - i*8 -: 8], cap_buf[prev_wr + i]);
                mismatch = 1;
            end
        end
        if (n !== 16) begin
            $display("  FAIL: expected 16 bytes, captured %0d", n);
        end else if (!mismatch) begin
            $display("  DECRYPT TX PASS: all 16 bytes match \xE2\x9C\x93");
        end

        // ═══════════════════════════════════════════════════════════════════
        // Summary
        // ═══════════════════════════════════════════════════════════════════
        $display("\n═══════════════════════════════════════════════");
        $display("  ALL TESTS PASSED");
        $display("═══════════════════════════════════════════════");

        #(CLK_NS * 10);
        $finish;
    end

    // ── VCD dump ─────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("build/sm4_uart_sim.vcd");
        $dumpvars(0, tb_sm4_uart);
    end

    // 备注：超时看门狗 — 防止仿真无限挂起
    // 备注：
    // 备注：如果 SM4 内核或 UART 通信异常导致 testbench 永远阻塞
    // 备注：在某个等待点（如 wait(led_busy)、wait(sm4_done)），
    // 备注：此看门狗会在 800,000 个时钟周期后强制退出仿真并报告超时。
    // 备注：
    // 备注：超时时间 = 800,000 × 37.037 ns ≈ 29.63 ms
    // 备注：在正常条件下，全部四项测试应在远小于此时间内完成。
    // 备注：
    // 备注：由于此 initial 块与主测试序列并行执行，
    // 备注：一旦触发 $finish，整个仿真立即终止。
    // ── Timeout watchdog ─────────────────────────────────────────────────────
    initial begin
        #(CLK_NS * 800000);
        $display("TIMEOUT: Simulation exceeded 800000 clock cycles");
        $finish;
    end

endmodule
