`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Raymond Rui Chen, raymond.rui.chen@qq.com
// 
// Create Date: 2018/03/10 12:06:49
// Design Name: 
// Module Name: sm4_top
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
// 备注：SM4 算法顶层模块
// 备注：
// 备注：SM4 为国密标准 128 位分组密码算法，密钥长度 128 位，采用 32 轮迭代结构。
// 备注：本模块作为顶层封装，连接两个核心子模块：
// 备注：  1. key_expansion —— 将 128 位用户密钥扩展为 32 个 32 位轮密钥 rk_00~rk_31
// 备注：  2. sm4_encdec_4round —— 使用轮密钥对 128 位数据进行 32 轮加密/解密
// 备注：
// 备注：数据流：
// 备注：  user_key_in → key_expansion → rk_00~rk_31 → sm4_encdec_4round → result_out
// 备注：  data_in    → sm4_encdec_4round ────────────────────────────────→ result_out
// 备注：
// 备注：key_cached_in 信号可跳过密钥扩展阶段，直接使用外部已缓存的轮密钥，
// 备注：适用于连续加密/解密时复用同一组轮密钥的场景。
module sm4_top(
    clk		            ,
    reset_n	            ,
    sm4_enable_in       ,
    encdec_enable_in    ,
    encdec_sel_in       ,
    valid_in            ,
    data_in             ,
    enable_key_exp_in   ,
    user_key_valid_in   ,
    user_key_in         ,
    key_cached_in       ,
    key_exp_ready_out   ,
    ready_out           ,
    result_out         
);
    
    // 备注：系统时钟，所有操作同步于时钟上升沿
    input			 clk		        ;
    // 备注：系统复位，低电平有效
    input			 reset_n	        ;
    // 备注：SM4 核心使能信号，高电平时模块开始工作
    input            sm4_enable_in      ;
    // 备注：加密/解密使能信号，高电平时允许加密或解密操作
    input            encdec_enable_in   ;
    // 备注：加密/解密选择，0=加密，1=解密
    input            encdec_sel_in      ;
    // 备注：输入数据有效信号，高电平时 data_in 有效
    input            valid_in           ;
    // 备注：128 位输入数据（明文/密文）
    input   [127: 0] data_in            ;
    // 备注：密钥扩展使能信号，高电平时启动密钥扩展
    input            enable_key_exp_in  ;
    // 备注：用户密钥有效信号，高电平时 user_key_in 有效
    input            user_key_valid_in  ;
    // 备注：128 位用户密钥
    input   [127: 0] user_key_in        ;
    // 备注：跳过密钥扩展，使用已缓存的轮密钥
    input            key_cached_in      ;  // 1=skip key expansion, use cached keys
    // 备注：模块就绪信号，高电平时可接收下一组数据
    output           ready_out          ;
    // 备注：128 位加密/解密结果输出
    output  [127: 0] result_out         ;
    
    // 备注：密钥扩展完成信号，高电平表示 32 个轮密钥已生成
    output           key_exp_ready_out  ;
    wire    [31 : 0] rk_00              ;
    wire    [31 : 0] rk_01              ;
    wire    [31 : 0] rk_02              ;
    wire    [31 : 0] rk_03              ;
    wire    [31 : 0] rk_04              ;
    wire    [31 : 0] rk_05              ;
    wire    [31 : 0] rk_06              ;
    wire    [31 : 0] rk_07              ;
    wire    [31 : 0] rk_08              ;
    wire    [31 : 0] rk_09              ;
    wire    [31 : 0] rk_10              ;
    wire    [31 : 0] rk_11              ;
    wire    [31 : 0] rk_12              ;
    wire    [31 : 0] rk_13              ;
    wire    [31 : 0] rk_14              ;
    wire    [31 : 0] rk_15              ;
    wire    [31 : 0] rk_16              ;
    wire    [31 : 0] rk_17              ;
    wire    [31 : 0] rk_18              ;
    wire    [31 : 0] rk_19              ;
    wire    [31 : 0] rk_20              ;
    wire    [31 : 0] rk_21              ;
    wire    [31 : 0] rk_22              ;
    wire    [31 : 0] rk_23              ;
    wire    [31 : 0] rk_24              ;
    wire    [31 : 0] rk_25              ;
    wire    [31 : 0] rk_26              ;
    wire    [31 : 0] rk_27              ;
    wire    [31 : 0] rk_28              ;
    wire    [31 : 0] rk_29              ;
    wire    [31 : 0] rk_30              ;
    wire    [31 : 0] rk_31              ;
    
    // 备注：密钥就绪信号 = 密钥扩展完成 或 使用缓存轮密钥
    // 备注：当 key_ready 为高时，加密/解密引擎可开始处理数据
    wire key_ready = key_exp_ready_out || key_cached_in;

    // 备注：加密/解密引擎实例化
    // 备注：sm4_encdec_4round 模块实现 32 轮迭代加密/解密，每轮使用一个 32 位轮密钥
    // 备注：采用 4 轮流水线架构，每周期完成 4 轮运算，8 个时钟周期完成全部 32 轮
    sm4_encdec_4round u_encdec (
        .clk                    (clk                 ),
        .reset_n                (reset_n             ),
        .sm4_enable_in          (sm4_enable_in       ),
        .encdec_enable_in       (encdec_enable_in    ),
        .key_exp_ready_in       (key_ready           ),
        .valid_in               (valid_in            ),
        .data_in                (data_in             ),
        .rk_00_in               (rk_00               ),
        .rk_01_in               (rk_01               ),
        .rk_02_in               (rk_02               ),
        .rk_03_in               (rk_03               ),
        .rk_04_in               (rk_04               ),
        .rk_05_in               (rk_05               ),
        .rk_06_in               (rk_06               ),
        .rk_07_in               (rk_07               ),
        .rk_08_in               (rk_08               ),
        .rk_09_in               (rk_09               ),
        .rk_10_in               (rk_10               ),
        .rk_11_in               (rk_11               ),
        .rk_12_in               (rk_12               ),
        .rk_13_in               (rk_13               ),
        .rk_14_in               (rk_14               ),
        .rk_15_in               (rk_15               ),
        .rk_16_in               (rk_16               ),
        .rk_17_in               (rk_17               ),
        .rk_18_in               (rk_18               ),
        .rk_19_in               (rk_19               ),
        .rk_20_in               (rk_20               ),
        .rk_21_in               (rk_21               ),
        .rk_22_in               (rk_22               ),
        .rk_23_in               (rk_23               ),
        .rk_24_in               (rk_24               ),
        .rk_25_in               (rk_25               ),
        .rk_26_in               (rk_26               ),
        .rk_27_in               (rk_27               ),
        .rk_28_in               (rk_28               ),
        .rk_29_in               (rk_29               ),
        .rk_30_in               (rk_30               ),
        .rk_31_in               (rk_31               ),
        .ready_out              (ready_out           ),
        .result_out             (result_out          )
    );
    
    // 备注：密钥扩展模块实例化
    // 备注：key_expansion 将 128 位用户密钥扩展为 32 个 32 位轮密钥 rk_00 ~ rk_31
    // 备注：加密时轮密钥按 rk_00~rk_31 顺序使用，解密时逆向使用（rk_31~rk_00）
    // 备注：扩展完成时 key_exp_finished_out 输出高电平信号
    key_expansion u_key
	(
        .clk					(clk					),
        .reset_n				(reset_n				),
        .sm4_enable_in		    (sm4_enable_in		    ),
        .encdec_sel_in		    (encdec_sel_in		    ),
        .enable_key_exp_in	    (enable_key_exp_in	    ),
        .user_key_in			(user_key_in			),
        .user_key_valid_in	    (user_key_valid_in	    ),
        .key_exp_finished_out   (key_exp_ready_out      ),
        .rk00_out			    (rk_00    			    ),
        .rk01_out			    (rk_01    			    ),
        .rk02_out			    (rk_02    			    ),
        .rk03_out			    (rk_03    			    ),
        .rk04_out			    (rk_04    			    ),
        .rk05_out			    (rk_05    			    ),
        .rk06_out			    (rk_06    			    ),
        .rk07_out			    (rk_07    			    ),
        .rk08_out			    (rk_08    			    ),
        .rk09_out			    (rk_09    			    ),
        .rk10_out			    (rk_10    			    ),
        .rk11_out			    (rk_11    			    ),
        .rk12_out			    (rk_12    			    ),
        .rk13_out			    (rk_13    			    ),
        .rk14_out			    (rk_14    			    ),
        .rk15_out			    (rk_15    			    ),
        .rk16_out			    (rk_16    			    ),
        .rk17_out			    (rk_17    			    ),
        .rk18_out			    (rk_18    			    ),
        .rk19_out			    (rk_19    			    ),
        .rk20_out			    (rk_20    			    ),
        .rk21_out			    (rk_21    			    ),
        .rk22_out			    (rk_22    			    ),
        .rk23_out			    (rk_23    			    ),
        .rk24_out			    (rk_24    			    ),
        .rk25_out			    (rk_25    			    ),
        .rk26_out			    (rk_26    			    ),
        .rk27_out			    (rk_27    			    ),
        .rk28_out			    (rk_28    			    ),
        .rk29_out			    (rk_29    			    ),
        .rk30_out			    (rk_30    			    ),
        .rk31_out			    (rk_31    			    )
    );
    
endmodule
