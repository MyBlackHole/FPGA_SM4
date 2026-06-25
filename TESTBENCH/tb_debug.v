`timescale 1ns / 100ps

// Debug testbench: demonstrates SM4 encrypt/decrypt with correct timing
// Key fix: keep enable_key_exp_in HIGH throughout so key_exp_ready_out stays HIGH,
// allowing encdec FSM to transition WAITING_FOR_KEY -> ENCRYPTION.
// 备注：文件说明：SM4 调试用 testbench
// 备注：
// 备注：用途：演示正确的 SM4 加密/解密时序，验证 enable_key_exp_in 的时序要求
// 备注：
// 备注：测试流程：
// 备注：  阶段 1: 密钥扩展（加密模式） → 阶段 2: 加密 → 阶段 3: 解密
// 备注：
// 备注：关键发现（已修复）：
// 备注：  enable_key_exp_in 在加密/解密阶段必须保持高电平！
// 备注：  如果 enable_key_exp_in 拉低，key_exp_ready_out 也会变低，
// 备注：  导致 encdec FSM 在 WAITING_FOR_KEY 状态卡住，无法进入 ENCRYPTION。
// 备注：  因此解密前需先切换 enable_key_exp_in=0 清除 key_exp_ready_out，
// 备注：  再重新置 1 以重新启动密钥扩展。
module tb_debug();
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

    // 备注：SM4 标准测试向量
    // 备注：KEY       = 0123456789abcdeffedcba9876543210 （128 位）
    // 备注：PLAINTEXT = 0123456789abcdeffedcba9876543210
    // 备注：EXPECTED  = 681edf34d206965e86b3e94f536e4246
    localparam KEY       = 128'h0123456789abcdeffedcba9876543210;
    localparam PLAINTEXT = 128'h0123456789abcdeffedcba9876543210;
    localparam EXPECTED  = 128'h681edf34d206965e86b3e94f536e4246;

    // 备注：时钟生成：周期 6ns（约 166MHz），用于仿真验证
    always #3 clk = ~clk;

    // 备注：精确延迟辅助任务 — 等待 n 个时钟上升沿
    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    // 备注：主测试序列：依次执行密钥扩展（加密）→ 加密 → 密钥扩展（解密）→ 解密
    initial begin
        $display("=== SM4 Debug Testbench ===");
        $dumpfile("build/sm4_debug.vcd");
        $dumpvars(0, tb_debug);

        // === Reset ===
        #100 reset_n = 1;
        #100 sm4_enable_in = 1;

        // ==========================================
        // 阶段 1：密钥扩展（加密模式）
        // ==========================================
        // 备注：时序要求：
        // 备注：  - enable_key_exp_in=1 使能密钥扩展模块
        // 备注：  - user_key_valid_in 只需脉冲一个时钟周期
        // 备注：  - 密钥扩展固定需要 34 个周期（32 轮 + 2 级流水线延迟）
        // === PHASE 1: Key Expansion (encrypt mode) ===
        // Keep enable_key_exp_in HIGH throughout encryption phase!
        @(negedge clk);
        encdec_sel_in = 1'b0;       // encrypt
        enable_key_exp_in = 1'b1;
        user_key_valid_in = 1'b1;
        user_key_in = KEY;

        @(posedge clk);
        $display("Key expansion start...");

        // Key expansion takes 32 cycles + 2 setup = 34 cycles
        wait_cycles(34);
        $display("key_exp_ready_out = %b", key_exp_ready_out);

        // ==========================================
        // 阶段 2：加密
        // ==========================================
        // 备注：FSM 状态转移：IDLE → WAITING_FOR_KEY → ENCRYPTION
        // 备注：关键时序要求：
        // 备注：  1. enable_key_exp_in 保持 HIGH（key_exp_ready_out 不变低）
        // 备注：  2. user_key_valid_in 拉低（密钥已加载完成）
        // 备注：  3. encdec_enable_in=1 启动加密 FSM
        // 备注：  4. 等待 3 个周期完成 FSM 状态转移
        // === PHASE 2: Encryption ===
        // enable_key_exp_in stays HIGH — key_exp_ready_out remains HIGH.
        // user_key_valid_in goes LOW after key loaded.
        @(negedge clk);
        user_key_valid_in = 1'b0;   // done loading key
        encdec_enable_in = 1'b1;    // enable encryption engine

        // 备注：FSM 状态转移需要 3 个周期
        // 备注：  IDLE（1周期）→ WAITING_FOR_KEY（1周期）→ ENCRYPTION（1周期）
        // FSM: IDLE -> WAITING_FOR_KEY (1 cycle) -> ENCRYPTION (1 cycle)
        wait_cycles(3);

        // 备注：valid_in 必须在连续 2 个 posedge clk 保持高电平
        // 备注：确保 reg_tmp 正确加载起始移位位 '1'
        // 备注：过早拉低 valid_in 会导致 reg_tmp 未载入起始位，32 轮移位无法启动
        // FSM now in ENCRYPTION — inject data
        @(negedge clk);
        valid_in = 1'b1;
        data_in = PLAINTEXT;

        @(posedge clk);
        $display("Encryption start... valid_in=%b data=%h", valid_in, data_in);

        // 备注：保持 valid_in 高电平跨越 2 个 posedge clk
        // 备注：第 1 个 posedge：reg_tmp 加载移位起始位 '1'
        // 备注：第 2 个 posedge：reg_tmp 开始右移，后续移位自动进行
        // Keep valid_in HIGH across 2 posedges to ensure reg_tmp loads the '1'
        @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        valid_in = 1'b0;

        // Wait for the '1' to ripple through all 32 bits of reg_tmp
        wait(ready_out);
        $display("Encryption done! Result=%h", result_out);
        if (result_out == EXPECTED)
            $display("*** ENCRYPTION CORRECT! ***");
        else
            $display("*** ENCRYPTION WRONG! Expected=%h ***", EXPECTED);

        // ==========================================
        // 阶段 3：解密
        // ==========================================
        // 备注：解密前必须重新做密钥扩展（解密模式），因为解密使用逆序轮密钥。
        // 备注：
        // 备注：步骤：
        // 备注：  1. 关闭 encdec_enable_in=0，让 FSM 回到 IDLE
        // 备注：  2. 切换 enable_key_exp_in=0 以清除 key_exp_ready_out
        // 备注：     （内部逻辑：~enable_key_exp_in && reg_enable_key_exp 触发清除）
        // 备注：  3. 设置 encdec_sel_in=1（解密模式）
        // 备注：  4. 等待 3 个周期使 key_exp_ready_out 变低
        // 备注：  5. enable_key_exp_in=1 重新启动密钥扩展
        // 备注：  6. 脉冲 user_key_valid_in 加载密钥
        // 备注：  7. 等待 34 个周期完成解密密钥扩展
        // 备注：
        // 备注：解密完成后验证 result_out == PLAINTEXT
        // === PHASE 3: Decryption ===
        // Need to re-run key expansion in decrypt mode
        // Step 1: disable encdec
        @(negedge clk);
        encdec_enable_in = 1'b0;

        wait_cycles(2);  // let encdec FSM return to IDLE

        // Step 2: restart key expansion by toggling enable_key_exp_in
        // This clears key_exp_finished_out via the clearing logic:
        //   ~enable_key_exp_in && reg_enable_key_exp
        @(negedge clk);
        enable_key_exp_in = 1'b0;   // trigger clear of key_exp_ready_out
        encdec_sel_in = 1'b1;       // decrypt mode

        wait_cycles(3);             // wait for key_exp_ready_out to clear

        // Step 3: start key expansion for decryption
        @(negedge clk);
        enable_key_exp_in = 1'b1;   // re-enable key expansion
        user_key_valid_in = 1'b1;   // pulse key valid
        user_key_in = KEY;

        @(posedge clk);
        $display("Decrypt key expansion start...");
        wait_cycles(34);
        $display("Decrypt key_exp_ready_out = %b", key_exp_ready_out);

        // Step 4: enable decryption
        @(negedge clk);
        user_key_valid_in = 1'b0;
        encdec_enable_in = 1'b1;

        // 备注：等待 FSM 状态转移：IDLE → WAITING_FOR_KEY → ENCRYPTION（3 周期）
        wait_cycles(3);              // IDLE -> WAITING_FOR_KEY -> ENCRYPTION

        @(negedge clk);
        valid_in = 1'b1;
        data_in = EXPECTED;          // feed ciphertext

        @(posedge clk);
        $display("Decryption start...");
        @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        valid_in = 1'b0;

        wait(ready_out);
        $display("Decryption done! Result=%h", result_out);
        if (result_out == PLAINTEXT)
            $display("*** DECRYPTION CORRECT! ***");
        else
            $display("*** DECRYPTION WRONG! Expected=%h ***", PLAINTEXT);

        #500;
        $display("=== SIMULATION DONE ===");
        $finish;
    end

    // 备注：实例化 SM4 顶层模块，连接所有测试激励信号
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
