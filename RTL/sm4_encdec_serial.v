`timescale 1ns / 100ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer: FPGA_SM4 (serial/iterative version by Sisyphus)
//
// Create Date: 2026/06/24
// Design Name: sm4_encdec_serial
// Project Name: FPGA_SM4
// Target Devices: Tang Nano 20K (GW2AR-LV18QN88C8/I7)
// Tool Versions:
// Description:
//   SM4 encryption/decryption engine (serial/iterative).
//
//   Replaces the 32-stage fully-pipelined sm4_encdec.v with a single-round
//   iterative engine. Uses ~1/32 the LUT area of the original pipeline.
//
//   FSM states: IDLE → WAITING_FOR_KEY → ENCRYPTION
//
//   Timing (single block):
//     - valid_in (1 cycle): load data_in, start processing
//     - following 32 cycles: compute rounds 0..31
//     - ready_out goes high after 33 total cycles
//
//   Interface is pin-compatible with the original sm4_encdec.v.
//
// Dependencies:
//   one_round_for_encdec.v, sbox_replace.v, transform_for_encdec.v
//
//////////////////////////////////////////////////////////////////////////////////

module sm4_encdec_serial(
    clk                 ,
    reset_n             ,
    sm4_enable_in       ,
    encdec_enable_in    ,
    key_exp_ready_in    ,
    valid_in            ,
    data_in             ,
    rk_00_in            ,
    rk_01_in            ,
    rk_02_in            ,
    rk_03_in            ,
    rk_04_in            ,
    rk_05_in            ,
    rk_06_in            ,
    rk_07_in            ,
    rk_08_in            ,
    rk_09_in            ,
    rk_10_in            ,
    rk_11_in            ,
    rk_12_in            ,
    rk_13_in            ,
    rk_14_in            ,
    rk_15_in            ,
    rk_16_in            ,
    rk_17_in            ,
    rk_18_in            ,
    rk_19_in            ,
    rk_20_in            ,
    rk_21_in            ,
    rk_22_in            ,
    rk_23_in            ,
    rk_24_in            ,
    rk_25_in            ,
    rk_26_in            ,
    rk_27_in            ,
    rk_28_in            ,
    rk_29_in            ,
    rk_30_in            ,
    rk_31_in            ,
    ready_out           ,
    result_out
);
    input               clk                 ;
    input               reset_n             ;
    input               sm4_enable_in       ;
    input               encdec_enable_in    ;
    input               key_exp_ready_in    ;
    input               valid_in            ;
    input   [127: 0]    data_in             ;
    input   [31 : 0]    rk_00_in            ;
    input   [31 : 0]    rk_01_in            ;
    input   [31 : 0]    rk_02_in            ;
    input   [31 : 0]    rk_03_in            ;
    input   [31 : 0]    rk_04_in            ;
    input   [31 : 0]    rk_05_in            ;
    input   [31 : 0]    rk_06_in            ;
    input   [31 : 0]    rk_07_in            ;
    input   [31 : 0]    rk_08_in            ;
    input   [31 : 0]    rk_09_in            ;
    input   [31 : 0]    rk_10_in            ;
    input   [31 : 0]    rk_11_in            ;
    input   [31 : 0]    rk_12_in            ;
    input   [31 : 0]    rk_13_in            ;
    input   [31 : 0]    rk_14_in            ;
    input   [31 : 0]    rk_15_in            ;
    input   [31 : 0]    rk_16_in            ;
    input   [31 : 0]    rk_17_in            ;
    input   [31 : 0]    rk_18_in            ;
    input   [31 : 0]    rk_19_in            ;
    input   [31 : 0]    rk_20_in            ;
    input   [31 : 0]    rk_21_in            ;
    input   [31 : 0]    rk_22_in            ;
    input   [31 : 0]    rk_23_in            ;
    input   [31 : 0]    rk_24_in            ;
    input   [31 : 0]    rk_25_in            ;
    input   [31 : 0]    rk_26_in            ;
    input   [31 : 0]    rk_27_in            ;
    input   [31 : 0]    rk_28_in            ;
    input   [31 : 0]    rk_29_in            ;
    input   [31 : 0]    rk_30_in            ;
    input   [31 : 0]    rk_31_in            ;
    output              ready_out           ;
    output  [127: 0]    result_out          ;

    //-----------------------------------------------------------------
    // FSM states (same encoding as original)
    //-----------------------------------------------------------------
    localparam IDLE            = 2'b00;
    localparam WAITING_FOR_KEY = 2'b01;
    localparam ENCRYPTION      = 2'b10;

    reg [1:0] current;
    reg [1:0] next_state;

    always @(posedge clk or negedge reset_n)
        if(!reset_n)
            current <= IDLE;
        else if(sm4_enable_in)
            current <= next_state;

    always @(*) begin
        next_state = IDLE;
        case (current)
            IDLE:
                if (sm4_enable_in && encdec_enable_in)
                    next_state = WAITING_FOR_KEY;
            WAITING_FOR_KEY:
                if (key_exp_ready_in)
                    next_state = ENCRYPTION;
                else
                    next_state = WAITING_FOR_KEY;
            ENCRYPTION:
                if (!encdec_enable_in || !sm4_enable_in)
                    next_state = IDLE;
                else
                    next_state = ENCRYPTION;
        endcase
    end

    //-----------------------------------------------------------------
    // Round iteration control
    //-----------------------------------------------------------------
    //   busy: 1 when actively processing a block
    //   round: 0..31, which round to compute THIS cycle
    //     round=0: compute round 0 using rk_00_in
    //     round=1: compute round 1 using rk_01_in
    //     ...
    //     round=31: compute round 31 using rk_31_in
    //
    // Timing (ENCRYPTION state):
    //   Cycle when valid_in: reg_data <= data_in, busy <= 1, round <= 0
    //   Next 31 cycles (round 0..30): reg_data <= round_result, round++
    //   Cycle when round=31: result_out <= reversed(round_result),
    //                        ready_out <= 1, busy <= 0
    //   Total: ~33 cycles from valid_in to ready_out
    //-----------------------------------------------------------------
    reg        busy;
    reg  [4:0] round;      // 0..31
    reg [127:0] reg_data;  // current block data

    // Round function combinational result
    wire [127:0] round_result;

    // Selected round key (combinational MUX)
    reg [31:0] selected_rk;

    // ready_out (registered, auto-clears on next clock)
    reg ready_reg;
    assign ready_out = ready_reg;

    // result_out (registered)
    reg [127:0] result_reg;
    assign result_out = result_reg;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            busy       <= 1'b0;
            round      <= 5'd0;
            reg_data   <= 128'd0;
            ready_reg  <= 1'b0;
            result_reg <= 128'd0;
        end else begin
            // Auto-clear ready_out (single-cycle pulse)
            if (ready_reg)
                ready_reg <= 1'b0;

            if (current == ENCRYPTION) begin
                if (valid_in && !busy) begin
                    // Load initial data, begin processing
                    reg_data <= data_in;
                    busy     <= 1'b1;
                    round    <= 5'd0;
                end else if (busy) begin
                    if (round < 5'd31) begin
                        // Compute and advance
                        reg_data <= round_result;
                        round    <= round + 1'b1;
                    end else begin
                        // round == 31: last round computation
                        // round_result is the final SM4 result
                        // Reverse word order for output (SM4 convention)
                        result_reg <= {round_result[31:0],
                                       round_result[63:32],
                                       round_result[95:64],
                                       round_result[127:96]};
                        ready_reg  <= 1'b1;
                        busy       <= 1'b0;
                        round      <= 5'd0;
                    end
                end
            end else begin
                // Not in ENCRYPTION state, reset
                busy  <= 1'b0;
                round <= 5'd0;
            end
        end
    end

    //-----------------------------------------------------------------
    // Round key selection MUX (32:1, combinational)
    //-----------------------------------------------------------------
    // round=0  → rk_00_in  (round 0)
    // round=1  → rk_01_in  (round 1)
    // ...
    // round=31 → rk_31_in  (round 31)
    //-----------------------------------------------------------------
    always @(*) begin
        case (round)
            5'd0:   selected_rk = rk_00_in;
            5'd1:   selected_rk = rk_01_in;
            5'd2:   selected_rk = rk_02_in;
            5'd3:   selected_rk = rk_03_in;
            5'd4:   selected_rk = rk_04_in;
            5'd5:   selected_rk = rk_05_in;
            5'd6:   selected_rk = rk_06_in;
            5'd7:   selected_rk = rk_07_in;
            5'd8:   selected_rk = rk_08_in;
            5'd9:   selected_rk = rk_09_in;
            5'd10:  selected_rk = rk_10_in;
            5'd11:  selected_rk = rk_11_in;
            5'd12:  selected_rk = rk_12_in;
            5'd13:  selected_rk = rk_13_in;
            5'd14:  selected_rk = rk_14_in;
            5'd15:  selected_rk = rk_15_in;
            5'd16:  selected_rk = rk_16_in;
            5'd17:  selected_rk = rk_17_in;
            5'd18:  selected_rk = rk_18_in;
            5'd19:  selected_rk = rk_19_in;
            5'd20:  selected_rk = rk_20_in;
            5'd21:  selected_rk = rk_21_in;
            5'd22:  selected_rk = rk_22_in;
            5'd23:  selected_rk = rk_23_in;
            5'd24:  selected_rk = rk_24_in;
            5'd25:  selected_rk = rk_25_in;
            5'd26:  selected_rk = rk_26_in;
            5'd27:  selected_rk = rk_27_in;
            5'd28:  selected_rk = rk_28_in;
            5'd29:  selected_rk = rk_29_in;
            5'd30:  selected_rk = rk_30_in;
            5'd31:  selected_rk = rk_31_in;
            default: selected_rk = 32'd0;
        endcase
    end

    //-----------------------------------------------------------------
    // Single round function instance (shared across all 32 iterations)
    //-----------------------------------------------------------------
    one_round_for_encdec u_round (
        .data_in      (reg_data),
        .round_key_in (selected_rk),
        .result_out   (round_result)
    );

endmodule
