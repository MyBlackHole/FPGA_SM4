`timescale 1ns / 100ps

// Debug testbench: demonstrates SM4 encrypt/decrypt with correct timing
// Key fix: keep enable_key_exp_in HIGH throughout so key_exp_ready_out stays HIGH,
// allowing encdec FSM to transition WAITING_FOR_KEY -> ENCRYPTION.
module tb_debug();
    reg             clk = 0;
    reg             reset_n = 0;
    reg             sm4_enable_in = 0;
    reg             encdec_enable_in = 0;
    reg             encdec_sel_in = 0;
    reg             valid_in = 0;
    reg   [127:0]   data_in = 0;
    reg             enable_key_exp_in = 0;
    reg             user_key_valid_in = 0;
    reg   [127:0]   user_key_in = 0;
    wire            ready_out;
    wire            key_exp_ready_out;
    wire  [127:0]   result_out;

    localparam KEY       = 128'h0123456789abcdeffedcba9876543210;
    localparam PLAINTEXT = 128'h0123456789abcdeffedcba9876543210;
    localparam EXPECTED  = 128'h681edf34d206965e86b3e94f536e4246;

    always #3 clk = ~clk;

    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    initial begin
        $display("=== SM4 Debug Testbench ===");
        $dumpfile("build/sm4_debug.vcd");
        $dumpvars(0, tb_debug);

        // === Reset ===
        #100 reset_n = 1;
        #100 sm4_enable_in = 1;

        // === PHASE 1: Key Expansion (encrypt mode) ===
        // Keep enable_key_exp_in HIGH throughout encryption phase!
        @(negedge clk);
        encdec_sel_in = 1'b0;       // encrypt
        enable_key_exp_in = 1'b1;
        user_key_valid_in = 1'b1;
        user_key_in = KEY;

        @(posedge clk);
        $display("Key expansion start...");

        // Key expansion takes 32 cycles + 2 setup = 34 cycles
        wait_cycles(34);
        $display("key_exp_ready_out = %b", key_exp_ready_out);

        // === PHASE 2: Encryption ===
        // enable_key_exp_in stays HIGH — key_exp_ready_out remains HIGH.
        // user_key_valid_in goes LOW after key loaded.
        @(negedge clk);
        user_key_valid_in = 1'b0;   // done loading key
        encdec_enable_in = 1'b1;    // enable encryption engine

        // FSM: IDLE -> WAITING_FOR_KEY (1 cycle) -> ENCRYPTION (1 cycle)
        wait_cycles(3);

        // FSM now in ENCRYPTION — inject data
        @(negedge clk);
        valid_in = 1'b1;
        data_in = PLAINTEXT;

        @(posedge clk);
        $display("Encryption start... valid_in=%b data=%h", valid_in, data_in);

        // Keep valid_in HIGH across 2 posedges to ensure reg_tmp loads the '1'
        @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        valid_in = 1'b0;

        // Wait for the '1' to ripple through all 32 bits of reg_tmp
        wait(ready_out);
        $display("Encryption done! Result=%h", result_out);
        if (result_out == EXPECTED)
            $display("*** ENCRYPTION CORRECT! ***");
        else
            $display("*** ENCRYPTION WRONG! Expected=%h ***", EXPECTED);

        // === PHASE 3: Decryption ===
        // Need to re-run key expansion in decrypt mode
        // Step 1: disable encdec
        @(negedge clk);
        encdec_enable_in = 1'b0;

        wait_cycles(2);  // let encdec FSM return to IDLE

        // Step 2: restart key expansion by toggling enable_key_exp_in
        // This clears key_exp_finished_out via the clearing logic:
        //   ~enable_key_exp_in && reg_enable_key_exp
        @(negedge clk);
        enable_key_exp_in = 1'b0;   // trigger clear of key_exp_ready_out
        encdec_sel_in = 1'b1;       // decrypt mode

        wait_cycles(3);             // wait for key_exp_ready_out to clear

        // Step 3: start key expansion for decryption
        @(negedge clk);
        enable_key_exp_in = 1'b1;   // re-enable key expansion
        user_key_valid_in = 1'b1;   // pulse key valid
        user_key_in = KEY;

        @(posedge clk);
        $display("Decrypt key expansion start...");
        wait_cycles(34);
        $display("Decrypt key_exp_ready_out = %b", key_exp_ready_out);

        // Step 4: enable decryption
        @(negedge clk);
        user_key_valid_in = 1'b0;
        encdec_enable_in = 1'b1;

        wait_cycles(3);              // IDLE -> WAITING_FOR_KEY -> ENCRYPTION

        @(negedge clk);
        valid_in = 1'b1;
        data_in = EXPECTED;          // feed ciphertext

        @(posedge clk);
        $display("Decryption start...");
        @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        valid_in = 1'b0;

        wait(ready_out);
        $display("Decryption done! Result=%h", result_out);
        if (result_out == PLAINTEXT)
            $display("*** DECRYPTION CORRECT! ***");
        else
            $display("*** DECRYPTION WRONG! Expected=%h ***", PLAINTEXT);

        #500;
        $display("=== SIMULATION DONE ===");
        $finish;
    end

    sm4_top uut (
        .clk                (clk               ),
        .reset_n            (reset_n           ),
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
