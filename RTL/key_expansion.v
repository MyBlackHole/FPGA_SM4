`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Raymond Rui Chen, raymond.rui.chen@qq.com
// 
// Create Date: 2018/03/09 20:56:10
// Design Name: FPGA_SM4
// Module Name: key_expansion
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
//      KEY expansion of SM4 encryption algorithm
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
// 备注：SM4 密钥扩展算法流程：
// 备注：┌───────────────────────────────────────────────────────────────────────┐
// 备注：│ 1. 输入 128-bit 用户密钥 MK = (MK0, MK1, MK2, MK3)                   │
// 备注：│ 2. 与系统参数 FK 异或: (K0,K1,K2,K3) = MK ^ FK                       │
// 备注：│ 3. 对 i=0..31 迭代计算:                                              │
// 备注：│    rk_i = K_{i+4} = K_i ^ T'(K_{i+1}^K_{i+2}^K_{i+3}^CK_i)          │
// 备注：│ 4. 输出 32 个 32-bit 轮密钥 rk_00 ~ rk_31                            │
// 备注：└───────────────────────────────────────────────────────────────────────┘
// 备注：图例：T' = 非线性变换τ(S盒) + 线性变换L'
// 备注：      FK = 系统参数常量 (FK0~FK3)
// 备注：      CK_i = 轮常量，每轮不同
module key_expansion
	(
        clk					,
        reset_n				,
        sm4_enable_in		,
        encdec_sel_in       ,
        enable_key_exp_in	,
        user_key_in			,
        user_key_valid_in	,
        key_exp_finished_out,
        rk00_out			,
        rk01_out			,
        rk02_out			,
        rk03_out			,
        rk04_out			,
        rk05_out			,
        rk06_out			,
        rk07_out			,
        rk08_out			,
        rk09_out			,
        rk10_out			,
        rk11_out			,
        rk12_out			,
        rk13_out			,
        rk14_out			,
        rk15_out			,
        rk16_out			,
        rk17_out			,
        rk18_out			,
        rk19_out			,
        rk20_out			,
        rk21_out			,
        rk22_out			,
        rk23_out			,
        rk24_out			,
        rk25_out			,
        rk26_out			,
        rk27_out			,
        rk28_out			,
        rk29_out			,
        rk30_out			,
        rk31_out			
);

input   clk                     ;
input   reset_n                 ;
input   sm4_enable_in           ;
input   encdec_sel_in           ;
input   enable_key_exp_in       ;
input   user_key_valid_in       ;
input   [127: 0]     user_key_in;

output  reg key_exp_finished_out;
output  reg [31 : 0] rk00_out;
output  reg [31 : 0] rk01_out;
output  reg [31 : 0] rk02_out;
output  reg [31 : 0] rk03_out;
output  reg [31 : 0] rk04_out;
output  reg [31 : 0] rk05_out;
output  reg [31 : 0] rk06_out;
output  reg [31 : 0] rk07_out;
output  reg [31 : 0] rk08_out;
output  reg [31 : 0] rk09_out;
output  reg [31 : 0] rk10_out;
output  reg [31 : 0] rk11_out;
output  reg [31 : 0] rk12_out;
output  reg [31 : 0] rk13_out;
output  reg [31 : 0] rk14_out;
output  reg [31 : 0] rk15_out;
output  reg [31 : 0] rk16_out;
output  reg [31 : 0] rk17_out;
output  reg [31 : 0] rk18_out;
output  reg [31 : 0] rk19_out;
output  reg [31 : 0] rk20_out;
output  reg [31 : 0] rk21_out;
output  reg [31 : 0] rk22_out;
output  reg [31 : 0] rk23_out;
output  reg [31 : 0] rk24_out;
output  reg [31 : 0] rk25_out;
output  reg [31 : 0] rk26_out;
output  reg [31 : 0] rk27_out;
output  reg [31 : 0] rk28_out;
output  reg [31 : 0] rk29_out;
output  reg [31 : 0] rk30_out;
output  reg [31 : 0] rk31_out;

reg     [127 : 0]   reg_user_key;
reg     [1   : 0]   current;
reg     [1   : 0]   next;
reg     [4   : 0]   count_round;
reg     [4   : 0]   reg_count_round;
wire    [4   : 0]   count_for_reg;
reg		[127 : 0]	reg_data_after_round;
reg     			reg_user_key_valid = 1'b0;
reg					reg_enable_key_exp;
wire    [31  : 0]  	cki;
wire	[127 : 0]	data_for_round;
wire	[127 : 0]	data_after_round;


always@(posedge clk)
if(!reset_n)
	reg_user_key_valid <= 1'b0;
else 
	reg_user_key_valid <= user_key_valid_in;
        
        
        
always@(posedge clk or negedge reset_n)
begin
	if(~reset_n)
    	reg_enable_key_exp <= 1'b0;
	else 
		reg_enable_key_exp <= enable_key_exp_in;
end

    
// 备注：FSM 状态定义
// 备注：IDLE — 空闲态，等待密钥扩展使能
// 备注：KEY_EXPANSION — 密钥扩展态，迭代 32 轮计算轮密钥
`define IDLE          2'b00
`define KEY_EXPANSION 2'b01

reg [63:0] ke_state_name;
always @(*) begin
    case (current)
        `IDLE:          ke_state_name = "IDLE";
        `KEY_EXPANSION: ke_state_name = "KEY_EXP";
        default:        ke_state_name = "?";
    endcase
end

always@(posedge clk or negedge reset_n)
if(!reset_n)
	current	<=	`IDLE;
else if(sm4_enable_in)
	current	<=	next;
else
	current	<=	`IDLE;

// 备注：状态转移逻辑 — 进入密钥扩展的条件
// 备注：IDLE下 enable_key_exp_in 有效且用户密钥缓存完成时跳转
always@(*) 
begin
	next = `IDLE;
	case(current)
		`IDLE:	
			if(enable_key_exp_in && ~reg_user_key_valid && user_key_valid_in )
				next = `KEY_EXPANSION;
			else
				next = `IDLE;
							
		`KEY_EXPANSION:
			if( reg_count_round == 5'd31)
				next =	`IDLE;
			else
				next =	`KEY_EXPANSION;
										
		default:	
				next =	`IDLE;
	endcase
end


// 备注：轮计数器 count_round — 每轮递增，0~31 共 32 轮
always@(posedge clk or negedge reset_n)
if(!reset_n)
	count_round	<=	5'd0;
else if(next == `KEY_EXPANSION)
	count_round	<=	count_round	+	1'b1;
else 
	count_round <=	5'd0;


always@(posedge clk or negedge reset_n)
begin
    if(!reset_n)
        reg_count_round <= 5'd0;
    else
        reg_count_round <= count_round;
end

    
reg ke_was_key_exp;
always @(posedge clk) begin
    ke_was_key_exp <= (current == `KEY_EXPANSION);
end

always@(posedge clk or negedge reset_n)
if(!reset_n)
	key_exp_finished_out <=	1'd0;
else if(~sm4_enable_in || ~enable_key_exp_in && reg_enable_key_exp)
    key_exp_finished_out <=	1'd0;
else if(current == `KEY_EXPANSION && next == `IDLE) begin
	key_exp_finished_out <=	1'b1;
	$display("[%0t] key_exp: FINISHED (cnt=%d, reg_cnt=%d)", $time, count_round, reg_count_round);
end

// Debug: print on KEY_EXPANSION entry and finish
always @(posedge clk) begin
    if (current == `KEY_EXPANSION && !ke_was_key_exp)
        $display("[%0t] key_exp: ENTERED (en_key_exp=%b reg_ukv=%b ukv=%b cnt=%d rcnt=%d)",
                 $time, enable_key_exp_in, reg_user_key_valid, user_key_valid_in,
                 count_round, reg_count_round);
end

always@(posedge clk or negedge reset_n)
if(!reset_n)
	reg_user_key <= 128'h0;
else if(~reg_user_key_valid && user_key_valid_in)
	reg_user_key <= user_key_in;
	
	

// 备注：每轮输入数据选择 — round 0 使用用户密钥，后续轮使用上一轮计算结果
assign	data_for_round = reg_count_round != 5'd0 ?	reg_data_after_round : reg_user_key; 


get_cki	u_get_cki
	(
        .clk(clk),
		.count_round_in(count_round),
		.cki_out(cki)
	);


one_round_for_key_exp	u_one_round	
	(	
		.count_round_in(reg_count_round),
		.data_in(data_for_round),
		.ck_parameter_in(cki),
		.result_out(data_after_round)
	);

    
always@(posedge clk or negedge reset_n)
if(!reset_n)
	reg_data_after_round <=	128'd0;
else if(current == `KEY_EXPANSION)
	reg_data_after_round <=	data_after_round;

    
// 备注：encdec_sel_in 控制轮密钥顺序：
// 备注：加密(encdec_sel_in=0): 直接顺序 rk_00~rk_31
// 备注：解密(encdec_sel_in=1): 逆序 rk_31~rk_00 (31 - reg_count_round)
assign count_for_reg = encdec_sel_in == 1'b0 ? reg_count_round : 5'b1_1111 -  reg_count_round;   
    
// 备注：每个时钟周期捕获一个轮密钥到对应 rk 寄存器
// 备注：count_for_reg 值决定当前结果写入哪个 rk 寄存器
always@(posedge clk or negedge reset_n)
begin
if(!reset_n) begin
	rk00_out <=	32'd0;
	rk01_out <=	32'd0;
	rk02_out <=	32'd0;
	rk03_out <=	32'd0;
	rk04_out <=	32'd0;
	rk05_out <=	32'd0;
	rk06_out <=	32'd0;
	rk07_out <=	32'd0;
	rk08_out <=	32'd0;
	rk09_out <=	32'd0;
	rk10_out <=	32'd0;
	rk11_out <=	32'd0;
	rk12_out <=	32'd0;
	rk13_out <=	32'd0;
	rk14_out <=	32'd0;
	rk15_out <=	32'd0;
	rk16_out <=	32'd0;
	rk17_out <=	32'd0;
	rk18_out <=	32'd0;
	rk19_out <=	32'd0;
	rk20_out <=	32'd0;
	rk21_out <=	32'd0;
	rk22_out <=	32'd0;
	rk23_out <=	32'd0;
	rk24_out <=	32'd0;
	rk25_out <=	32'd0;
	rk26_out <=	32'd0;
	rk27_out <=	32'd0;
	rk28_out <=	32'd0;
	rk29_out <=	32'd0;
	rk30_out <=	32'd0;
	rk31_out <=	32'd0;
end
else begin
	rk00_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_0000	?	data_after_round[31:0]	:	rk00_out;										
	rk01_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_0001	?	data_after_round[31:0]	:	rk01_out;
	rk02_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_0010	?	data_after_round[31:0]	:	rk02_out;
	rk03_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_0011	?	data_after_round[31:0]	:	rk03_out;
	rk04_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_0100	?	data_after_round[31:0]	:	rk04_out;
	rk05_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_0101	?	data_after_round[31:0]	:	rk05_out;
	rk06_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_0110	?	data_after_round[31:0]	:	rk06_out;
	rk07_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_0111	?	data_after_round[31:0]	:	rk07_out;
	rk08_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_1000	?	data_after_round[31:0]	:	rk08_out;
	rk09_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_1001	?	data_after_round[31:0]	:	rk09_out;
	rk10_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_1010	?	data_after_round[31:0]	:	rk10_out;
	rk11_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_1011	?	data_after_round[31:0]	:	rk11_out;
	rk12_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_1100	?	data_after_round[31:0]	:	rk12_out;
	rk13_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_1101	?	data_after_round[31:0]	:	rk13_out;
	rk14_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_1110	?	data_after_round[31:0]	:	rk14_out;
	rk15_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b0_1111	?	data_after_round[31:0]	:	rk15_out;
	rk16_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_0000	?	data_after_round[31:0]	:	rk16_out;
	rk17_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_0001	?	data_after_round[31:0]	:	rk17_out;
	rk18_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_0010	?	data_after_round[31:0]	:	rk18_out;
	rk19_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_0011	?	data_after_round[31:0]	:	rk19_out;
	rk20_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_0100	?	data_after_round[31:0]	:	rk20_out;
	rk21_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_0101	?	data_after_round[31:0]	:	rk21_out;
	rk22_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_0110	?	data_after_round[31:0]	:	rk22_out;
	rk23_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_0111	?	data_after_round[31:0]	:	rk23_out;
	rk24_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_1000	?	data_after_round[31:0]	:	rk24_out;
	rk25_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_1001	?	data_after_round[31:0]	:	rk25_out;
	rk26_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_1010	?	data_after_round[31:0]	:	rk26_out;
	rk27_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_1011	?	data_after_round[31:0]	:	rk27_out;
	rk28_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_1100	?	data_after_round[31:0]	:	rk28_out;
	rk29_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_1101	?	data_after_round[31:0]	:	rk29_out;
	rk30_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_1110	?	data_after_round[31:0]	:	rk30_out;
	rk31_out <=	current == `KEY_EXPANSION && count_for_reg == 5'b1_1111	?	data_after_round[31:0]	:	rk31_out;
	end
end

endmodule





