`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Raymond Rui Chen, raymond.rui.chen@qq.com
// 
// Create Date: 2018/03/10 10:20:34
// Design Name: 
// Module Name: one_round_for_encdec
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
// 备注：SM4 一轮加密运算 (Feistel 结构):
// 备注：
// 备注：输入: (X0, X1, X2, X3) = data_in (4×32-bit)
// 备注：       rk = round_key_in (32-bit 轮密钥)
// 备注：
// 备注：计算过程:
// 备注：  1. tmp = X1 ^ X2 ^ X3 ^ rk        (32-bit 异或)
// 备注：  2. 非线性变换 τ: 将 tmp 分为 4 字节，
// 备注：     分别经过 S 盒替换得到 B = (S(a0),S(a1),S(a2),S(a3))
// 备注：  3. 线性变换 L: C = B ^ (B<<<2) ^ (B<<<10) ^ (B<<<18) ^ (B<<<24)
// 备注：  4. 输出: (X1, X2, X3, X0 ^ C)   — 128-bit 分组左移一字
// 备注：
// 备注：SM4 共 32 轮，最后一轮后对输出进行反序变换 R:
// 备注：  (Y0, Y1, Y2, Y3) = (X32_3, X32_2, X32_1, X32_0)
// 备注：
// 备注：解密: 使用与加密相同的轮函数，仅轮密钥顺序相反
module one_round_for_encdec(
		data_in,
		round_key_in,
		result_out
	);
input	[127:0]		data_in;
input	[31:0]		round_key_in;
output	[127:0]		result_out;

wire	[31:0]	word_0;
wire	[31:0]	word_1;
wire	[31:0]	word_2;
wire	[31:0]	word_3;
wire	[31:0]	tmp_0;
wire	[31:0]	tmp_1;
wire	[31:0]	data_for_transform;
wire	[31:0]	data_after_transform;

// 备注：将 128-bit 输入 data_in 拆分为 4 个 32-bit 字 (X0, X1, X2, X3)
assign { word_0, word_1, word_2, word_3} = data_in;
			
// 备注：异或计算第一步: X1 ^ X2
assign	tmp_0				=	word_1 ^ word_2;
// 备注：异或计算第二步: X3 ^ rk
assign	tmp_1				=	word_3 ^ round_key_in;
// 备注：完整的异或结果: tmp = (X1 ^ X2) ^ (X3 ^ rk)
// 备注：该结果送入 S 盒变换与线性变换 L
assign	data_for_transform	=	tmp_0 ^ tmp_1;
// 备注：一轮输出 = (X1, X2, X3, X0 ^ C)，即 128-bit 循环左移一字
assign	result_out			=	{word_1, word_2, word_3, data_after_transform ^ word_0}	;

transform_for_encdec u_transform	
	(
		.data_in(data_for_transform),
		.result_out(data_after_transform)
	);
	
endmodule	