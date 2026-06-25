`timescale 1ns / 100ps

module sm4_encdec_4round(
    clk,
    reset_n,
    sm4_enable_in,
    encdec_enable_in,
    key_exp_ready_in,
    valid_in,
    data_in,
    rk_00_in, rk_01_in, rk_02_in, rk_03_in,
    rk_04_in, rk_05_in, rk_06_in, rk_07_in,
    rk_08_in, rk_09_in, rk_10_in, rk_11_in,
    rk_12_in, rk_13_in, rk_14_in, rk_15_in,
    rk_16_in, rk_17_in, rk_18_in, rk_19_in,
    rk_20_in, rk_21_in, rk_22_in, rk_23_in,
    rk_24_in, rk_25_in, rk_26_in, rk_27_in,
    rk_28_in, rk_29_in, rk_30_in, rk_31_in,
    ready_out,
    result_out
);
    input               clk;
    input               reset_n;
    input               sm4_enable_in;
    input               encdec_enable_in;
    input               key_exp_ready_in;
    input               valid_in;
    input   [127:0]     data_in;
    input   [31:0]      rk_00_in, rk_01_in, rk_02_in, rk_03_in;
    input   [31:0]      rk_04_in, rk_05_in, rk_06_in, rk_07_in;
    input   [31:0]      rk_08_in, rk_09_in, rk_10_in, rk_11_in;
    input   [31:0]      rk_12_in, rk_13_in, rk_14_in, rk_15_in;
    input   [31:0]      rk_16_in, rk_17_in, rk_18_in, rk_19_in;
    input   [31:0]      rk_20_in, rk_21_in, rk_22_in, rk_23_in;
    input   [31:0]      rk_24_in, rk_25_in, rk_26_in, rk_27_in;
    input   [31:0]      rk_28_in, rk_29_in, rk_30_in, rk_31_in;
    output              ready_out;
    output  [127:0]     result_out;

    localparam IDLE            = 2'b00;
    localparam WAITING_FOR_KEY = 2'b01;
    localparam ENCRYPTION      = 2'b10;

    reg [1:0] current, next_state;

    always @(posedge clk or negedge reset_n)
        if (!reset_n) current <= IDLE;
        else if (sm4_enable_in) current <= next_state;

    always @(*) begin
        next_state = IDLE;
        case (current)
            IDLE:            if (sm4_enable_in && encdec_enable_in) next_state = WAITING_FOR_KEY;
            WAITING_FOR_KEY: if (key_exp_ready_in) next_state = ENCRYPTION;
                             else next_state = WAITING_FOR_KEY;
            ENCRYPTION:      if (!encdec_enable_in || !sm4_enable_in) next_state = IDLE;
                             else next_state = ENCRYPTION;
        endcase
    end

    reg        busy;
    reg  [2:0] round_group;
    reg [127:0] reg_data;
    reg        ready_reg;
    reg [127:0] result_reg;

    assign ready_out   = ready_reg;
    assign result_out  = result_reg;

    wire [127:0] r0_out, r1_out, r2_out, r3_out;

    wire [31:0] rk0, rk1, rk2, rk3;

    assign rk0 = (round_group == 3'd0) ? rk_00_in :
                 (round_group == 3'd1) ? rk_04_in :
                 (round_group == 3'd2) ? rk_08_in :
                 (round_group == 3'd3) ? rk_12_in :
                 (round_group == 3'd4) ? rk_16_in :
                 (round_group == 3'd5) ? rk_20_in :
                 (round_group == 3'd6) ? rk_24_in : rk_28_in;

    assign rk1 = (round_group == 3'd0) ? rk_01_in :
                 (round_group == 3'd1) ? rk_05_in :
                 (round_group == 3'd2) ? rk_09_in :
                 (round_group == 3'd3) ? rk_13_in :
                 (round_group == 3'd4) ? rk_17_in :
                 (round_group == 3'd5) ? rk_21_in :
                 (round_group == 3'd6) ? rk_25_in : rk_29_in;

    assign rk2 = (round_group == 3'd0) ? rk_02_in :
                 (round_group == 3'd1) ? rk_06_in :
                 (round_group == 3'd2) ? rk_10_in :
                 (round_group == 3'd3) ? rk_14_in :
                 (round_group == 3'd4) ? rk_18_in :
                 (round_group == 3'd5) ? rk_22_in :
                 (round_group == 3'd6) ? rk_26_in : rk_30_in;

    assign rk3 = (round_group == 3'd0) ? rk_03_in :
                 (round_group == 3'd1) ? rk_07_in :
                 (round_group == 3'd2) ? rk_11_in :
                 (round_group == 3'd3) ? rk_15_in :
                 (round_group == 3'd4) ? rk_19_in :
                 (round_group == 3'd5) ? rk_23_in :
                 (round_group == 3'd6) ? rk_27_in : rk_31_in;

    one_round_for_encdec u_r0 (.data_in(reg_data),       .round_key_in(rk0), .result_out(r0_out));
    one_round_for_encdec u_r1 (.data_in(r0_out),         .round_key_in(rk1), .result_out(r1_out));
    one_round_for_encdec u_r2 (.data_in(r1_out),         .round_key_in(rk2), .result_out(r2_out));
    one_round_for_encdec u_r3 (.data_in(r2_out),         .round_key_in(rk3), .result_out(r3_out));

    wire [127:0] reversed_result = {r3_out[31:0], r3_out[63:32], r3_out[95:64], r3_out[127:96]};

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy       <= 1'b0;
            round_group<= 3'd0;
            reg_data   <= 128'd0;
            ready_reg  <= 1'b0;
            result_reg <= 128'd0;
        end else begin
            if (ready_reg) ready_reg <= 1'b0;

            if (current == ENCRYPTION) begin
                if (valid_in && !busy) begin
                    reg_data    <= data_in;
                    busy        <= 1'b1;
                    round_group <= 3'd0;
                end else if (busy) begin
                    if (round_group < 3'd7) begin
                        reg_data    <= r3_out;
                        round_group <= round_group + 1'b1;
                    end else begin
                        result_reg <= reversed_result;
                        ready_reg  <= 1'b1;
                        busy       <= 1'b0;
                        round_group<= 3'd0;
                    end
                end
            end else begin
                busy        <= 1'b0;
                round_group <= 3'd0;
            end
        end
    end

endmodule
