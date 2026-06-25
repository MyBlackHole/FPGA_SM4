`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2018/03/09 21:36:10
// Design Name: 
// Module Name: tb_key_expansion
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// ============================================
// 文件说明：key_expansion 密钥扩展模块的独立测试平台
// 包含：加密/解密双模式下的密钥扩展功能验证
// 测试方法：直接实例化 key_expansion，观察所有 32 轮子密钥输出
// ============================================
// 备注：测试策略：
// 备注：  独立测试 key_expansion 模块，而非通过 sm4_top 间接验证
// 备注：  引出 32 个轮密钥（rk00~rk31）到测试平台顶层，
// 备注：  可逐轮观察子密钥是否正确生成
// 备注：
// 备注：加密模式与解密模式的区别：
// 备注：  加密模式：rk[0]~rk[31] 正向顺序
// 备注：  解密模式：rk[0]~rk[31] 反序（rk[31]~rk[0]），与加密顺序相反
// 备注：
// 备注：测试密钥：0123456789abcdeffedcba9876543210（与 tb_sm4_top 一致）


module tb_key_expansion(

    );
    
// 备注：控制与时钟信号 — 驱动 key_expansion 的输入接口
reg   clk                   ;
reg   reset_n               ;
reg   sm4_enable_in         ;
// 备注：加密/解密模式选择（0=加密，1=解密）
reg   encdec_sel_in         ;
reg   enable_key_exp_in     ;
reg   user_key_valid_in     ;
reg   [127: 0] user_key_in  ;

// 备注：密钥扩展完成标志
wire  key_exp_finished_out  ;
// 备注：32 轮子密钥输出（rk00~rk31），每轮 32 位
// 备注：加密时 rk00 为第 0 轮密钥，解密时 rk00 为第 31 轮密钥（反序）
// 备注：通过将轮密钥引出到顶层，可单独验证每轮子密钥的正确性
wire  [31 : 0] rk00_out     ;
wire  [31 : 0] rk01_out     ;
wire  [31 : 0] rk02_out     ;
wire  [31 : 0] rk03_out     ;
wire  [31 : 0] rk04_out     ;
wire  [31 : 0] rk05_out     ;
wire  [31 : 0] rk06_out     ;
wire  [31 : 0] rk07_out     ;
wire  [31 : 0] rk08_out     ;
wire  [31 : 0] rk09_out     ;
wire  [31 : 0] rk10_out     ;
wire  [31 : 0] rk11_out     ;
wire  [31 : 0] rk12_out     ;
wire  [31 : 0] rk13_out     ;
wire  [31 : 0] rk14_out     ;
wire  [31 : 0] rk15_out     ;
wire  [31 : 0] rk16_out     ;
wire  [31 : 0] rk17_out     ;
wire  [31 : 0] rk18_out     ;
wire  [31 : 0] rk19_out     ;
wire  [31 : 0] rk20_out     ;
wire  [31 : 0] rk21_out     ;
wire  [31 : 0] rk22_out     ;
wire  [31 : 0] rk23_out     ;
wire  [31 : 0] rk24_out     ;
wire  [31 : 0] rk25_out     ;
wire  [31 : 0] rk26_out     ;
wire  [31 : 0] rk27_out     ;
wire  [31 : 0] rk28_out     ;
wire  [31 : 0] rk29_out     ;
wire  [31 : 0] rk30_out     ;
wire  [31 : 0] rk31_out     ;   

// 备注：时钟生成 — 周期约 6ns
always #3 clk = ~clk;

// 备注：主测试流程 — 先加密模式密钥扩展，后解密模式密钥扩展
// 备注：两阶段之间插入复位操作，确保模块状态完全重置
initial
    begin
        // 备注：初始状态 — 所有信号置为默认值
        clk                 = 1'b0 ;
        reset_n             = 1'b0 ;
        sm4_enable_in		= 1'b0 ;
        enable_key_exp_in   = 1'b0 ; 
        encdec_sel_in       = 1'b0;
        user_key_in         = 128'h0 ;
        user_key_valid_in   = 1'b0 ;
        // 备注：第一阶段：加密模式密钥扩展（encdec_sel_in=0）
        // 备注：释放复位，使能 SM4
        #100;
        @(posedge clk) reset_n             = 1'b1 ;
        @(posedge clk) sm4_enable_in       = 1'b1 ;
        // 备注：使能密钥扩展
        #100;
        @(posedge clk) #1 enable_key_exp_in   = 1'b1 ;
        // 备注：加载 128 位用户密钥，等待模块采样
        #222;
        @(posedge clk)
        begin
            user_key_valid_in = 1'b1;
            user_key_in       = 128'h0123456789abcdeffedcba9876543210;
        end
        // 备注：撤销密钥写入信号
        @(posedge clk)
                begin
                    user_key_valid_in = 1'b0;
                    user_key_in       = 128'h0;
                end

        // 备注：等待密钥扩展完成（加密模式下生成正向轮密钥 rk[0..31]）
        wait(key_exp_finished_out);
        // 备注：第二阶段：解密模式密钥扩展（encdec_sel_in=1）
        // 备注：先复位模块，清除所有内部状态
        #200;
        reset_n             = 1'b0 ;
        sm4_enable_in		= 1'b0 ;
        enable_key_exp_in   = 1'b0 ; 
        encdec_sel_in       = 1'b1;
        user_key_in         = 128'h0 ;
        user_key_valid_in   = 1'b0 ;
        // 备注：重新使能，切换到解密模式
        #100;
        @(posedge clk) reset_n             = 1'b1 ;
        @(posedge clk) sm4_enable_in       = 1'b1 ;
        // 备注：重新使能密钥扩展
        #100;
        @(posedge clk) #1 enable_key_exp_in   = 1'b1 ;
        // 备注：再次加载相同密钥
        #222;
        @(posedge clk)
        begin
            user_key_valid_in = 1'b1;
            user_key_in       = 128'h0123456789abcdeffedcba9876543210;
        end
        @(posedge clk)
                begin
                    user_key_valid_in = 1'b0;
                    user_key_in       = 128'h0;
                end

        // 备注：等待密钥扩展完成（解密模式下生成反序轮密钥 rk[31..0]）
        wait(key_exp_finished_out);
        #200;
        
        $finish;
    end
        


// 备注：实例化被测模块 — key_expansion（SM4 密钥扩展模块）
// 备注：引出所有 32 轮密钥输出，便于在仿真波形中逐轮检查
key_expansion uut
	(
        .clk				    (clk				    ),
        .reset_n			    (reset_n			    ),
        .sm4_enable_in		    (sm4_enable_in		    ),
        .encdec_sel_in		    (encdec_sel_in		    ),
        .enable_key_exp_in	    (enable_key_exp_in	    ),
        .user_key_in		    (user_key_in		    ),
        .user_key_valid_in	    (user_key_valid_in	    ),
        .key_exp_finished_out   (key_exp_finished_out   ),
        .rk00_out			    (rk00_out			    ),
        .rk01_out			    (rk01_out			    ),
        .rk02_out			    (rk02_out			    ),
        .rk03_out			    (rk03_out			    ),
        .rk04_out			    (rk04_out			    ),
        .rk05_out			    (rk05_out			    ),
        .rk06_out			    (rk06_out			    ),
        .rk07_out			    (rk07_out			    ),
        .rk08_out			    (rk08_out			    ),
        .rk09_out			    (rk09_out			    ),
        .rk10_out			    (rk10_out			    ),
        .rk11_out			    (rk11_out			    ),
        .rk12_out			    (rk12_out			    ),
        .rk13_out			    (rk13_out			    ),
        .rk14_out			    (rk14_out			    ),
        .rk15_out			    (rk15_out			    ),
        .rk16_out			    (rk16_out			    ),
        .rk17_out			    (rk17_out			    ),
        .rk18_out			    (rk18_out			    ),
        .rk19_out			    (rk19_out			    ),
        .rk20_out			    (rk20_out			    ),
        .rk21_out			    (rk21_out			    ),
        .rk22_out			    (rk22_out			    ),
        .rk23_out			    (rk23_out			    ),
        .rk24_out			    (rk24_out			    ),
        .rk25_out			    (rk25_out			    ),
        .rk26_out			    (rk26_out			    ),
        .rk27_out			    (rk27_out			    ),
        .rk28_out			    (rk28_out			    ),
        .rk29_out			    (rk29_out			    ),
        .rk30_out			    (rk30_out			    ),
        .rk31_out			    (rk31_out			    )
    );	
endmodule
