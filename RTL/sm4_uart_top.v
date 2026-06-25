`timescale 1ns / 100ps
////////////////////////////////////////////////////////////////////////////////
// SM4 UART Top
//   Integrates UART RX/TX + SM4 core (via sm4_top).
//
//   UART protocol (ASCII, 8N1):
//     'K' + 16 key bytes       → Set key (store only, no key expansion yet)
//     'E' + 16 plaintext       → Encrypt, returns 16 ciphertext bytes
//     'D' + 16 ciphertext      → Decrypt, returns 16 plaintext bytes
//     'P'                      → Ping, returns 'O'
//
//   On 'E' or 'D', the controller:
//     1. Runs key expansion with the stored key
//     2. Starts encryption/decryption
//     3. Waits for completion
//     4. Transmits 16 result bytes via UART TX
////////////////////////////////////////////////////////////////////////////////
// 备注：SM4 UART 通信顶层模块
// 备注：
// 备注：通过 UART (115200 8N1) 与 PC 通信，实现 SM4 加密/解密功能
// 备注：
// 备注：UART 命令协议:
// 备注：  'K' + 16 字节密钥    → 设置密钥（仅存储，不展开）
// 备注：  'E' + 16 字节明文    → 加密，返回 16 字节密文
// 备注：  'D' + 16 字节密文    → 解密，返回 16 字节明文
// 备注：  'P'                 → Ping，返回 'O'
// 备注：
// 备注：处理流程 (以加密为例):
// 备注：  PC ──'E'──▶ UART RX ──▶ 接收命令
// 备注：  PC ──16字节明文──▶ UART RX ──▶ 存入 result_buf
// 备注：  ▶ 密钥扩展(key_expansion) ◀── 使用已存储的用户密钥
// 备注：  ▶ 等待密钥扩展完成
// 备注：  ▶ 送入加密引擎(sm4_encdec_serial)
// 备注：  ▶ 等待加密完成
// 备注：  ▶ 捕获结果到 result_buf
// 备注：  ▶ UART TX ──16字节密文──▶ PC
module sm4_uart_top #(
    parameter CLK_FREQ  = 27_000_000,
    parameter BAUD_RATE = 115200
)(
    input  wire clk,
    input  wire reset_n,
    input  wire rx,
    output wire tx,
    output wire led_busy,
    output wire tx_busy_out,
    output wire [127:0] sm4_result_out,
    output wire         sm4_ready_out
);
    // 备注：UART 收发器实例 — 通过 115200 8N1 与 PC 串口通信
    // ── UART instances ──────────────────────────────────────────────────────
    wire [7:0] rx_data;
    wire       rx_received;
    wire       tx_send;
    wire [7:0] tx_data;
    wire       tx_busy;

    // 备注：UART 接收器 — 将串行 rx 信号转换为 8 位并行数据
    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE))
    u_rx (.clk(clk), .reset_n(reset_n), .rx(rx),
           .data_out(rx_data), .received(rx_received));

    // 备注：UART 发送器 — 将 8 位并行数据转换为串行 tx 信号发送给 PC
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE))
    u_tx (.clk(clk), .reset_n(reset_n), .send(tx_send),
           .data_in(tx_data), .tx(tx), .busy(tx_busy));

    // 备注：SM4 核心实例 — 包含密钥扩展、加密/解密引擎 (sm4_encdec_serial)
    // ── SM4 core (via sm4_top) ──────────────────────────────────────────────
    wire [127:0] user_key;
    wire [127:0] data_in;
    wire [127:0] result;
    reg          sm4_enable_in;
    reg          encdec_enable_in;
    reg          encdec_sel_in;
    reg          enable_key_exp_in;
    reg          user_key_valid_in;
    reg          valid_in;
    wire         key_exp_ready_out;
    wire         ready_out;

    // 备注：SM4 顶层模块实例
    // 备注：data_in / result 均为 128 位宽，内部包含流水线架构的加密/解密单元
    // 备注：key_cached_in 指示密钥是否已缓存，避免重复扩展
    sm4_top u_sm4 (
        .clk                (clk),
        .reset_n            (reset_n),
        .sm4_enable_in      (sm4_enable_in),
        .encdec_enable_in   (encdec_enable_in),
        .encdec_sel_in      (encdec_sel_in),
        .valid_in           (valid_in),
        .data_in            (data_in),
        .enable_key_exp_in  (enable_key_exp_in),
        .user_key_valid_in  (user_key_valid_in),
        .user_key_in        (user_key),
        .key_cached_in      (key_cached),
        .key_exp_ready_out  (key_exp_ready_out),
        .ready_out          (ready_out),
        .result_out         (result)
    );

    // ── Registers ───────────────────────────────────────────────────────────
    reg [7:0] key_buf   [0:15];
    reg [7:0] result_buf[0:15];
    reg [3:0] byte_cnt;

    reg [4:0] tx_done_count;

    // 备注：密钥缓存优化 — 避免重复扩展相同密钥
    // 备注：key_cached=1 时，对 E/D 命令跳过 KEY_EXPAND→WAIT_KEY 状态
    // 备注：key_expansion 模块保持轮密钥寄存器，故只需让 sm4_encdec_serial
    // 备注：立即看到 key_exp_ready=1 即可，无需重新计算
    // ── Key expansion cache ────────────────────────────────────────────────
    // When key_cached=1, skip KEY_EXPAND→WAIT_KEY on E/D commands.
    // The key_expansion module retains its round key registers, so we
    // just need sm4_encdec_serial to see key_exp_ready=1 immediately.
    reg key_cached;
    wire key_ready = key_exp_ready_out || key_cached;

    // 备注：UART 协议状态机 — 控制接收 UART 命令、密钥扩展、加密/解密、结果发送
    // 备注：
    // 备注：  IDLE       → 等待 UART 命令字节 ('K'/'E'/'D'/'P')
    // 备注：  RX_KEY     → 接收 16 字节密钥并存入 key_buf
    // 备注：  RX_DATA    → 接收 16 字节待处理数据并存入 result_buf
    // 备注：  KEY_EXPAND → 拉高 enable_key_exp 信号启动密钥扩展
    // 备注：  WAIT_KEY   → 等待密钥扩展完成 (key_exp_ready_out)
    // 备注：  DO_START   → 发送 valid_in 脉冲启动加密/解密
    // 备注：  WAIT_DONE  → 等待加密/解密完成 (ready_out)
    // 备注：  CAPTURE    → 从 result 捕获 16 字节结果到 result_buf 并启动 UART 发送
    // 备注：  TX_RESULT  → 通过 UART 逐字节发送 16 字节结果
    // 备注：  TX_PONG    → 收到 'P' 后回复 'O'
    // ── FSM ─────────────────────────────────────────────────────────────────
    localparam IDLE       = 5'd0;
    localparam RX_KEY     = 5'd1;
    localparam RX_DATA    = 5'd2;
    localparam KEY_EXPAND = 5'd3;
    localparam WAIT_KEY   = 5'd4;
    localparam DO_START   = 5'd5;
    localparam WAIT_DONE  = 5'd6;
    localparam CAPTURE    = 5'd7;
    localparam TX_RESULT  = 5'd8;
    localparam TX_PONG    = 5'd9;

    reg [4:0] state;

    wire cmd_is_set_key = (rx_data == 8'h4B);
    wire cmd_is_encrypt = (rx_data == 8'h45);
    wire cmd_is_decrypt = (rx_data == 8'h44);
    wire cmd_is_ping    = (rx_data == 8'h50);

    // ── TX edge detection ───────────────────────────────────────────────────
    reg tx_busy_d;
    wire tx_busy_falling = tx_busy_d && !tx_busy;

    reg send_pulse;
    reg [7:0] send_byte;

    reg send_ff;
    assign tx_send = send_pulse && !send_ff;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            send_ff <= 1'b0;
        end else begin
            send_ff <= send_pulse;
        end
    end

    // ── Wire SM4 inputs ─────────────────────────────────────────────────────
    assign user_key = {key_buf[0],  key_buf[1],  key_buf[2],  key_buf[3],
                       key_buf[4],  key_buf[5],  key_buf[6],  key_buf[7],
                       key_buf[8],  key_buf[9],  key_buf[10], key_buf[11],
                       key_buf[12], key_buf[13], key_buf[14], key_buf[15]};

    assign data_in = {result_buf[0],  result_buf[1],  result_buf[2],  result_buf[3],
                      result_buf[4],  result_buf[5],  result_buf[6],  result_buf[7],
                      result_buf[8],  result_buf[9],  result_buf[10], result_buf[11],
                      result_buf[12], result_buf[13], result_buf[14], result_buf[15]};

    // Extract result bytes (big-endian)
    wire [7:0] res_bytes[0:15];
    genvar gi;
    generate
        for (gi = 0; gi < 16; gi = gi + 1) begin
            assign res_bytes[gi] = result[127 - gi*8 -: 8];
        end
    endgenerate

    assign led_busy      = (state != IDLE);
    assign tx_busy_out   = tx_busy;
    assign sm4_result_out = result;
    assign sm4_ready_out  = ready_out;

    // ── Debug: state names ─────────────────────────────────────────────────
    reg [127:0] state_name;
    always @(*) begin
        case (state)
            IDLE:       state_name = "IDLE";
            RX_KEY:     state_name = "RX_KEY";
            RX_DATA:    state_name = "RX_DATA";
            KEY_EXPAND: state_name = "KEY_EXPAND";
            WAIT_KEY:   state_name = "WAIT_KEY";
            DO_START:   state_name = "DO_START";
            WAIT_DONE:  state_name = "WAIT_DONE";
            CAPTURE:    state_name = "CAPTURE";
            TX_RESULT:  state_name = "TX_RESULT";
            TX_PONG:    state_name = "TX_PONG";
            default:    state_name = "?";
        endcase
    end

    // ── Main FSM ────────────────────────────────────────────────────────────
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state             <= IDLE;
            byte_cnt          <= 4'd0;
            sm4_enable_in     <= 1'b0;
            encdec_enable_in  <= 1'b0;
            encdec_sel_in     <= 1'b0;
            enable_key_exp_in <= 1'b0;
            user_key_valid_in <= 1'b0;
            valid_in          <= 1'b0;
            send_pulse        <= 1'b0;
            tx_busy_d         <= 1'b0;
            tx_done_count     <= 5'd0;
            key_cached        <= 1'b0;
        end else begin
            tx_busy_d  <= tx_busy;
            send_pulse <= 1'b0;

            // Default SM4 control: hold enables steady unless a state changes them
            // (key expansion: held high during WAIT_KEY, data valid: single pulse)
            user_key_valid_in <= 1'b0;
            valid_in          <= 1'b0;

            case (state)
                // 备注：IDLE — 等待 UART 命令，识别 'K'(设置密钥) / 'E'(加密) / 'D'(解密) / 'P'(Ping)
                // ═════════════════════════════════════════════════════════
                IDLE: begin
                    sm4_enable_in     <= 1'b0;
                    encdec_enable_in  <= 1'b0;
                    enable_key_exp_in <= 1'b0;

                    if (rx_received) begin
                        if (cmd_is_set_key) begin
                            byte_cnt   <= 4'd0;
                            key_cached <= 1'b0;  // new key → must re-expand
                            state      <= RX_KEY;
                        end else if (cmd_is_encrypt) begin
                            encdec_sel_in <= 1'b0;  // encrypt mode
                            byte_cnt      <= 4'd0;
                            state         <= RX_DATA;
                        end else if (cmd_is_decrypt) begin
                            encdec_sel_in <= 1'b1;  // decrypt mode
                            byte_cnt      <= 4'd0;
                            state         <= RX_DATA;
                        end else if (cmd_is_ping) begin
                            send_pulse <= 1'b1;
                            send_byte  <= 8'h4F;
                            state      <= TX_PONG;
                        end
                    end
                end

                // 备注：RX_KEY — 逐字节接收 16 字节密钥存入 key_buf，收满返回 IDLE
                // ═════════════════════════════════════════════════════════
                RX_KEY: begin
                    if (rx_received) begin
                        key_buf[byte_cnt] <= rx_data;
                        if (byte_cnt == 4'd15) begin
                            state <= IDLE;
                        end
                        byte_cnt <= byte_cnt + 1;
                    end
                end

                // 备注：RX_DATA — 逐字节接收 16 字节数据到 result_buf
                // 备注：收满后根据 key_cached 决定直接启动加密/解密或先执行密钥扩展
                // ═════════════════════════════════════════════════════════
                RX_DATA: begin
                    if (rx_received) begin
                        result_buf[byte_cnt] <= rx_data;
                        if (byte_cnt == 4'd15) begin
                            $display("[%0t] RX_DATA: last byte, key_cached=%b", $time, key_cached);
                            sm4_enable_in    <= 1'b1;
                            encdec_enable_in <= 1'b1;

                            if (key_cached) begin
                                // Key already expanded — skip KEY_EXPAND/WAIT_KEY.
                                // key_ready=1 (from key_cached), so sm4_encdec_serial
                                // will immediately transition WAITING_FOR_KEY→ENCRYPTION.
                                // Pulse valid_in directly.
                                valid_in <= 1'b1;
                                state    <= DO_START;
                            end else begin
                                // First time: run key expansion
                                enable_key_exp_in <= 1'b1;
                                user_key_valid_in <= 1'b1;
                                state             <= KEY_EXPAND;
                            end
                        end
                        byte_cnt <= byte_cnt + 1;
                    end
                end

                // 备注：KEY_EXPAND — 拉高 enable_key_exp 信号，启动密钥扩展
                // ═════════════════════════════════════════════════════════
                KEY_EXPAND: begin
                    $display("[%0t] KEY_EXPAND", $time);
                    sm4_enable_in     <= 1'b1;
                    encdec_enable_in  <= 1'b1;
                    enable_key_exp_in <= 1'b1;
                    state             <= WAIT_KEY;
                end

                // 备注：WAIT_KEY — 等待密钥扩展完成，完成后标记 key_cached 并发送 valid_in 脉冲
                // ═════════════════════════════════════════════════════════
                WAIT_KEY: begin
                    sm4_enable_in     <= 1'b1;
                    encdec_enable_in  <= 1'b1;
                    enable_key_exp_in <= 1'b1;

                    if (key_exp_ready_out) begin
                        $display("[%0t] WAIT_KEY: key_exp_ready_out ASSERTED", $time);
                        key_cached <= 1'b1;  // key is now expanded and cached
                        valid_in   <= 1'b1;
                        state      <= DO_START;
                    end
                end

                // 备注：DO_START — 发送 valid_in 脉冲启动加密/解密引擎，然后进入 WAIT_DONE
                // ═════════════════════════════════════════════════════════
                DO_START: begin
                    // valid_in was pulsed for one cycle.
                    // Keep everything enabled while SM4 processes.
                    $display("[%0t] DO_START: asserting valid_in", $time);
                    sm4_enable_in     <= 1'b1;
                    encdec_enable_in  <= 1'b1;
                    enable_key_exp_in <= 1'b0;  // key expansion no longer needed

                    state <= WAIT_DONE;
                end

                // 备注：WAIT_DONE — 等待加密/解密完成 (ready_out)，完成后进入 CAPTURE
                // ═════════════════════════════════════════════════════════
                WAIT_DONE: begin
                    sm4_enable_in     <= 1'b1;
                    encdec_enable_in  <= 1'b1;
                    enable_key_exp_in <= 1'b0;

                    if (ready_out) begin
                        $display("[%0t] WAIT_DONE: ready_out ASSERTED", $time);
                        state <= CAPTURE;
                    end
                end

                // 备注：CAPTURE — 从 result 总线捕获 16 字节结果到 result_buf
                // 备注：同时发送第一个字节的 send_pulse 启动 UART TX 发送
                // ═════════════════════════════════════════════════════════
                CAPTURE: begin
                    $display("[%0t] CAPTURE: result=%032h, tx_busy=%b", $time, result, tx_busy);
                    // Capture result into result_buf, queue first TX byte
                    // Disable SM4 core now that we're done
                    sm4_enable_in     <= 1'b0;
                    encdec_enable_in  <= 1'b0;
                    enable_key_exp_in <= 1'b0;

                    result_buf[0]  <= res_bytes[0] ;
                    result_buf[1]  <= res_bytes[1] ;
                    result_buf[2]  <= res_bytes[2] ;
                    result_buf[3]  <= res_bytes[3] ;
                    result_buf[4]  <= res_bytes[4] ;
                    result_buf[5]  <= res_bytes[5] ;
                    result_buf[6]  <= res_bytes[6] ;
                    result_buf[7]  <= res_bytes[7] ;
                    result_buf[8]  <= res_bytes[8] ;
                    result_buf[9]  <= res_bytes[9] ;
                    result_buf[10] <= res_bytes[10];
                    result_buf[11] <= res_bytes[11];
                    result_buf[12] <= res_bytes[12];
                    result_buf[13] <= res_bytes[13];
                    result_buf[14] <= res_bytes[14];
                    result_buf[15] <= res_bytes[15];

                    send_pulse    <= 1'b1;
                    send_byte     <= res_bytes[0];
                    tx_done_count <= 5'd0;
                    state         <= TX_RESULT;
                end

                // 备注：TX_RESULT — 通过 UART 逐字节发送 16 字节结果
                // 备注：利用 tx_busy_falling 边沿检测每个字节发送完成，依次推送下一字节
                // ═════════════════════════════════════════════════════════
                TX_RESULT: begin
                    // Byte 0 was queued by CAPTURE's send_pulse.
                    // On each tx_busy_falling (TX completes a byte),
                    // queue the next byte from result_buf.
                    //
                    // tx_done_count tracks how many bytes have been fully
                    // transmitted. Byte 0 done → tx_done_count=0→1,
                    // queue byte 1. Byte 15 done → tx_done_count=15→IDLE.
                    if (tx_busy_falling) begin
                        $display("[%0t] TX_RESULT: byte %d done, busy_fall, cnt=%d -> %d",
                                 $time, tx_done_count, tx_done_count, tx_done_count+1);
                        if (tx_done_count == 5'd15) begin
                            $display("[%0t] TX_RESULT: ALL DONE -> IDLE", $time);
                            state <= IDLE;
                        end else begin
                            send_pulse <= 1'b1;
                            send_byte  <= result_buf[tx_done_count + 1];
                        end
                        tx_done_count <= tx_done_count + 1;
                    end
                end

                // 备注：TX_PONG — Ping 响应状态，等待 'O' 发送完毕后返回 IDLE
                // ═════════════════════════════════════════════════════════
                TX_PONG: begin
                    if (tx_busy_falling) begin
                        state <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    assign tx_data = send_byte;

endmodule
