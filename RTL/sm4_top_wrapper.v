//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Raymond Rui Chen, raymond.rui.chen@qq.com
// 
// Create Date: 2018/03/10 12:06:49
// Design Name: 
// Module Name: sm4_top_wrapper
// Project Name: FPGA_SM4
// Target Devices: Tang Nano 20K (GW2AR-LV18QN88C8/I7)
// Description: 
//   Top-level wrapper for SM4 encryption/decryption core.
//   Maps the SM4 core to Tang Nano 20K onboard resources:
//   - 27MHz clock (PIN4)
//   - S2 button as reset (PIN87, active low)
//   - S1 button to trigger encrypt/decrypt (PIN88, active low)
//   - 6 LEDs for status display (PIN15-20, active low)
// 
//   Test vectors (from testbench):
//     Key:      128'h0123456789abcdeffedcba9876543210
//     Plain:    128'h0123456789abcdeffedcba9876543210
//     Cipher:   128'h681edf34d206965e86b3e94f536e4246
// 
//   LED status:
//     [0] SM4 enabled / busy
//     [1] Key expansion complete
//     [2] Encryption done
//     [3] Encryption result = expected (correct)
//     [4] Decryption done
//     [5] Decryption result = original (correct)
//////////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 100ps

module sm4_top_wrapper (
    input  wire       clk,        // 27MHz main clock (PIN4)
    input  wire       rst_n,      // Reset button S2 (PIN87), active low
    input  wire       btn_s1,     // Start button S1 (PIN88), active low
    output wire [5:0] led         // 6 LEDs (PIN15-20), active low
);

    //-----------------------------------------------------------------
    // Test vectors (from original testbench)
    //-----------------------------------------------------------------
    localparam [127:0] TEST_KEY       = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] TEST_PLAINTEXT = 128'h0123456789abcdeffedcba9876543210;
    localparam [127:0] EXPECTED_CIPHER = 128'h681edf34d206965e86b3e94f536e4246;

    //-----------------------------------------------------------------
    // SM4 core interface signals
    //-----------------------------------------------------------------
    wire        sm4_enable_in;
    wire        encdec_enable_in;
    reg         encdec_sel_in;
    reg         valid_in;
    reg  [127:0] data_in;
    reg         enable_key_exp_in;
    reg         user_key_valid_in;
    reg  [127:0] user_key_in;
    wire        key_exp_ready_out;
    wire        ready_out;
    wire [127:0] result_out;

    //-----------------------------------------------------------------
    // Internal registers
    //-----------------------------------------------------------------
    reg [127:0] stored_result;
    reg         enc_result_correct;
    reg         dec_result_correct;

    //-----------------------------------------------------------------
    // Button debounce / edge detection
    //-----------------------------------------------------------------
    reg [2:0] btn_s1_sync;
    reg       btn_s1_falling;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_s1_sync <= 3'b111;
        end else begin
            btn_s1_sync <= {btn_s1_sync[1:0], btn_s1};
        end
    end

    // Falling edge: button pressed (active low)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            btn_s1_falling <= 1'b0;
        else if (btn_s1_sync[2:1] == 2'b10)
            btn_s1_falling <= 1'b1;
        else
            btn_s1_falling <= 1'b0;
    end

    //-----------------------------------------------------------------
    // State machine
    //-----------------------------------------------------------------
    localparam IDLE         = 4'd0;
    localparam KEY_EXPAND   = 4'd1;
    localparam WAIT_KEY     = 4'd2;
    localparam LOAD_DATA    = 4'd3;
    localparam ENCRYPT_WAIT = 4'd4;
    localparam CHECK_ENC    = 4'd5;
    localparam DECRYPT_KEY  = 4'd6;
    localparam WAIT_DEC_KEY = 4'd7;
    localparam LOAD_CIPHER  = 4'd8;
    localparam DECRYPT_WAIT = 4'd9;
    localparam CHECK_DEC    = 4'd10;
    localparam DONE         = 4'd11;

    reg [3:0] state, next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (btn_s1_falling)
                    next_state = KEY_EXPAND;
            end

            KEY_EXPAND: begin
                next_state = WAIT_KEY;
            end

            WAIT_KEY: begin
                if (key_exp_ready_out)
                    next_state = LOAD_DATA;
            end

            LOAD_DATA: begin
                next_state = ENCRYPT_WAIT;
            end

            ENCRYPT_WAIT: begin
                if (ready_out)
                    next_state = CHECK_ENC;
            end

            CHECK_ENC: begin
                next_state = DECRYPT_KEY;
            end

            DECRYPT_KEY: begin
                next_state = WAIT_DEC_KEY;
            end

            WAIT_DEC_KEY: begin
                if (key_exp_ready_out)
                    next_state = LOAD_CIPHER;
            end

            LOAD_CIPHER: begin
                next_state = DECRYPT_WAIT;
            end

            DECRYPT_WAIT: begin
                if (ready_out)
                    next_state = CHECK_DEC;
            end

            CHECK_DEC: begin
                next_state = DONE;
            end

            DONE: begin
                if (btn_s1_falling)
                    next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    //-----------------------------------------------------------------
    // SM4 core control signals
    //-----------------------------------------------------------------
    assign sm4_enable_in = (state != IDLE);

    always @(*) begin
        // Defaults
        enable_key_exp_in = 1'b0;
        user_key_valid_in = 1'b0;
        user_key_in       = TEST_KEY;
        encdec_sel_in     = 1'b0;  // 0=encrypt, 1=decrypt
        valid_in          = 1'b0;
        data_in           = TEST_PLAINTEXT;

        case (state)
            KEY_EXPAND, DECRYPT_KEY: begin
                enable_key_exp_in = 1'b1;
                user_key_valid_in = 1'b1;
                user_key_in       = TEST_KEY;
            end

            LOAD_DATA: begin
                valid_in = 1'b1;
                data_in  = TEST_PLAINTEXT;
            end

            DECRYPT_KEY: begin
                encdec_sel_in = 1'b1;    // decrypt mode
            end

            LOAD_CIPHER: begin
                encdec_sel_in = 1'b1;    // decrypt mode
                valid_in      = 1'b1;
                data_in       = EXPECTED_CIPHER;
            end
        endcase
    end

    assign encdec_enable_in = (state == LOAD_DATA || state == ENCRYPT_WAIT ||
                               state == LOAD_CIPHER || state == DECRYPT_WAIT);

    //-----------------------------------------------------------------
    // Capture result
    //-----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stored_result      <= 128'h0;
            enc_result_correct <= 1'b0;
            dec_result_correct <= 1'b0;
        end else begin
            if (state == CHECK_ENC && ready_out) begin
                stored_result      <= result_out;
                enc_result_correct <= (result_out == EXPECTED_CIPHER);
            end
            if (state == CHECK_DEC && ready_out) begin
                dec_result_correct <= (result_out == TEST_PLAINTEXT);
            end
        end
    end

    //-----------------------------------------------------------------
    // LED output (active low)
    //   [0] SM4 busy
    //   [1] Key expansion done
    //   [2] Encryption done
    //   [3] Encryption correct
    //   [4] Decryption done
    //   [5] Decryption correct
    //-----------------------------------------------------------------
    reg [5:0] led_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            led_reg <= 6'b111111;  // all LEDs off (active low)
        else begin
            case (state)
                IDLE:         led_reg <= 6'b111111;  // all off
                KEY_EXPAND,
                WAIT_KEY:     led_reg <= 6'b111110;  // LED0 on: busy
                LOAD_DATA,
                ENCRYPT_WAIT: led_reg <= 6'b111100;  // LED0,1 on: encrypting
                CHECK_ENC:    led_reg <= {~enc_result_correct, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0};
                              // LED3 = enc correct
                DECRYPT_KEY,
                WAIT_DEC_KEY: led_reg <= 6'b110000;  // LED0,1: decrypt key exp
                LOAD_CIPHER,
                DECRYPT_WAIT: led_reg <= 6'b100000;  // LED0 only: decrypting
                CHECK_DEC:    led_reg <= {~dec_result_correct, ~dec_result_correct, 1'b0, 1'b0, 1'b0, 1'b0};
                              // LED5 = dec correct, LED4 = dec done
                DONE:         led_reg <= {6{~enc_result_correct & ~dec_result_correct}};
                              // All on = success, all off = fail
                default:      led_reg <= 6'b111111;
            endcase
        end
    end

    assign led = led_reg;

    //-----------------------------------------------------------------
    // SM4 core instantiation
    //-----------------------------------------------------------------
    sm4_top u_sm4 (
        .clk                (clk               ),
        .reset_n            (rst_n             ),
        .sm4_enable_in      (sm4_enable_in     ),
        .encdec_enable_in   (encdec_enable_in  ),
        .encdec_sel_in      (encdec_sel_in     ),
        .valid_in           (valid_in          ),
        .data_in            (data_in           ),
        .enable_key_exp_in  (enable_key_exp_in ),
        .user_key_valid_in  (user_key_valid_in ),
        .user_key_in        (user_key_in       ),
        .key_exp_ready_out  (key_exp_ready_out ),
        .ready_out          (ready_out         ),
        .result_out         (result_out        )
    );

endmodule
