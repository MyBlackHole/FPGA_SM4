`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Raymond Rui Chen, raymond.rui.chen@qq.com
// 
// Create Date: 2018/03/09 21:13:57
// Design Name: 
// Module Name: one_round_for_key_exp
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


// 备注：SM4 密钥扩展 — 单轮运算模块
// 备注：
// 备注：统观图 (One Round Key Expansion Flow):
// 备注：  data_in[127:0]  ──┬──→ word_0 ──⊕ FK0 ──→ k0 ──┐
// 备注：                    ├──→ word_1 ──⊕ FK1 ──→ k1 ──┤
// 备注：                    ├──→ word_2 ──⊕ FK2 ──→ k2 ──┤          ┌──────────────────┐
// 备注：                    └──→ word_3 ──⊕ FK3 ──→ k3 ──┤──round0?─→│ tmp = (k1^k2)     │
// 备注：                                                         │      ^ (k3^ck)      │
// 备注：  ck_parameter_in[31:0] ────────────────────────────┘      └────────┬─────────┘
// 备注：                                                                   │
// 备注：  (后续轮) word_1^word_2 ^ word_3^ck ──────────────────────────────┤
// 备注：                                                                   ▼
// 备注：  data_for_transform ═══▶ transform_for_key_exp (S盒 + L') ═══▶ data_after_transform_key
// 备注：                                                                   │
// 备注：                                                                   ▼
// 备注：                      result_out = round0 ? {k1,k2,k3, C^k0} : {word_1,word_2,word_3, C^word_0}
// 备注：
// 备注：SM4 密钥扩展算法公式:
// 备注：  系统参数 FK (用于初始 XOR):
// 备注：    FK0 = 0xa3b1bac6, FK1 = 0x56aa3350, FK2 = 0x677d9197, FK3 = 0xb27022dc
// 备注：
// 备注：  密钥扩展步骤:
// 备注：    1. (K0,K1,K2,K3) = (MK0^FK0, MK1^FK1, MK2^FK2, MK3^FK3)
// 备注：    2. for i = 0..31:
// 备注：       B = τ(K_{i+1} ^ K_{i+2} ^ K_{i+3} ^ CK_i)     ← S 盒替换
// 备注：       L': C = B ^ (B <<< 13) ^ (B <<< 23)           ← 线性变换(与加密的 L 不同)
// 备注：       rk_i = K_{i+4} = K_i ^ C
// 备注：
// 备注：注意: 加密轮函数使用 L 变换，密钥扩展使用 L' 变换（移位量不同）
// 备注：  L:   C = B ^ (B<<<2) ^ (B<<<10) ^ (B<<<18) ^ (B<<<24)
// 备注：  L':  C = B ^ (B<<<13) ^ (B<<<23)
// 备注：
// 备注：本模块负责一轮运算，外部通过 count_round_in = 0 标记第一轮。
// 备注：第一轮使用 MK^FK 初始化 K 值，后续轮直接使用上一轮输出的 word 值。
module one_round_for_key_exp
	(
		count_round_in,
		data_in,
		ck_parameter_in,
		result_out
	);

input	[127 : 0]	data_in;
input	[31  : 0]	ck_parameter_in;
input 	[4   : 0] 	count_round_in;

output	[127 : 0]	result_out;


// 备注：SM4 标准系统参数 FK，用于第一轮密钥初始化
// 备注：FK0=0xa3b1bac6, FK1=0x56aa3350, FK2=0x677d9197, FK3=0xb27022dc
// 备注：第一轮: K_i = MK_i ^ FK_i
localparam FK0	=	32'ha3b1bac6;
localparam FK1	=	32'h56aa3350;
localparam FK2	=	32'h677d9197;
localparam FK3	=	32'hb27022dc;

wire	[31:0]	word_0;
wire	[31:0]	word_1;
wire	[31:0]	word_2;
wire	[31:0]	word_3;
wire	[31:0]	tmp_0;
wire	[31:0]	tmp_1;
wire	[31:0]	data_for_xor;
wire	[31:0]	data_for_transform;
wire	[31:0]	data_after_transform_key;
wire	[31:0]	k0;
wire	[31:0]	k1;
wire	[31:0]	k2;
wire	[31:0]	k3;

// 备注：将 128-bit 输入拆分为 4 个 32-bit 字
// 备注：data_in[127:96]=word_0, [95:64]=word_1, [63:32]=word_2, [31:0]=word_3
assign	{	word_0,
			word_1,
			word_2,
			word_3}	=	data_in;

// 备注：第一轮用 MK ^ FK 初始化 K0~K3
// 备注：K_i = MK_i ^ FK_i，之后每轮更新 K_{i+4} = K_i ^ C
assign	k0					=	word_0^FK0;
assign	k1					=	word_1^FK1;
assign	k2					=	word_2^FK2;
assign	k3					=	word_3^FK3;
assign	data_for_xor		=	ck_parameter_in;
// 备注：tmp_0 = 第一轮用 k1^k2，后续轮直接使用上一轮的 word_1^word_2
assign	tmp_0				=	count_round_in == 'd0 ? k1^k2 : word_1^word_2;
// 备注：tmp_1 = 第一轮用 k3^ck，后续轮使用 word_3^ck (ck=ck_parameter_in)
assign	tmp_1				=	count_round_in == 'd0 ? k3^data_for_xor	: word_3^data_for_xor;
// 备注：完整的异或输入: data_for_transform = tmp_0 ^ tmp_1
// 备注：相当于 K_{i+1} ^ K_{i+2} ^ K_{i+3} ^ CK_i，送入 S 盒变换
assign	data_for_transform	=	tmp_0 ^ tmp_1;

// 备注：输出组合：
// 备注：  第一轮(count=0): {k1, k2, k3, C^k0} — 用 FK 初始化后的 K1~K3 + C^K0
// 备注：  后续轮:         {word_1, word_2, word_3, C^word_0} — 直接使用输出反馈
// 备注：  其中 C = data_after_transform_key = L'(τ(data_for_transform))
assign	result_out			=	count_round_in == 'd0	?
								{k1, k2, k3, data_after_transform_key ^ k0}:
								{word_1, word_2, word_3, data_after_transform_key ^ word_0};

transform_for_key_exp	u_transform_key
	(
		.data_in(data_for_transform),
		.data_after_linear_key_out(data_after_transform_key)
	);

	
endmodule
						
