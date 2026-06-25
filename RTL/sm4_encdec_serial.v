`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer: FPGA_SM4 (serial/iterative version by Sisyphus)
//
// Create Date: 2026/06/24
// Design Name: sm4_encdec_serial
// Project Name: FPGA_SM4
// Target Devices: Tang Nano 20K (GW2AR-LV18QN88C8/I7)
// Tool Versions:
// Description:
//   SM4 encryption/decryption engine (serial/iterative).
//
//   Replaces the 32-stage fully-pipelined sm4_encdec.v with a single-round
//   iterative engine. Uses ~1/32 the LUT area of the original pipeline.
//
//   FSM states: IDLE → WAITING_FOR_KEY → ENCRYPTION
//
//   Timing (single block):
//     - valid_in (1 cycle): load data_in, start processing
//     - following 32 cycles: compute rounds 0..31
//     - ready_out goes high after 33 total cycles
//
//   Interface is pin-compatible with the original sm4_encdec.v.
//
// Dependencies:
//   one_round_for_encdec.v, sbox_replace.v, transform_for_encdec.v
//
//////////////////////////////////////////////////////////////////////////////////
// 备注：SM4 加密/解密引擎 — 串行迭代架构
// 备注：
// 备注：设计目标：在 Tang Nano 20K (GW2AR) 上最小化 LUT 资源占用。
// 备注：与全流水线架构的对比：
// 备注：  全流水线: 32 个 one_round_for_encdec 实例，每时钟输出一个结果
// 备注：  串行迭代: 1 个 one_round_for_encdec 实例复用 32 次，
// 备注：            33 个时钟输出一个结果
// 备注：
// 备注：面积节省: 轮函数逻辑约为全流水线的 1/32
// 备注：代价: 吞吐率降为流水线的 1/33，延后 32 拍输出
// 备注：
// 备注：接口与 sm4_encdec.v (流水线版) 完全兼容，可即插即用替换。
// 备注：外围模块 (key_expansion 等) 无需做任何修改。
// 备注：
// 备注：FSM 工作流程：
// 备注：  IDLE → WAITING_FOR_KEY → ENCRYPTION
// 备注：  等待密钥扩展完成后开始加密，加密状态保持直到被禁用。
// 备注：
// 备注：迭代控制器核心寄存器：busy, round, reg_data (详见下方)
// 备注：

module sm4_encdec_serial(
    clk                 ,
    reset_n             ,
    sm4_enable_in       ,
    encdec_enable_in    ,
    key_exp_ready_in    ,
    valid_in            ,
    data_in             ,
    rk_00_in            ,
    rk_01_in            ,
    rk_02_in            ,
    rk_03_in            ,
    rk_04_in            ,
    rk_05_in            ,
    rk_06_in            ,
    rk_07_in            ,
    rk_08_in            ,
    rk_09_in            ,
    rk_10_in            ,
    rk_11_in            ,
    rk_12_in            ,
    rk_13_in            ,
    rk_14_in            ,
    rk_15_in            ,
    rk_16_in            ,
    rk_17_in            ,
    rk_18_in            ,
    rk_19_in            ,
    rk_20_in            ,
    rk_21_in            ,
    rk_22_in            ,
    rk_23_in            ,
    rk_24_in            ,
    rk_25_in            ,
    rk_26_in            ,
    rk_27_in            ,
    rk_28_in            ,
    rk_29_in            ,
    rk_30_in            ,
    rk_31_in            ,
    ready_out           ,
    result_out
);
    input               clk                 ;
    input               reset_n             ;
    input               sm4_enable_in       ;
    input               encdec_enable_in    ;
    input               key_exp_ready_in    ;
    input               valid_in            ;
    input   [127: 0]    data_in             ;
    input   [31 : 0]    rk_00_in            ;
    input   [31 : 0]    rk_01_in            ;
    input   [31 : 0]    rk_02_in            ;
    input   [31 : 0]    rk_03_in            ;
    input   [31 : 0]    rk_04_in            ;
    input   [31 : 0]    rk_05_in            ;
    input   [31 : 0]    rk_06_in            ;
    input   [31 : 0]    rk_07_in            ;
    input   [31 : 0]    rk_08_in            ;
    input   [31 : 0]    rk_09_in            ;
    input   [31 : 0]    rk_10_in            ;
    input   [31 : 0]    rk_11_in            ;
    input   [31 : 0]    rk_12_in            ;
    input   [31 : 0]    rk_13_in            ;
    input   [31 : 0]    rk_14_in            ;
    input   [31 : 0]    rk_15_in            ;
    input   [31 : 0]    rk_16_in            ;
    input   [31 : 0]    rk_17_in            ;
    input   [31 : 0]    rk_18_in            ;
    input   [31 : 0]    rk_19_in            ;
    input   [31 : 0]    rk_20_in            ;
    input   [31 : 0]    rk_21_in            ;
    input   [31 : 0]    rk_22_in            ;
    input   [31 : 0]    rk_23_in            ;
    input   [31 : 0]    rk_24_in            ;
    input   [31 : 0]    rk_25_in            ;
    input   [31 : 0]    rk_26_in            ;
    input   [31 : 0]    rk_27_in            ;
    input   [31 : 0]    rk_28_in            ;
    input   [31 : 0]    rk_29_in            ;
    input   [31 : 0]    rk_30_in            ;
    input   [31 : 0]    rk_31_in            ;
    output              ready_out           ;
    output  [127: 0]    result_out          ;

    //-----------------------------------------------------------------
    // FSM states (same encoding as original)
    //-----------------------------------------------------------------
    // 备注：状态编码：
    // 备注：  IDLE (00) — 空闲，等待 sm4_enable_in & encdec_enable_in
    // 备注：  WAITING_FOR_KEY (01) — 等待 key expansion 完成
    // 备注：  ENCRYPTION (10) — 迭代计算中，连续处理到来的 128-bit 块
    // 备注：
    // 备注：注意 WAITING_FOR_KEY 仅在密钥未就绪时停留，
    // 备注：key_exp_ready_in 为高后下一拍跳转到 ENCRYPTION。
    // 备注：ENCRYPTION 状态不因 block 处理完成而退出，
    // 备注：它是"持续工作"模式，直到外部禁用 encdec_enable_in。
    localparam IDLE            = 2'b00;
    localparam WAITING_FOR_KEY = 2'b01;
    localparam ENCRYPTION      = 2'b10;

    reg [1:0] current;
    reg [1:0] next_state;

    reg [63:0] enc_state_name;
    always @(*) begin
        case (current)
            IDLE:            enc_state_name = "IDLE";
            WAITING_FOR_KEY: enc_state_name = "WAIT_KEY";
            ENCRYPTION:      enc_state_name = "ENCRYPT";
            default:         enc_state_name = "?";
        endcase
    end

    reg [1:0] enc_current_d;
    reg [63:0] enc_state_d;
    always @(posedge clk) begin
        enc_current_d <= current;
        enc_state_d   <= enc_state_name;
    end

    always @(posedge clk) begin
        if (current != enc_current_d && $time > 100)
            $display("[%0t] encdec: %s -> %s (key_exp_rdy=%b, sm4_en=%b, encdec_en=%b, valid=%b)",
                     $time, enc_state_d, enc_state_name,
                     key_exp_ready_in, sm4_enable_in, encdec_enable_in, valid_in);
    end

    always @(posedge clk or negedge reset_n)
        if(!reset_n)
            current <= IDLE;
        else if(sm4_enable_in)
            current <= next_state;

    always @(*) begin
        next_state = IDLE;
        case (current)
            IDLE:
                if (sm4_enable_in && encdec_enable_in)
                    next_state = WAITING_FOR_KEY;
            WAITING_FOR_KEY:
                if (key_exp_ready_in)
                    next_state = ENCRYPTION;
                else
                    next_state = WAITING_FOR_KEY;
            ENCRYPTION:
                if (!encdec_enable_in || !sm4_enable_in)
                    next_state = IDLE;
                else
                    next_state = ENCRYPTION;
        endcase
    end

    //-----------------------------------------------------------------
    // Round iteration control
    //-----------------------------------------------------------------
    //   busy: 1 when actively processing a block
    //   round: 0..31, which round to compute THIS cycle
    //     round=0: compute round 0 using rk_00_in
    //     round=1: compute round 1 using rk_01_in
    //     ...
    //     round=31: compute round 31 using rk_31_in
    //
    // Timing (ENCRYPTION state):
    //   Cycle when valid_in: reg_data <= data_in, busy <= 1, round <= 0
    //   Next 31 cycles (round 0..30): reg_data <= round_result, round++
    //   Cycle when round=31: result_out <= reversed(round_result),
    //                        ready_out <= 1, busy <= 0
    //   Total: ~33 cycles from valid_in to ready_out
    //-----------------------------------------------------------------
    // 备注：迭代控制核心寄存器说明：
    // 备注：
    // 备注：  busy — 忙标志，=1 表示正在处理一个 block，阻止新数据加载
    // 备注：  round[4:0] — 当前轮号 (0..31)，决定本轮使用哪个轮密钥，
    // 备注：              也作为迭代是否完成的判断 (round==31 时输出)
    // 备注：  reg_data — 128 位中间状态寄存器，每轮被 round_result 更新
    // 备注：
    // 备注：迭代周期（ENCRYPTION 状态下）：
    // 备注：  T=0   valid_in=1 → 加载 data_in, busy=1, round=0
    // 备注：  T=1   计算 round 0, reg_data ← round_result, round=1
    // 备注：  T=2   计算 round 1, reg_data ← round_result, round=2
    // 备注：  ...    ...
    // 备注：  T=32  计算 round 31, 输出反序结果, ready_out=1, busy=0
    // 备注：
    // 备注：总延迟 33 拍，期间可连续输入新 block（需要前一个 busy=0）。
    // 备注：但由于串行迭代的流水线间隙，每 33 拍处理一个 block，
    // 备注：不能像全流水线那样每拍输入一个。
    // 备注：
    reg        busy;
    reg  [4:0] round;      // 0..31
    reg [127:0] reg_data;  // current block data

    // Round function combinational result
    wire [127:0] round_result;

    // Selected round key (combinational MUX)
    reg [31:0] selected_rk;
    // 备注：selected_rk — 由 round 号从 32 个预计算轮密钥中选出一个，
    // 备注：组合逻辑 MUX 输出，不占用时钟周期。

    // ready_out (registered, auto-clears on next clock)
    reg ready_reg;
    assign ready_out = ready_reg;

    // result_out (registered)
    reg [127:0] result_reg;
    assign result_out = result_reg;
    // 备注：result_out 与 ready_out 同步输出，ready_out 高电平时
    // 备注：result_out 的数据有效。

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy       <= 1'b0;
            round      <= 5'd0;
            reg_data   <= 128'd0;
            ready_reg  <= 1'b0;
            result_reg <= 128'd0;
        end else begin
            // Auto-clear ready_out (single-cycle pulse)
            if (ready_reg)
                ready_reg <= 1'b0;

            if (current == ENCRYPTION) begin
                if (valid_in && !busy) begin
                    // Load initial data, begin processing
                    $display("[%0t] encdec: LOAD valid_in=%b busy=%b data=%032h",
                             $time, valid_in, busy, data_in);
                    reg_data <= data_in;
                    busy     <= 1'b1;
                    round    <= 5'd0;
                end else if (busy) begin
                    if (round < 5'd31) begin
                        // Compute and advance
                        reg_data <= round_result;
                        round    <= round + 1'b1;
                    end else begin
                        // round == 31: last round computation
                        // round_result is the final SM4 result
                        // Reverse word order for output (SM4 convention)
                        // 备注：SM4 反序变换 (Reverse Transform)
                        // 备注：SM4 算法规定输出时需将 (X0, X1, X2, X3) 反序排列为 (X3, X2, X1, X0)。
                        // 备注：此处将 round_result 的四个 32-bit 字 (X3|X2|X1|X0) 重排为 (X0|X1|X2|X3) 输出。
                        // 备注：拼接域格式：{X0, X1, X2, X3}，其中 X0 在 [127:96] 位。
                        // 备注：反序后结果需与标准 SM4 测试向量一致。
                        $display("[%0t] encdec: RESULT ready (round=%d)", $time, round);
                        result_reg <= {round_result[31:0],
                                       round_result[63:32],
                                       round_result[95:64],
                                       round_result[127:96]};
                        ready_reg  <= 1'b1;
                        busy       <= 1'b0;
                        round      <= 5'd0;
                    end
                end
            end else begin
                // Not in ENCRYPTION state, reset
                busy  <= 1'b0;
                round <= 5'd0;
            end
        end
    end

    //-----------------------------------------------------------------
    // Round key selection MUX (32:1, combinational)
    //-----------------------------------------------------------------
    // round=0  → rk_00_in  (round 0)
    // round=1  → rk_01_in  (round 1)
    // ...
    // round=31 → rk_31_in  (round 31)
    //-----------------------------------------------------------------
    // 备注：32:1 轮密钥多路选择器
    // 备注：32 个预计算轮密钥由外部 key_expansion 模块提供。
    // 备注：注意这里不关心加密/解密模式，因为加密和解密使用的轮密钥序列
    // 备注：不同（解密时轮密钥反序使用），但此选择器仅按 round 号选取，
    // 备注：反序工作由外围模块或者轮密钥输入顺序保证。
    always @(*) begin
        case (round)
            5'd0:   selected_rk = rk_00_in;
            5'd1:   selected_rk = rk_01_in;
            5'd2:   selected_rk = rk_02_in;
            5'd3:   selected_rk = rk_03_in;
            5'd4:   selected_rk = rk_04_in;
            5'd5:   selected_rk = rk_05_in;
            5'd6:   selected_rk = rk_06_in;
            5'd7:   selected_rk = rk_07_in;
            5'd8:   selected_rk = rk_08_in;
            5'd9:   selected_rk = rk_09_in;
            5'd10:  selected_rk = rk_10_in;
            5'd11:  selected_rk = rk_11_in;
            5'd12:  selected_rk = rk_12_in;
            5'd13:  selected_rk = rk_13_in;
            5'd14:  selected_rk = rk_14_in;
            5'd15:  selected_rk = rk_15_in;
            5'd16:  selected_rk = rk_16_in;
            5'd17:  selected_rk = rk_17_in;
            5'd18:  selected_rk = rk_18_in;
            5'd19:  selected_rk = rk_19_in;
            5'd20:  selected_rk = rk_20_in;
            5'd21:  selected_rk = rk_21_in;
            5'd22:  selected_rk = rk_22_in;
            5'd23:  selected_rk = rk_23_in;
            5'd24:  selected_rk = rk_24_in;
            5'd25:  selected_rk = rk_25_in;
            5'd26:  selected_rk = rk_26_in;
            5'd27:  selected_rk = rk_27_in;
            5'd28:  selected_rk = rk_28_in;
            5'd29:  selected_rk = rk_29_in;
            5'd30:  selected_rk = rk_30_in;
            5'd31:  selected_rk = rk_31_in;
            default: selected_rk = 32'd0;
        endcase
    end

    //-----------------------------------------------------------------
    // Single round function instance (shared across all 32 iterations)
    //-----------------------------------------------------------------
    // 备注：单轮函数实例化（被所有 32 轮迭代共享）
    // 备注：
    // 备注：这是串行迭代架构的核心——面积节省的关键。
    // 备注：全流水线版实例化 32 个 u_round，每个占用一套 S-Box + 线性变换逻辑。
    // 备注：本设计只实例化 1 个，通过 MUX 每周期切换输入 (reg_data, selected_rk)，
    // 备注：并在时序上重复使用 32 次。
    // 备注：
    // 备注：组合逻辑路径：
    // 备注：  reg_data[127:0] + selected_rk[31:0]
    // 备注：    → S-Box 替换 (4 个并行 S-Box)
    // 备注：      → 线性变换 L
    // 备注：        → 与 reg_data 高位异或
    // 备注：          → round_result[127:0]
    // 备注：
    // 备注：这种单实例共享方式延后了 32 拍输出结果，
    // 备注：但在资源受限的 FPGA（如 Tang Nano 20K）上至关重要。
    one_round_for_encdec u_round (
        .data_in      (reg_data),
        .round_key_in (selected_rk),
        .result_out   (round_result)
    );

endmodule
