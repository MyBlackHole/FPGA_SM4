`timescale 1ns / 100ps

// ============================================
// 文件说明：SM4 4轮流水线加密/解密引擎
// 架构：面积与吞吐率的折中设计
// ============================================
// 备注：SM4 加密/解密引擎 — 4 轮流水线架构（面积与吞吐率的折中设计）
// 备注：
// 备注：与 sm4_encdec.v (32级全流水线) 和 sm4_encdec_serial.v (串行迭代) 的区别：
// 备注：
// 备注：  架构          | 单轮引擎数 | 时钟周期/分组 | 面积
// 备注：  ──────────────|───────────|──────────────|───────
// 备注：  全流水线(32级) |    32     |      1       |  最大
// 备注：  4轮流水线     |     4     |      8       |  中等
// 备注：  串行迭代       |     1     |     32       |  最小
// 备注：
// 备注：本模块实现方式：
// 备注：  每周期计算 4 轮 (通过 4 个组合逻辑 one_round_for_encdec 串联)
// 备注：  每轮使用 4 个不同的轮密钥 (rk0/rk1/rk2/rk3)
// 备注：  共需 8 个时钟周期完成全部 32 轮加密
// 备注：  分组流水线填满后，每 8 个时钟输出一个结果
module sm4_encdec_4round(
    clk,
    reset_n,
    sm4_enable_in,
    encdec_enable_in,
    key_exp_ready_in,
    valid_in,
    data_in,
    rk_00_in, rk_01_in, rk_02_in, rk_03_in,
    rk_04_in, rk_05_in, rk_06_in, rk_07_in,
    rk_08_in, rk_09_in, rk_10_in, rk_11_in,
    rk_12_in, rk_13_in, rk_14_in, rk_15_in,
    rk_16_in, rk_17_in, rk_18_in, rk_19_in,
    rk_20_in, rk_21_in, rk_22_in, rk_23_in,
    rk_24_in, rk_25_in, rk_26_in, rk_27_in,
    rk_28_in, rk_29_in, rk_30_in, rk_31_in,
    ready_out,
    result_out
);
    input               clk;
    input               reset_n;
    input               sm4_enable_in;
    input               encdec_enable_in;
    input               key_exp_ready_in;
    input               valid_in;
    input   [127:0]     data_in;
    input   [31:0]      rk_00_in, rk_01_in, rk_02_in, rk_03_in;
    input   [31:0]      rk_04_in, rk_05_in, rk_06_in, rk_07_in;
    input   [31:0]      rk_08_in, rk_09_in, rk_10_in, rk_11_in;
    input   [31:0]      rk_12_in, rk_13_in, rk_14_in, rk_15_in;
    input   [31:0]      rk_16_in, rk_17_in, rk_18_in, rk_19_in;
    input   [31:0]      rk_20_in, rk_21_in, rk_22_in, rk_23_in;
    input   [31:0]      rk_24_in, rk_25_in, rk_26_in, rk_27_in;
    input   [31:0]      rk_28_in, rk_29_in, rk_30_in, rk_31_in;
    output              ready_out;
    output  [127:0]     result_out;

    // 备注：FSM 状态定义
    // 备注：  IDLE            — 空闲状态，等待加密使能
    // 备注：  WAITING_FOR_KEY — 等待密钥扩展完成
    // 备注：  ENCRYPTION      — 加密处理中
    localparam IDLE            = 2'b00;
    localparam WAITING_FOR_KEY = 2'b01;
    localparam ENCRYPTION      = 2'b10;

    reg [1:0] current, next_state;

    always @(posedge clk or negedge reset_n)
        if (!reset_n) current <= IDLE;
        else if (sm4_enable_in) current <= next_state;

    always @(*) begin
        next_state = IDLE;
        case (current)
            IDLE:            if (sm4_enable_in && encdec_enable_in) next_state = WAITING_FOR_KEY;
            WAITING_FOR_KEY: if (key_exp_ready_in) next_state = ENCRYPTION;
                             else next_state = WAITING_FOR_KEY;
            ENCRYPTION:      if (!encdec_enable_in || !sm4_enable_in) next_state = IDLE;
                             else next_state = ENCRYPTION;
        endcase
    end

    reg        busy;
    reg  [2:0] round_group;
    reg [127:0] reg_data;
    reg        ready_reg;
    reg [127:0] result_reg;

    assign ready_out   = ready_reg;
    assign result_out  = result_reg;

    wire [127:0] r0_out, r1_out, r2_out, r3_out;

    wire [31:0] rk0, rk1, rk2, rk3;

    // 备注：round_group 计数器选择 8 组轮密钥中的一组
    // 备注：round_group=0 → rk_00~rk_03 (第1-4轮)
    // 备注：round_group=1 → rk_04~rk_07 (第5-8轮)
    // 备注：...
    // 备注：round_group=7 → rk_28~rk_31 (第29-32轮)
    assign rk0 = (round_group == 3'd0) ? rk_00_in :
                 (round_group == 3'd1) ? rk_04_in :
                 (round_group == 3'd2) ? rk_08_in :
                 (round_group == 3'd3) ? rk_12_in :
                 (round_group == 3'd4) ? rk_16_in :
                 (round_group == 3'd5) ? rk_20_in :
                 (round_group == 3'd6) ? rk_24_in : rk_28_in;

    assign rk1 = (round_group == 3'd0) ? rk_01_in :
                 (round_group == 3'd1) ? rk_05_in :
                 (round_group == 3'd2) ? rk_09_in :
                 (round_group == 3'd3) ? rk_13_in :
                 (round_group == 3'd4) ? rk_17_in :
                 (round_group == 3'd5) ? rk_21_in :
                 (round_group == 3'd6) ? rk_25_in : rk_29_in;

    assign rk2 = (round_group == 3'd0) ? rk_02_in :
                 (round_group == 3'd1) ? rk_06_in :
                 (round_group == 3'd2) ? rk_10_in :
                 (round_group == 3'd3) ? rk_14_in :
                 (round_group == 3'd4) ? rk_18_in :
                 (round_group == 3'd5) ? rk_22_in :
                 (round_group == 3'd6) ? rk_26_in : rk_30_in;

    assign rk3 = (round_group == 3'd0) ? rk_03_in :
                 (round_group == 3'd1) ? rk_07_in :
                 (round_group == 3'd2) ? rk_11_in :
                 (round_group == 3'd3) ? rk_15_in :
                 (round_group == 3'd4) ? rk_19_in :
                 (round_group == 3'd5) ? rk_23_in :
                 (round_group == 3'd6) ? rk_27_in : rk_31_in;

    // 备注：4 轮组合逻辑串联：一个时钟周期内完成 4 轮 SM4 轮函数
    // 备注：  u_r0: reg_data + rk0 → r0_out (第1轮)
    // 备注：  u_r1: r0_out   + rk1 → r1_out (第2轮)
    // 备注：  u_r2: r1_out   + rk2 → r2_out (第3轮)
    // 备注：  u_r3: r2_out   + rk3 → r3_out (第4轮)
    // 备注：结果 r3_out 在下一时钟周期存入 reg_data，供下一组 4 轮使用
    one_round_for_encdec u_r0 (.data_in(reg_data),       .round_key_in(rk0), .result_out(r0_out));
    one_round_for_encdec u_r1 (.data_in(r0_out),         .round_key_in(rk1), .result_out(r1_out));
    one_round_for_encdec u_r2 (.data_in(r1_out),         .round_key_in(rk2), .result_out(r2_out));
    one_round_for_encdec u_r3 (.data_in(r2_out),         .round_key_in(rk3), .result_out(r3_out));

    // 备注：SM4 反序变换 (Reverse Transformation)
    // 备注：SM4 规范要求输出 X[32..35] 反序排列：后 4 个 32-bit 字逆序输出
    // 备注：  r3_out = {X35, X34, X33, X32} → reversed = {X32, X33, X34, X35}
    // 备注：  即每个 32-bit 字内部字节序不变，仅字顺序反转
    wire [127:0] reversed_result = {r3_out[31:0], r3_out[63:32], r3_out[95:64], r3_out[127:96]};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy       <= 1'b0;
            round_group<= 3'd0;
            reg_data   <= 128'd0;
            ready_reg  <= 1'b0;
            result_reg <= 128'd0;
        end else begin
            if (ready_reg) ready_reg <= 1'b0;

            if (current == ENCRYPTION) begin
                // 备注：加载明文数据，开始第一组 4 轮处理
                // 备注：valid_in 有效且引擎空闲时，将 data_in 锁存到 reg_data
                // 备注：同时复位 round_group 计数器，置位 busy 标志
                if (valid_in && !busy) begin
                    reg_data    <= data_in;
                    busy        <= 1'b1;
                    round_group <= 3'd0;
                end else if (busy) begin
                    // 备注：循环处理第 2~7 组（共 8 组，32 轮）
                    // 备注：每组 4 轮结果 r3_out 存入 reg_data，round_group 递增
                    if (round_group < 3'd7) begin
                        reg_data    <= r3_out;
                        round_group <= round_group + 1'b1;
                    // 备注：最后 4 轮完成（round_group == 7），输出最终结果
                    // 备注：经反序变换后写入 result_reg，置位 ready_reg 通知下游
                    // 备注：清除 busy 标志，释放引擎接收下一个分组
                    end else begin
                        result_reg <= reversed_result;
                        ready_reg  <= 1'b1;
                        busy       <= 1'b0;
                        round_group<= 3'd0;
                    end
                end
            end else begin
                busy        <= 1'b0;
                round_group <= 3'd0;
            end
        end
    end

endmodule
