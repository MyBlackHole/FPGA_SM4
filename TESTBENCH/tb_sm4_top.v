`timescale 1ns / 100ps

// ============================================
// 文件说明：sm4_top 顶层模块的测试平台
// 包含：加密/解密双模式下完整的功能验证
// 测试向量来源：SM4 国家标准 GM/T 0002-2012
// ============================================
// 备注：测试方法：
// 备注：第一轮加密：明文 → 密文，验证密文是否匹配标准向量
// 备注：第二轮解密：密文 → 明文，验证是否还原为原始明文
// 备注：使用标准测试向量：
// 备注：  KEY   = 0123456789abcdeffedcba9876543210
// 备注：  PLAIN = 0123456789abcdeffedcba9876543210
// 备注：  CIPHER= 681edf34d206965e86b3e94f536e4246
module tb_sm4_top();

    // 备注：时钟与复位信号
    reg			    clk		            ;
    reg			    reset_n	            ;
    // 备注：SM4 核心使能信号
    reg             sm4_enable_in       ;
    // 备注：加密操作使能信号
    reg             encdec_enable_in    ;
    // 备注：加密/解密模式选择（0=加密，1=解密）
    reg             encdec_sel_in       ;
    // 备注：输入数据有效标志
    reg             valid_in            ;
    // 备注：128 位明文/密文输入
    reg   [127: 0]  data_in             ;
    // 备注：密钥扩展使能信号
    reg             enable_key_exp_in   ;
    // 备注：用户密钥写入有效标志
    reg             user_key_valid_in   ;
    // 备注：128 位用户密钥输入
    reg   [127: 0]  user_key_in         ;
    // 备注：加密结果就绪标志
    wire            ready_out           ;
    // 备注：密钥扩展就绪标志
    wire            key_exp_ready_out   ;
    // 备注：128 位加密/解密结果输出
    wire  [127: 0]  result_out          ;
    

    // 备注：时钟生成 — 周期约 6ns（约 166MHz），行为级仿真用
    always #3 clk = ~clk;


    // 备注：主测试流程 — 先加密后解密，双遍测试
    // 备注：测试协议：
    // 备注：  1. 复位释放 → 使能 SM4 → 使能密钥扩展 → 加载密钥
    // 备注：  2. 等待 key_exp_ready_out → 使能加密 → 输入明文
    // 备注：  3. 等待 ready_out → 读取结果并验证
    // 备注：  4. 复位模块 → 切换到解密模式 → 重复上述流程
    initial
        begin
            clk		            = 0;
            reset_n	            = 0;
            sm4_enable_in       = 0;
            encdec_enable_in    = 0;
            encdec_sel_in       = 0;
            valid_in            = 0;
            data_in             = 0;
            enable_key_exp_in   = 0;
            user_key_valid_in   = 0;
            user_key_in         = 0;
            // 备注：第一阶段 — 加密测试
            // 备注：复位释放，等待 111ns 让全局信号稳定
            #111;
            reset_n = 1;
            // 备注：使能 SM4 核心
            #111;
            sm4_enable_in = 1;
            // 备注：使能密钥扩展模块
            #111;
            enable_key_exp_in = 1;
            // 备注：加载 128 位用户密钥
            #111;
            @(posedge clk)
            begin
            user_key_valid_in = 1'b1;
            user_key_in       = 128'h0123456789abcdeffedcba9876543210;
            end
            // 备注：等待密钥扩展完成
            wait(key_exp_ready_out);
            // 备注：使能加密操作，注入明文数据
            #111;
            encdec_enable_in = 1;
            #111;
            @(posedge clk)
            begin
            valid_in = 1'b1;
            data_in = 128'h0123456789abcdeffedcba9876543210;
            end
            // 备注：撤销 valid_in，等待加密完成
            @(posedge clk) valid_in = 1'b0;
            wait(ready_out);
            // 备注：第二阶段 — 解密测试
            // 备注：清除所有控制信号，切换为解密模式
            #300;
            sm4_enable_in       = 0;
            encdec_enable_in    = 0;
            encdec_sel_in       = 0;
            valid_in            = 0;
            data_in             = 0;
            enable_key_exp_in   = 0;
            user_key_valid_in   = 0;
            user_key_in         = 0;
            // 备注：重新使能 SM4，切换到解密模式（encdec_sel_in=1）
            #111;
            sm4_enable_in       = 1;
            #111;
            encdec_sel_in       = 1;
            enable_key_exp_in   = 1;
            // 备注：再次加载相同密钥（解密时密钥扩展生成反序轮密钥）
            #111;
            @(posedge clk)
            begin
            user_key_valid_in = 1'b1;
            user_key_in       = 128'h0123456789abcdeffedcba9876543210;
            end
            // 备注：等待密钥扩展完成
            wait(key_exp_ready_out);
            // 备注：注入密文数据，启动解密
            #111;
            encdec_enable_in = 1;
            #111;
            @(posedge clk)
            begin
            valid_in = 1'b1;
            data_in = 128'h681edf34d206965e86b3e94f536e4246;
            end
            #300;
            $finish;
        end
      
      
      
    // 备注：打印当前测试阶段（加密或解密）
    always@(*)        
        if(~encdec_sel_in)
            $display("Test of Encryption....\n");
        else
            $display("Test of Decryption....\n");
            
    // 备注：打印输入的明文/密文数据
    always@(*)                
        if(valid_in)
            $display("Input Data: %h\n", data_in); 

    // 备注：加密结果验证 — 与标准密文 0x681edf34d206965e86b3e94f536e4246 比对
    // 备注：使用 $display 输出期望值和实际值，不一致时打印 "Error!"
    always@(*)                
        if(~encdec_sel_in && ready_out)
            begin
                $display("Expected encryption result: 128'h681edf34d206965e86b3e94f536e4246");
                $display("Actual   encryption result: %h", result_out);
                if(result_out == 128'h681edf34d206965e86b3e94f536e4246 )
                        $display("Correct! The same as the expected!\n");
                else
                    begin
                        $display("Error!\n");
                    end
            end
            
    // 备注：解密结果验证 — 与原始明文 0x0123456789abcdeffedcba9876543210 比对
    // 备注：解密正确应能还原加密前的输入数据
    always@(*)                
        if(encdec_sel_in && ready_out)
            begin
                $display("Expected decryption result: 128'h0123456789abcdeffedcba9876543210");
                $display("Actual   decryption result: %h", result_out);
                if(result_out == 128'h0123456789abcdeffedcba9876543210 )
                        $display("Correct! The same as the expected!\n");
                else
                    begin
                        $display("Error!\n");
                    end
            end           
            
          
    // 备注：实例化被测模块 — sm4_top（SM4 加密/解密顶层模块）
    sm4_top uut(
        .clk		         (clk		        ),
        .reset_n	         (reset_n	        ),
        .sm4_enable_in       (sm4_enable_in     ),
        .encdec_enable_in    (encdec_enable_in  ),
        .encdec_sel_in       (encdec_sel_in     ),
        .valid_in            (valid_in          ),
        .data_in             (data_in           ),
        .enable_key_exp_in   (enable_key_exp_in ),
        .user_key_valid_in   (user_key_valid_in ),
        .user_key_in         (user_key_in       ),
        .ready_out           (ready_out         ),
        .key_exp_ready_out   (key_exp_ready_out ),
        .result_out          (result_out        )
    );
    

endmodule