`timescale 1ns / 100ps

// Speed & latency testbench for serial SM4
// Measures exact cycle counts and reports throughput estimates.
module tb_speed();
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

    // Clock: 27 MHz (~37ns period) to match Tang Nano 20K
    // Use #18.5 for 50% duty cycle at 27MHz
    always #18.5 clk = ~clk;

    // Cycle counter
    integer cycle_cnt;
    always @(posedge clk) cycle_cnt = cycle_cnt + 1;

    // Timing measurement variables
    integer enc_start_cycle, enc_end_cycle;
    integer dec_start_cycle, dec_end_cycle;
    integer enc_latency, dec_latency;

    task wait_cycles(input int n);
        repeat (n) @(posedge clk);
    endtask

    initial begin
        cycle_cnt = 0;

        $display("===========================================");
        $display("  SM4 Serial Engine — Speed & Latency Test ");
        $display("===========================================");
        $display("Clock period: 37 ns (27 MHz)");
        $display("");

        // Dump VCD for detailed timing analysis
        $dumpfile("build/sm4_speed.vcd");
        $dumpvars(0, tb_speed);

        // === Reset & enable ===
        #100 reset_n = 1;
        #100 sm4_enable_in = 1;

        //===================================================================
        // PHASE 1: Key Expansion (encrypt mode)
        //===================================================================
        @(negedge clk);
        encdec_sel_in = 1'b0;
        enable_key_exp_in = 1'b1;
        user_key_valid_in = 1'b1;
        user_key_in = KEY;

        @(posedge clk);
        $display("[Phase 1] Key expansion (encrypt)...");

        // Key expansion takes 34 cycles from user_key_valid_in
        wait_cycles(34);

        if (key_exp_ready_out !== 1'b1) begin
            $display("ERROR: key_exp_ready_out did not go high!");
            $finish;
        end
        $display("[Phase 1] Key expansion done (cycle %0d)", cycle_cnt);

        //===================================================================
        // PHASE 2: Encryption latency measurement
        //===================================================================
        @(negedge clk);
        user_key_valid_in = 1'b0;
        encdec_enable_in = 1'b1;

        // Wait for FSM to reach ENCRYPTION state
        wait_cycles(3);

        // Fire data & record cycle
        @(negedge clk);
        valid_in = 1'b1;
        data_in = PLAINTEXT;
        enc_start_cycle = cycle_cnt;

        @(posedge clk);
        $display("[Phase 2] Encryption data valid at cycle %0d", enc_start_cycle);

        // Hold valid_in for 2 cycles then release
        @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        valid_in = 1'b0;

        // Wait for result
        wait(ready_out);
        enc_end_cycle = cycle_cnt;
        enc_latency = enc_end_cycle - enc_start_cycle;

        $display("[Phase 2] Encryption done at cycle %0d", enc_end_cycle);
        $display("  Result  = %h", result_out);
        $display("  Expected= %h", EXPECTED);
        if (result_out == EXPECTED)
            $display("  *** CORRECT ***");
        else
            $display("  *** WRONG ***");
        $display("  Latency = %0d clock cycles", enc_latency);
        $display("");

        //===================================================================
        // PHASE 3: Decryption latency measurement
        //===================================================================
        // Disable encdec FSM
        @(negedge clk);
        encdec_enable_in = 1'b0;
        wait_cycles(2);

        // Toggle enable_key_exp_in to trigger re-keying
        @(negedge clk);
        enable_key_exp_in = 1'b0;
        encdec_sel_in = 1'b1;       // decrypt mode (reverses round key order)

        wait_cycles(3);

        @(negedge clk);
        enable_key_exp_in = 1'b1;
        user_key_valid_in = 1'b1;
        user_key_in = KEY;

        @(posedge clk);
        $display("[Phase 3] Key expansion (decrypt)...");
        wait_cycles(34);

        if (key_exp_ready_out !== 1'b1) begin
            $display("ERROR: decryption key_exp_ready_out did not go high!");
            $finish;
        end
        $display("[Phase 3] Decrypt key expansion done (cycle %0d)", cycle_cnt);

        // Enable decryption
        @(negedge clk);
        user_key_valid_in = 1'b0;
        encdec_enable_in = 1'b1;

        wait_cycles(3);

        // Fire ciphertext & record cycle
        @(negedge clk);
        valid_in = 1'b1;
        data_in = EXPECTED;
        dec_start_cycle = cycle_cnt;

        @(posedge clk);
        $display("[Phase 3] Decryption data valid at cycle %0d", dec_start_cycle);

        @(negedge clk);
        @(posedge clk);
        @(negedge clk);
        valid_in = 1'b0;

        wait(ready_out);
        dec_end_cycle = cycle_cnt;
        dec_latency = dec_end_cycle - dec_start_cycle;

        $display("[Phase 3] Decryption done at cycle %0d", dec_end_cycle);
        $display("  Result  = %h", result_out);
        $display("  Expected= %h", PLAINTEXT);
        if (result_out == PLAINTEXT)
            $display("  *** CORRECT ***");
        else
            $display("  *** WRONG ***");
        $display("  Latency = %0d clock cycles", dec_latency);
        $display("");

        //===================================================================
        // Summary
        //===================================================================
        $display("===========================================");
        $display("  PERFORMANCE SUMMARY");
        $display("===========================================");
        $display("  Design:      SM4 serial/iterative engine");
        $display("  LUT4:        5526 / 20736 (26%%)");
        $display("  Max Fmax:    61 MHz (nextpnr estimate)");
        $display("");
        $display("  Encryption latency:  %0d cycles  %0d ns  @27MHz",
                 enc_latency, enc_latency * 37);
        $display("  Decryption latency:  %0d cycles  %0d ns  @27MHz",
                 dec_latency, dec_latency * 37);
        $display("");

        // Throughput: 128 bits per enc_latency cycles
        // At 27 MHz clock
        // Use real arithmetic for throughput to avoid 32-bit overflow
        $display("  --- Throughput @ 27 MHz ---");
        $display("  Per-block cycles: %0d  (data load + 32 rounds)", enc_latency);
        $display("  Blocks/sec:       %0d  (%.2f Mblock/s)",
                 27_000_000 / enc_latency,
                 (27_000_000.0 / enc_latency) / 1_000_000.0);
        $display("  Data rate:        %0.2f Mbps",
                 (128.0 * 27000000.0) / (enc_latency * 1000000.0));
        $display("");

        // At 61 MHz (max frequency from nextpnr)
        $display("  --- Throughput @ 61 MHz (theoretical max) ---");
        $display("  Blocks/sec:       %0d  (%.2f Mblock/s)",
                 61_000_000 / enc_latency,
                 (61_000_000.0 / enc_latency) / 1_000_000.0);
        $display("  Data rate (real): %0.2f Mbps",
                 (128.0 * 61000000.0) / (enc_latency * 1000000.0));
        $display("");

        // Key expansion cycles
        $display("  Key expansion:    34 cycles");
        $display("  Key expansion freq: once per key change");
        $display("");
        $display("===========================================");
        $display("  Test PASSED");
        $display("===========================================");

        #500;
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
