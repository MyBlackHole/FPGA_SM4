//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Raymond Rui Chen, raymond.rui.chen@qq.com
// 
// Create Date: 2018/03/10 12:06:49
// Design Name: 
// Module Name: sm4_top_wrapper
// Project Name: FPGA_SM4
// Target Devices: Tang Nano 20K (GW2AR-LV18QN88C8/I7)
// Description: 
//   Top-level wrapper for SM4 encryption/decryption core.
//   Maps the SM4 core to Tang Nano 20K onboard resources:
//   - 27MHz clock (PIN4)
//   - S2 button as reset (PIN87, active low)
//   - S1 button to trigger encrypt/decrypt (PIN88, active low)
//   - 6 LEDs for status display (PIN15-20, active low)
// 
//   Test vectors (from testbench):
//     Key:      128'h0123456789abcdeffedcba9876543210
//     Plain:    128'h0123456789abcdeffedcba9876543210
//     Cipher:   128'h681edf34d206965e86b3e94f536e4246
// 
//   LED status:
//     [0] SM4 enabled / busy
//     [1] Key expansion complete
//     [2] Encryption done
//     [3] Encryption result = expected (correct)
//     [4] Decryption done
//     [5] Decryption result = original (correct)
// ============================================
// 备注：Tang Nano 20K 开发板 SM4 测试顶层
// 备注：
// 备注：用途: 在 FPGA 开发板上演示 SM4 加密/解密并验证正确性
// 备注：
// 备注：硬件映射:
// 备注：  clk   (PIN4)    — 27MHz 系统时钟
// 备注：  rst_n (PIN87)   — S2 按键复位（低有效）
// 备注：  btn_s1(PIN88)   — S1 按键触发（低有效）
// 备注：  led[5:0] (PIN15-20) — 6 个 LED 状态灯
// 备注：
// 备注：测试流程（按 S1 按键触发）:
// 备注：  KEY_EXPAND → WAIT_KEY → LOAD_DATA →
// 备注：  ENCRYPT_WAIT → CHECK_ENC → DECRYPT_KEY →
// 备注：  WAIT_DEC_KEY → LOAD_CIPHER → DECRYPT_WAIT →
// 备注：  CHECK_DEC → DONE
// 备注：
// 备注：LED 显示:
// 备注：  [0] SM4 工作中
// 备注：  [1] 密钥扩展完成
// 备注：  [2] 加密完成
// 备注：  [3] 加密结果正确
// 备注：  [4] 解密完成
// 备注：  [5] 解密结果正确
// 备注：
// 备注：测试向量:
// 备注：  密钥:    0123456789abcdeffedcba9876543210
// 备注：  明文:    0123456789abcdeffedcba9876543210
// 备注：  期望密文: 681edf34d206965e86b3e94f536e4246
// 备注：  解密后应恢复为原始明文
// ============================================
////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 100ps

module sm4_top_wrapper (
    input  wire       clk,        // 27MHz main clock (PIN4)
    input  wire       rst_n,      // Reset button S2 (PIN87), active low
    input  wire       btn_s1,     // Start button S1 (PIN88), active low
    output wire [5:0] led         // 6 LEDs (PIN15-20), active low
);

    //-----------------------------------------------------------------
    // Test vectors (from original testbench)
    //-----------------------------------------------------------------
    localparam [127:0] TEST_KEY       = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] TEST_PLAINTEXT = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] EXPECTED_CIPHER = 128'h681edf34d206965e86b3e94f536e4246;

    //-----------------------------------------------------------------
    // SM4 core interface signals
    //-----------------------------------------------------------------
    wire        sm4_enable_in;
    wire        encdec_enable_in;
    reg         encdec_sel_in;
    reg         valid_in;
    reg  [127:0] data_in;
    reg         enable_key_exp_in;
    reg         user_key_valid_in;
    reg  [127:0] user_key_in;
    wire        key_exp_ready_out;
    wire        ready_out;
    wire [127:0] result_out;

    //-----------------------------------------------------------------
    // Internal registers
    //-----------------------------------------------------------------
    reg [127:0] stored_result;
    reg         enc_result_correct;
    reg         dec_result_correct;

    //-----------------------------------------------------------------
    // Button debounce / edge detection
    //-----------------------------------------------------------------
    // 备注：S1 按键同步消抖及下降沿检测
    // 备注：btn_s1_sync: 三级移位寄存器，将异步按键信号同步到时钟域，同时起消抖作用
    // 备注：  {btn_s1_sync[1:0], btn_s1} — 每个时钟上升沿移入当前按键值
    // 备注：  btn_s1_sync[2:1] == 2'b10 — 检测到下降沿（按键按下，低有效）
    // 备注：btn_s1_falling: 单周期脉冲信号，驱动 FSM 状态切换
    reg [2:0] btn_s1_sync;
    reg       btn_s1_falling;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_s1_sync <= 3'b111;
        end else begin
            btn_s1_sync <= {btn_s1_sync[1:0], btn_s1};
        end
    end

    // Falling edge: button pressed (active low)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            btn_s1_falling <= 1'b0;
        else if (btn_s1_sync[2:1] == 2'b10)
            btn_s1_falling <= 1'b1;
        else
            btn_s1_falling <= 1'b0;
    end

    //-----------------------------------------------------------------
    // State machine
    //-----------------------------------------------------------------
    // 备注：FSM 状态机 — 完整加密/解密测试流程（12 个状态）
    // 备注：
    // 备注：  状态转移:
    // 备注：  ┌─────────────────────────────────────────────────────┐
    // 备注：  │  IDLE ──(按键按下)──▶ KEY_EXPAND ──▶ WAIT_KEY      │
    // 备注：  │    ↑                                │ 密钥扩展完成   │
    // 备注：  │    │                                ▼               │
    // 备注：  │    │                              LOAD_DATA ──▶    │
    // 备注：  │    │                              ENCRYPT_WAIT ──▶  │
    // 备注：  │  DONE ◀── CHECK_DEC ◀── DECRYPT_WAIT               │
    // 备注：  │    ↑           ▲         ▲                           │
    // 备注：  │    │           │   解密等待完成                       │
    // 备注：  │  CHECK_ENC ──▶ DECRYPT_KEY ──▶ WAIT_DEC_KEY        │
    // 备注：  │    ▲                              │ 密钥扩展完成     │
    // 备注：  │    │                              ▼                  │
    // 备注：  │  加密完成                      LOAD_CIPHER ──▶     │
    // 备注：  │                                              DECRYPT_WAIT
    // 备注：  └─────────────────────────────────────────────────────┘
    // 备注：
    // 备注：图例：──▶ 无条件转移，─(条件)──▶ 条件转移, ◀── 返回
    // 备注：
    // 备注：IDLE:       等待 S1 按键触发
    // 备注：KEY_EXPAND: 拉高 enable_key_exp, 启动密钥扩展
    // 备注：WAIT_KEY:   等待 key_exp_ready_out 指示密钥扩展完成
    // 备注：LOAD_DATA:  加载明文到 SM4 数据输入
    // 备注：ENCRYPT_WAIT:等待 ready_out 指示加密完成
    // 备注：CHECK_ENC:  捕获加密结果并与 EXPECTED_CIPHER 比对
    // 备注：DECRYPT_KEY:切换为解密模式，再次启动密钥扩展
    // 备注：WAIT_DEC_KEY:等待解密密钥扩展完成
    // 备注：LOAD_CIPHER: 加载密文到 SM4 数据输入
    // 备注：DECRYPT_WAIT:等待 ready_out 指示解密完成
    // 备注：CHECK_DEC:  捕获解密结果并与 TEST_PLAINTEXT 比对
    // 备注：DONE:       测试完成，等待按键回到 IDLE
    localparam IDLE         = 4'd0;
    localparam KEY_EXPAND   = 4'd1;
    localparam WAIT_KEY     = 4'd2;
    localparam LOAD_DATA    = 4'd3;
    localparam ENCRYPT_WAIT = 4'd4;
    localparam CHECK_ENC    = 4'd5;
    localparam DECRYPT_KEY  = 4'd6;
    localparam WAIT_DEC_KEY = 4'd7;
    localparam LOAD_CIPHER  = 4'd8;
    localparam DECRYPT_WAIT = 4'd9;
    localparam CHECK_DEC    = 4'd10;
    localparam DONE         = 4'd11;

    reg [3:0] state, next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (btn_s1_falling)
                    next_state = KEY_EXPAND;
            end

            KEY_EXPAND: begin
                next_state = WAIT_KEY;
            end

            WAIT_KEY: begin
                if (key_exp_ready_out)
                    next_state = LOAD_DATA;
            end

            LOAD_DATA: begin
                next_state = ENCRYPT_WAIT;
            end

            ENCRYPT_WAIT: begin
                if (ready_out)
                    next_state = CHECK_ENC;
            end

            CHECK_ENC: begin
                next_state = DECRYPT_KEY;
            end

            DECRYPT_KEY: begin
                next_state = WAIT_DEC_KEY;
            end

            WAIT_DEC_KEY: begin
                if (key_exp_ready_out)
                    next_state = LOAD_CIPHER;
            end

            LOAD_CIPHER: begin
                next_state = DECRYPT_WAIT;
            end

            DECRYPT_WAIT: begin
                if (ready_out)
                    next_state = CHECK_DEC;
            end

            CHECK_DEC: begin
                next_state = DONE;
            end

            DONE: begin
                if (btn_s1_falling)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    //-----------------------------------------------------------------
    // SM4 core control signals
    //-----------------------------------------------------------------
    // 备注：组合逻辑 — 根据当前状态驱动 SM4 核心的各控制信号
    // 备注：
    // 备注：  sm4_enable_in: 非 IDLE 状态时使能 SM4 核心
    // 备注：  enable_key_exp: KEY_EXPAND / DECRYPT_KEY 时拉高
    // 备注：  user_key_valid: 密钥扩展同时加载用户密钥
    // 备注：  encdec_sel:    加密=0, 解密=1（LOAD_CIPHER/DECRYPT_KEY 时切换）
    // 备注：  valid_in:      LOAD_DATA/LOAD_CIPHER 时拉高，加载待处理数据
    // 备注：  encdec_enable: 加密/解密运算使能，覆盖 ENCRYPT_WAIT/DECRYPT_WAIT
    assign sm4_enable_in = (state != IDLE);

    always @(*) begin
        // Defaults
        enable_key_exp_in = 1'b0;
        user_key_valid_in = 1'b0;
        user_key_in       = TEST_KEY;
        encdec_sel_in     = 1'b0;  // 0=encrypt, 1=decrypt
        valid_in          = 1'b0;
        data_in           = TEST_PLAINTEXT;

        case (state)
            KEY_EXPAND, DECRYPT_KEY: begin
                enable_key_exp_in = 1'b1;
                user_key_valid_in = 1'b1;
                user_key_in       = TEST_KEY;
            end

            LOAD_DATA: begin
                valid_in = 1'b1;
                data_in  = TEST_PLAINTEXT;
            end

            DECRYPT_KEY: begin
                encdec_sel_in = 1'b1;    // decrypt mode
            end

            LOAD_CIPHER: begin
                encdec_sel_in = 1'b1;    // decrypt mode
                valid_in      = 1'b1;
                data_in       = EXPECTED_CIPHER;
            end
        endcase
    end

    assign encdec_enable_in = (state == LOAD_DATA || state == ENCRYPT_WAIT ||
                               state == LOAD_CIPHER || state == DECRYPT_WAIT);

    //-----------------------------------------------------------------
    // Capture result
    //-----------------------------------------------------------------
    // 备注：加密与解密结果的捕获和比对验证
    // 备注：  CHECK_ENC: ready_out 有效时锁存 result_out
    // 备注：    stored_result ← result_out（保存加密结果供后续观察）
    // 备注：    enc_result_correct ← result_out == EXPECTED_CIPHER（加密正确性标记）
    // 备注：  CHECK_DEC: ready_out 有效时比对解密结果
    // 备注：    dec_result_correct ← result_out == TEST_PLAINTEXT（解密正确性标记）
    // 备注：  若全流程正确：加密=期望密文，解密=原始明文
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stored_result      <= 128'h0;
            enc_result_correct <= 1'b0;
            dec_result_correct <= 1'b0;
        end else begin
            if (state == CHECK_ENC && ready_out) begin
                stored_result      <= result_out;
                enc_result_correct <= (result_out == EXPECTED_CIPHER);
            end
            if (state == CHECK_DEC && ready_out) begin
                dec_result_correct <= (result_out == TEST_PLAINTEXT);
            end
        end
    end

    //-----------------------------------------------------------------
    // LED output (active low)
    //   [0] SM4 busy
    //   [1] Key expansion done
    //   [2] Encryption done
    //   [3] Encryption correct
    //   [4] Decryption done
    //   [5] Decryption correct
    //-----------------------------------------------------------------
    // 备注：LED 状态编码（低有效，引脚为 0 时 LED 点亮）
    // 备注：
    // 备注：  6'b111111 — 全灭（IDLE/默认）
    // 备注：  6'b111110 — [0]亮 = SM4 工作中（密钥扩展阶段）
    // 备注：  6'b111100 — [1:0]亮 = 加密进行中
    // 备注：  6'b11?000 — [2:0]亮 = 加密完成，[3]=加密正确性（0=正确）
    // 备注：  6'b110000 — [1:0]亮 = 解密密钥扩展
    // 备注：  6'b100000 — [0]亮 = 解密进行中
    // 备注：  6'b??0000 — [4:3]亮 = 解密完成，[5]=解密正确性
    // 备注：  6'b000000 — 全亮 = 加密和解密均正确（成功指示）
    reg [5:0] led_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            led_reg <= 6'b111111;  // all LEDs off (active low)
        else begin
            case (state)
                IDLE:         led_reg <= 6'b111111;  // all off
                KEY_EXPAND,
                WAIT_KEY:     led_reg <= 6'b111110;  // LED0 on: busy
                LOAD_DATA,
                ENCRYPT_WAIT: led_reg <= 6'b111100;  // LED0,1 on: encrypting
                CHECK_ENC:    led_reg <= {~enc_result_correct, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};
                              // LED3 = enc correct
                DECRYPT_KEY,
                WAIT_DEC_KEY: led_reg <= 6'b110000;  // LED0,1: decrypt key exp
                LOAD_CIPHER,
                DECRYPT_WAIT: led_reg <= 6'b100000;  // LED0 only: decrypting
                CHECK_DEC:    led_reg <= {~dec_result_correct, ~dec_result_correct, 1'b0, 1'b0, 1'b0, 1'b0};
                              // LED5 = dec correct, LED4 = dec done
                DONE:         led_reg <= {6{~enc_result_correct & ~dec_result_correct}};
                              // All on = success, all off = fail
                default:      led_reg <= 6'b111111;
            endcase
        end
    end

    assign led = led_reg;

    //-----------------------------------------------------------------
    // SM4 core instantiation
    //-----------------------------------------------------------------
    // 备注：SM4 算法核心模块实例化
    // 备注：
    // 备注：  clk, reset_n       — 全局时钟和复位
    // 备注：  sm4_enable_in       — 模块使能（非 IDLE 时有效）
    // 备注：  encdec_enable_in    — 加密/解密运算使能
    // 备注：  encdec_sel_in       — 算法方向：0=加密, 1=解密
    // 备注：  valid_in + data_in  — 输入数据握手（明文或密文）
    // 备注：  enable_key_exp + user_key_valid + user_key_in — 密钥扩展
    // 备注：  key_exp_ready_out   — 密钥扩展完成标志
    // 备注：  ready_out + result_out — 运算完成握手及输出结果
    sm4_top u_sm4 (
        .clk                (clk               ),
        .reset_n            (rst_n             ),
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
