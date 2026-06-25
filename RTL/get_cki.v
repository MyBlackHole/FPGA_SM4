`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Raymond Rui Chen, raymond.rui.chen@qq.com
// 
// Create Date: 2018/03/09 21:11:26
// Design Name: 
// Module Name: get_cki
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
// 备注：SM4 轮常量 CK_i 生成
// 备注：
// 备注：CK_i 是 SM4 密钥扩展中使用的 32-bit 轮常量
// 备注：对 i=0..31，CK_i = (ck_{i,0}, ck_{i,1}, ck_{i,2}, ck_{i,3})
// 备注：其中 ck_{i,j} = (2i + j) * 7 mod 256
// 备注：
// 备注：CK_i 的作用是在密钥扩展的异或运算中引入轮序号信息，
// 备注：防止不同轮次使用相同的密钥调度模式
module get_cki	
	(
		clk,
    	count_round_in,
		cki_out
	);
				
input   clk;
input	[4 :0]	count_round_in;
output	[31:0]	cki_out;

reg [31 : 0] cki_out;
    
// 备注：根据轮序号 count_round_in 查表输出对应的 CK_i 常量
// 备注：i=0..31 对应 count_round_in=0..31，共 32 个轮常量
// 备注：CK_i 的值由公式 ck_{i,j} = (2i + j) * 7 mod 256 逐字节计算得出
always@(posedge clk)
	case(count_round_in)
		5'b0_0000:	cki_out	<=	32'h00070e15;
		5'b0_0001:	cki_out	<=	32'h1c232a31;
		5'b0_0010:	cki_out	<=	32'h383f464d;
		5'b0_0011:	cki_out	<=	32'h545b6269;
		5'b0_0100:	cki_out	<=	32'h70777e85;
		5'b0_0101:	cki_out	<=	32'h8c939aa1;
		5'b0_0110:	cki_out	<=	32'ha8afb6bd;
		5'b0_0111:	cki_out	<=	32'hc4cbd2d9;
		5'b0_1000:	cki_out	<=	32'he0e7eef5;
		5'b0_1001:	cki_out	<=	32'hfc030a11;
		5'b0_1010:	cki_out	<=	32'h181f262d;
		5'b0_1011:	cki_out	<=	32'h343b4249;
		5'b0_1100:	cki_out	<=	32'h50575e65;
		5'b0_1101:	cki_out	<=	32'h6c737a81;
		5'b0_1110:	cki_out	<=	32'h888f969d;
		5'b0_1111:	cki_out	<=	32'ha4abb2b9;
		5'b1_0000:	cki_out	<=	32'hc0c7ced5;
		5'b1_0001:	cki_out	<=	32'hdce3eaf1;
		5'b1_0010:	cki_out	<=	32'hf8ff060d;
		5'b1_0011:	cki_out	<=	32'h141b2229;
		5'b1_0100:	cki_out	<=	32'h30373e45;
		5'b1_0101:	cki_out	<=	32'h4c535a61;
		5'b1_0110:	cki_out	<=	32'h686f767d;
		5'b1_0111:	cki_out	<=	32'h848b9299;
		5'b1_1000:	cki_out	<=	32'ha0a7aeb5;
		5'b1_1001:	cki_out	<=	32'hbcc3cad1;
		5'b1_1010:	cki_out	<=	32'hd8dfe6ed;
		5'b1_1011:	cki_out	<=	32'hf4fb0209;
		5'b1_1100:	cki_out	<=	32'h10171e25;
		5'b1_1101:	cki_out	<=	32'h2c333a41;
		5'b1_1110:	cki_out	<=	32'h484f565d;
		5'b1_1111:	cki_out	<=	32'h646b7279;
		default:	cki_out	<=	32'h0;
	endcase

endmodule
