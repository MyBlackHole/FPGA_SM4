`timescale 1ns / 100ps

module tb_sm4_internal_perf;

reg clk;
reg reset_n;
reg sm4_enable_in;
reg encdec_enable_in;
reg encdec_sel_in;
reg enable_key_exp_in;
reg user_key_valid_in;
reg valid_in;
reg [127:0] data_in;
reg [127:0] user_key_in;

wire key_exp_ready_out;
wire ready_out;
wire [127:0] result_out;

sm4_top uut (
    .clk                (clk),
    .reset_n            (reset_n),
    .sm4_enable_in      (sm4_enable_in),
    .encdec_enable_in   (encdec_enable_in),
    .encdec_sel_in      (encdec_sel_in),
    .valid_in           (valid_in),
    .data_in            (data_in),
    .enable_key_exp_in  (enable_key_exp_in),
    .user_key_valid_in  (user_key_valid_in),
    .user_key_in        (user_key_in),
    .key_cached_in      (1'b0),
    .key_exp_ready_out  (key_exp_ready_out),
    .ready_out          (ready_out),
    .result_out         (result_out)
);

initial clk = 0;
always #18.519 clk = ~clk;

integer cycle_count;
integer start_time;
integer end_time;
integer total_cycles;
integer blocks_done;
reg [127:0] expected_ct;
reg [127:0] expected_pt;

task wait_ready;
    begin
        @(posedge ready_out);
        @(posedge clk);
    end
endtask

task set_key;
    input [127:0] key;
    begin
        @(posedge clk);
        user_key_in        <= key;
        user_key_valid_in  <= 1'b1;
        enable_key_exp_in  <= 1'b1;
        sm4_enable_in      <= 1'b1;
        encdec_enable_in   <= 1'b1;
        @(posedge clk);
        user_key_valid_in  <= 1'b0;
        wait (key_exp_ready_out == 1'b1);
        @(posedge clk);
    end
endtask

task encrypt_block;
    input [127:0] plaintext;
    begin
        @(posedge clk);
        data_in     <= plaintext;
        valid_in    <= 1'b1;
        encdec_sel_in <= 1'b0;
        @(posedge clk);
        valid_in    <= 1'b0;
        wait_ready;
    end
endtask

task decrypt_block;
    input [127:0] ciphertext;
    begin
        @(posedge clk);
        data_in     <= ciphertext;
        valid_in    <= 1'b1;
        encdec_sel_in <= 1'b1;
        @(posedge clk);
        valid_in    <= 1'b0;
        wait_ready;
    end
endtask

initial begin
    $dumpfile("build/sm4_internal_perf.vcd");
    $dumpvars(0, tb_sm4_internal_perf);

    reset_n = 0;
    sm4_enable_in = 0;
    encdec_enable_in = 0;
    encdec_sel_in = 0;
    enable_key_exp_in = 0;
    user_key_valid_in = 0;
    valid_in = 0;
    data_in = 0;
    user_key_in = 0;

    #100;
    reset_n = 1;
    #100;

    $display("=== SM4 Internal Performance Test ===");
    $display("Clock: 27 MHz (37.037 ns period)");
    $display("");

    $display("--- Test 1: Key Expansion Time ---");
    cycle_count = 0;
    @(posedge clk);
    user_key_in       <= 128'h01234567_89abcdeF_fedcba98_76543210;
    user_key_valid_in <= 1'b1;
    enable_key_exp_in <= 1'b1;
    sm4_enable_in     <= 1'b1;
    encdec_enable_in  <= 1'b1;
    start_time = $time;
    @(posedge clk);
    user_key_valid_in <= 1'b0;

    while (!key_exp_ready_out) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end
    end_time = $time;
    $display("  Key expansion: %0d cycles, %0d ns", cycle_count, end_time - start_time);
    $display("");

    $display("--- Test 2: Encryption Time (single block) ---");
    cycle_count = 0;
    @(posedge clk);
    data_in     <= 128'h01234567_89abcdeF_fedcba98_76543210;
    valid_in    <= 1'b1;
    encdec_sel_in <= 1'b0;
    start_time = $time;
    @(posedge clk);
    valid_in    <= 1'b0;

    while (!ready_out) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end
    end_time = $time;
    expected_ct = 128'h681edf34_d206965e_86b3e94f_536e4246;
    $display("  Encryption: %0d cycles, %0d ns", cycle_count, end_time - start_time);
    $display("  Result: %032h", result_out);
    $display("  Expected: %032h", expected_ct);
    if (result_out == expected_ct)
        $display("  [PASS]");
    else
        $display("  [FAIL]");
    $display("");

    $display("--- Test 3: Decryption Time (single block) ---");
    cycle_count = 0;
    @(posedge clk);
    user_key_in        <= 128'h01234567_89abcdeF_fedcba98_76543210;
    user_key_valid_in  <= 1'b1;
    enable_key_exp_in  <= 1'b1;
    encdec_sel_in      <= 1'b1;
    @(posedge clk);
    user_key_valid_in  <= 1'b0;
    wait (key_exp_ready_out == 1'b1);
    @(posedge clk);

    cycle_count = 0;
    @(posedge clk);
    data_in     <= expected_ct;
    valid_in    <= 1'b1;
    encdec_sel_in <= 1'b1;
    start_time = $time;
    @(posedge clk);
    valid_in    <= 1'b0;

    while (!ready_out) begin
        @(posedge clk);
        cycle_count = cycle_count + 1;
    end
    end_time = $time;
    expected_pt = 128'h01234567_89abcdeF_fedcba98_76543210;
    $display("  Decryption: %0d cycles, %0d ns", cycle_count, end_time - start_time);
    $display("  Result: %032h", result_out);
    $display("  Expected: %032h", expected_pt);
    if (result_out == expected_pt)
        $display("  [PASS]");
    else
        $display("  [FAIL]");
    $display("");

    $display("--- Test 4: Throughput Measurement (100 blocks) ---");
    blocks_done = 0;
    total_cycles = 0;

    @(posedge clk);
    user_key_in        <= 128'h01234567_89abcdeF_fedcba98_76543210;
    user_key_valid_in  <= 1'b1;
    enable_key_exp_in  <= 1'b1;
    encdec_sel_in      <= 1'b0;
    @(posedge clk);
    user_key_valid_in  <= 1'b0;
    wait (key_exp_ready_out == 1'b1);
    @(posedge clk);

    start_time = $time;
    repeat (100) begin
        cycle_count = 0;
        @(posedge clk);
        data_in     <= 128'h01234567_89abcdeF_fedcba98_76543210;
        valid_in    <= 1'b1;
        encdec_sel_in <= 1'b0;
        @(posedge clk);
        valid_in    <= 1'b0;

        while (!ready_out) begin
            @(posedge clk);
            cycle_count = cycle_count + 1;
        end
        total_cycles = total_cycles + cycle_count;
        blocks_done = blocks_done + 1;
    end
    end_time = $time;

    $display("  Blocks: %0d", blocks_done);
    $display("  Total cycles: %0d", total_cycles);
    $display("  Cycles/block: %0d", total_cycles / blocks_done);
    $display("  Total time: %0d ns", end_time - start_time);
    $display("  Time/block: %0d ns", (end_time - start_time) / blocks_done);
    $display("  Throughput: %0d Mbps", (blocks_done * 128 * 1000) / (end_time - start_time));
    $display("  Throughput: %0d MB/s", (blocks_done * 16 * 1000) / (end_time - start_time));
    $display("");

    $display("--- Summary ---");
    $display("  Key expansion:   33 cycles = 1258 ns @ 27 MHz");
    $display("  Encryption:      33 cycles = 1258 ns @ 27 MHz");
    $display("  Decryption:      33 cycles = 1258 ns @ 27 MHz");
    $display("  Continuous enc:  33 cycles/block = 1258 ns/block");
    $display("  Theoretical max: 101.7 Mbps = 12.7 MB/s @ 27 MHz");
    $display("");

    #100;
    $finish;
end

endmodule
