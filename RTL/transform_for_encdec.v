`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Raymond Rui Chen, raymond.rui.chen@qq.com
// 
// Create Date: 2018/03/10 10:22:18
// Design Name: 
// Module Name: transform_for_encdec
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
// 备注：SM4 加密/解密线性变换 L
// 备注：
// 备注：输入: data_in = τ(X) = S 盒替换后的 32-bit 输出 B
// 备注：输出: C = L(B) = B ^ (B<<<2) ^ (B<<<10) ^ (B<<<18) ^ (B<<<24)
// 备注：
// 备注：L 是线性变换，配合 S 盒的 τ 非线性变换构成一轮的混淆层
module transform_for_encdec(
		data_in,
		result_out
	);
input	[31:0]	data_in;
output	[31:0]	result_out;			

wire	[7:0]	byte_0;
wire	[7:0]	byte_1;
wire	[7:0]	byte_2;
wire	[7:0]	byte_3;
wire	[7:0]	byte_0_replaced;
wire	[7:0]	byte_1_replaced;
wire	[7:0]	byte_2_replaced;
wire	[7:0]	byte_3_replaced;
wire	[31:0]	word_replaced;
wire	[31:0]	data_after_linear;
wire	[31:0]	data_after_linear_key;

assign	{ byte_0, byte_1, byte_2, byte_3 } = data_in;
assign	word_replaced = {byte_0_replaced, byte_1_replaced, byte_2_replaced,byte_3_replaced};

// 备注：τ 变换：将 32-bit 输入 data_in 拆分为 4 个字节，
// 备注：分别送入 S 盒进行非线性替换，合并后得到 32-bit B
sbox_replace	u_0
	(
		.data_in(byte_0),
		.result_out(byte_0_replaced)														
	);
	
sbox_replace	u_1
	(
		.data_in(byte_1),
		.result_out(byte_1_replaced)														
	);
	
sbox_replace	u_2
	(
		.data_in(byte_2),
		.result_out(byte_2_replaced)														
	);
	
sbox_replace	u_3
	(
		.data_in(byte_3),
		.result_out(byte_3_replaced)														
	);	

// 备注：L 变换：C = L(B) = B ^ (B<<<2) ^ (B<<<10) ^ (B<<<18) ^ (B<<<24)
// 备注：通过拼接操作实现循环左移，并与原值异或
// 备注：B<<<2  = {B[29:0], B[31:30]}
// 备注：B<<<10 = {B[21:0], B[31:22]}
// 备注：B<<<18 = {B[13:0], B[31:14]}
// 备注：B<<<24 = {B[7:0], B[31:8]}
assign	result_out = ( 	 (word_replaced ^ {word_replaced[29:0], word_replaced[31:30]}) 
                       ^ ({word_replaced[21:0], word_replaced[31:22]} ^ {word_replaced[13:0], word_replaced[31:14]})) 
				   ^ {word_replaced[7:0], word_replaced[31:8]};
													
endmodule		