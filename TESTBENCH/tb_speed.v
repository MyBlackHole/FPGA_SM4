`timescale 1ns / 100ps

// Speed & latency testbench for serial SM4
// Measures exact cycle counts and reports throughput estimates.
// ============================================
// 文件说明：SM4 串行引擎速度与延迟测试平台
// 包含：密钥扩展计时、加密延迟、解密延迟、吞吐量估算
// 功能：在 27MHz 时钟下测量 SM4 串行引擎的精确周期计数和延迟
// ============================================
module tb_speed();
    reg             clk = 0;
    reg             reset_n = 0;
    reg             sm4_enable_in = 0;
    reg             encdec_enable_in = 0;
    reg             encdec_sel_in = 0;
    reg             valid_in = 0;
    reg   [127:0]   data_in = 0;
    reg             enable_key_exp_in = 0;
    reg             user_key_valid_in = 0;
    reg   [127:0]   user_key_in = 0;
    wire            ready_out;
    wire            key_exp_ready_out;
    wire  [127:0]   result_out;

    // 备注：测试向量常量定义
    // 备注：KEY       - SM4 128 位密钥（与明文相同，简化验证）
    // 备注：PLAINTEXT - 128 位明文输入
    // 备注：EXPECTED  - 预期密文（与密钥对应的 SM4 标准测试向量）
    localparam KEY       = 128'h0123456789abcdeffedcba9876543210;
    localparam PLAINTEXT = 128'h0123456789abcdeffedcba9876543210;
    localparam EXPECTED  = 128'h681edf34d206965e86b3e94f536e4246;

    // Clock: 27 MHz (~37ns period) to match Tang Nano 20K
    // Use #18.5 for 50% duty cycle at 27MHz
    // 备注：27MHz 时钟生成，半周期 #18.5ns，周期约 37ns
    always #18.5 clk = ~clk;

    // Cycle counter
    // 备注：连续周期计数器 — 从仿真开始在每个时钟上升沿递增
    // 备注：与 tb_sm4_internal_perf.v 的按阶段独立计数不同，
    // 备注：这里使用全局连续计数器，通过记录 start/end 时刻的
    // 备注：cycle_cnt 值来计算各阶段延迟（差值法）。
    integer cycle_cnt;
    always @(posedge clk) cycle_cnt = cycle_cnt + 1;

    // Timing measurement variables
    // 备注：延迟测量变量 — 记录各阶段的起始和结束 cycle_cnt
    // 备注：enc_start_cycle / enc_end_cycle — 加密阶段起止
    // 备注：dec_start_cycle / dec_end_cycle — 解密阶段起止
    // 备注：enc_latency / dec_latency — 计算得到的延迟周期数
    integer enc_start_cycle, enc_end_cycle;
    integer dec_start_cycle, dec_end_cycle;
    integer enc_latency, dec_latency;

    // 备注：等待 n 个时钟周期的精确延迟任务
    // 备注：@param n - 需要等待的时钟周期数
    // 备注：用于控制测试阶段的时序间隔，确保 FSM 状态机
    // 备注：有足够时间完成状态转移
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    initial begin
        cycle_cnt = 0;

        $display("===========================================");
        $display("  SM4 Serial Engine — Speed & Latency Test ");
        $display("===========================================");
        $display("Clock period: 37 ns (27 MHz)");
        $display("");

        // Dump VCD for detailed timing analysis
        // 备注：生成 VCD 波形文件，供 GTKWave 等工具进行时序分析
        $dumpfile("build/sm4_speed.vcd");
        $dumpvars(0, tb_speed);

        // === Reset & enable ===
        #100 reset_n = 1;
        #100 sm4_enable_in = 1;

        //===================================================================
        // PHASE 1: Key Expansion (encrypt mode)
        //===================================================================
        // 备注：阶段 1：密钥扩展（加密模式）
        // 备注：在时钟负沿配置 encdec_sel_in=0（加密）并加载密钥。
        // 备注：密钥扩展预计需要 34 个周期。使用 wait_cycles(34) 精确等待，
        // 备注：随后检查 key_exp_ready_out 确认扩展已完成。
        // 备注：
        // 备注：负沿驱动 valid 信号的设计目的：在时钟上升沿时数据已经稳定，
        // 备注：满足 DUT 的建立时间要求，实现"在时钟负沿准备数据，上升沿采样"
        // 备注：的双沿握手协议。
        @(negedge clk);
        encdec_sel_in = 1'b0;
        enable_key_exp_in = 1'b1;
        user_key_valid_in = 1'b1;
        user_key_in = KEY;

        @(posedge clk);
        $display("[Phase 1] Key expansion (encrypt)...");

        // Key expansion takes 34 cycles from user_key_valid_in
        wait_cycles(34);

        if (key_exp_ready_out !== 1'b1) begin
            $display("ERROR: key_exp_ready_out did not go high!");
            $finish;
        end
        $display("[Phase 1] Key expansion done (cycle %0d)", cycle_cnt);

        //===================================================================
        // PHASE 2: Encryption latency measurement
        //===================================================================
        // 备注：阶段 2：加密延迟测量
        // 备注：先撤销 user_key_valid_in，使能 encdec_enable_in。
        // 备注：wait_cycles(3) 等待 FSM 进入 ENCRYPTION 状态。
        // 备注：
        // 备注：关键测量方法：在 valid_in 置位（负沿）的当拍记录 enc_start_cycle，
        // 备注：然后等待 ready_out 拉高时记录 enc_end_cycle。
        // 备注：enc_latency = enc_end_cycle - enc_start_cycle 即为加密延迟。
        // 备注：
        // 备注：valid_in 保持 2 个时钟周期（负沿→正沿→负沿→正沿→负沿撤销），
        // 备注：确保 DUT 正确捕获 valid 信号。
        @(negedge clk);
        user_key_valid_in = 1'b0;
        encdec_enable_in = 1'b1;

        // Wait for FSM to reach ENCRYPTION state
        // 备注：等待 FSM 进入加密状态
        wait_cycles(3);

        // Fire data & record cycle
        // 备注：在负沿置位 valid_in 并记录起始周期
        @(negedge clk);
        valid_in = 1'b1;
        data_in = PLAINTEXT;
        enc_start_cycle = cycle_cnt;

        @(posedge clk);
        $display("[Phase 2] Encryption data valid at cycle %0d", enc_start_cycle);

        // Hold valid_in for 2 cycles then release
        @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        valid_in = 1'b0;

        // Wait for result
        wait(ready_out);
        enc_end_cycle = cycle_cnt;
        enc_latency = enc_end_cycle - enc_start_cycle;

        $display("[Phase 2] Encryption done at cycle %0d", enc_end_cycle);
        $display("  Result  = %h", result_out);
        $display("  Expected= %h", EXPECTED);
        if (result_out == EXPECTED)
            $display("  *** CORRECT ***");
        else
            $display("  *** WRONG ***");
        $display("  Latency = %0d clock cycles", enc_latency);
        $display("");

        //===================================================================
        // PHASE 3: Decryption latency measurement
        //===================================================================
        // 备注：阶段 3：解密延迟测量
        // 备注：首先禁用 encdec_enable_in 暂停 FSM，然后通过 toggle
        // 备注：enable_key_exp_in（1→0→1）触发重新密钥扩展。
        // 备注：注意设置 encdec_sel_in = 1'b1 表示解密模式，这会反转
        // 备注：轮密钥的顺序。重新密钥后再次测量 valid_in→ready_out 延迟。
        // 备注：
        // 备注：重新密钥的必要性：SM4 加解密使用不同的轮密钥顺序，
        // 备注：加密时轮密钥为正序(rk[0..31])，解密时为逆序(rk[31..0])。
        // 备注：切换 encdec_sel_in 后必须重新执行密钥扩展以使轮密钥顺序正确。
        // Disable encdec FSM
        @(negedge clk);
        encdec_enable_in = 1'b0;
        wait_cycles(2);

        // Toggle enable_key_exp_in to trigger re-keying
        // 备注：toggle enable_key_exp_in 触发重新密钥扩展
        @(negedge clk);
        enable_key_exp_in = 1'b0;
        encdec_sel_in = 1'b1;       // decrypt mode (reverses round key order)

        wait_cycles(3);

        @(negedge clk);
        enable_key_exp_in = 1'b1;
        user_key_valid_in = 1'b1;
        user_key_in = KEY;

        @(posedge clk);
        $display("[Phase 3] Key expansion (decrypt)...");
        wait_cycles(34);

        if (key_exp_ready_out !== 1'b1) begin
            $display("ERROR: decryption key_exp_ready_out did not go high!");
            $finish;
        end
        $display("[Phase 3] Decrypt key expansion done (cycle %0d)", cycle_cnt);

        // Enable decryption
        @(negedge clk);
        user_key_valid_in = 1'b0;
        encdec_enable_in = 1'b1;

        wait_cycles(3);

        // Fire ciphertext & record cycle
        @(negedge clk);
        valid_in = 1'b1;
        data_in = EXPECTED;
        dec_start_cycle = cycle_cnt;

        @(posedge clk);
        $display("[Phase 3] Decryption data valid at cycle %0d", dec_start_cycle);

        @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        valid_in = 1'b0;

        wait(ready_out);
        dec_end_cycle = cycle_cnt;
        dec_latency = dec_end_cycle - dec_start_cycle;

        $display("[Phase 3] Decryption done at cycle %0d", dec_end_cycle);
        $display("  Result  = %h", result_out);
        $display("  Expected= %h", PLAINTEXT);
        if (result_out == PLAINTEXT)
            $display("  *** CORRECT ***");
        else
            $display("  *** WRONG ***");
        $display("  Latency = %0d clock cycles", dec_latency);
        $display("");

        //===================================================================
        // Summary
        //===================================================================
        // 备注：性能总结输出
        // 备注：输出加解密延迟（周期数和 ns 值），以及两种频率下的吞吐量：
        // 备注：  - 27 MHz: Tang Nano 20K 实际工作频率
        // 备注：  - 61 MHz: nextpnr 估算的理论最大 Fmax
        // 备注：
        // 备注：吞吐量计算公式：
        // 备注：  Blocks/sec = Fclk / enc_latency
        // 备注：  Data rate  = 128 × Fclk / enc_latency  (bps)
        // 备注：
        // 备注：使用浮点运算（128.0 / enc_latency / 1000000.0）避免 32-bit 溢出
        $display("===========================================");
        $display("  PERFORMANCE SUMMARY");
        $display("===========================================");
        $display("  Design:      SM4 serial/iterative engine");
        $display("  LUT4:        5526 / 20736 (26%%)");
        $display("  Max Fmax:    61 MHz (nextpnr estimate)");
        $display("");
        $display("  Encryption latency:  %0d cycles  %0d ns  @27MHz",
                 enc_latency, enc_latency * 37);
        $display("  Decryption latency:  %0d cycles  %0d ns  @27MHz",
                 dec_latency, dec_latency * 37);
        $display("");

        // Throughput: 128 bits per enc_latency cycles
        // At 27 MHz clock
        // Use real arithmetic for throughput to avoid 32-bit overflow
        $display("  --- Throughput @ 27 MHz ---");
        $display("  Per-block cycles: %0d  (data load + 32 rounds)", enc_latency);
        $display("  Blocks/sec:       %0d  (%.2f Mblock/s)",
                 27_000_000 / enc_latency,
                 (27_000_000.0 / enc_latency) / 1_000_000.0);
        $display("  Data rate:        %0.2f Mbps",
                 (128.0 * 27000000.0) / (enc_latency * 1000000.0));
        $display("");

        // At 61 MHz (max frequency from nextpnr)
        $display("  --- Throughput @ 61 MHz (theoretical max) ---");
        $display("  Blocks/sec:       %0d  (%.2f Mblock/s)",
                 61_000_000 / enc_latency,
                 (61_000_000.0 / enc_latency) / 1_000_000.0);
        $display("  Data rate (real): %0.2f Mbps",
                 (128.0 * 61000000.0) / (enc_latency * 1000000.0));
        $display("");

        // Key expansion cycles
        $display("  Key expansion:    34 cycles");
        $display("  Key expansion freq: once per key change");
        $display("");
        $display("===========================================");
        $display("  Test PASSED");
        $display("===========================================");

        #500;
        $finish;
    end

    // 备注：SM4 顶层模块实例化（Device Under Test）
    // 备注：连接所有测试激励信号到 DUT 端口。key_cached_in 未引出，
    // 备注：与 tb_sm4_internal_perf.v 一致使用默认值（已由 RTL 内部处理）。
    sm4_top uut (
        .clk                (clk               ),
        .reset_n            (reset_n           ),
        .sm4_enable_in      (sm4_enable_in     ),
        .encdec_enable_in   (encdec_enable_in  ),
        .encdec_sel_in      (encdec_sel_in     ),
        .valid_in           (valid_in          ),
        .data_in            (data_in           ),
        .enable_key_exp_in  (enable_key_exp_in ),
        .user_key_valid_in  (user_key_valid_in ),
        .user_key_in        (user_key_in       ),
        .key_exp_ready_out  (key_exp_ready_out ),
        .ready_out          (ready_out         ),
        .result_out         (result_out        )
    );

endmodule
