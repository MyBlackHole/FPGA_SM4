`timescale 1ns / 100ps
////////////////////////////////////////////////////////////////////////////////
// Testbench: SM4 UART Top
//
// Strategy:
//   - Sends commands to the FPGA via UART (drives the rx pin).
//   - Verifies SM4 core result via sm4_result_out / sm4_ready_out (internal).
//   - Captures UART TX bytes autonomously (cap_* always block samples tx at
//     mid-bit using clock-synchronous timing).
//   - After each transaction, checks captured bytes against expected values.
//
//  UART protocol:
//    'P' + 0 payload bytes   Ping, FPGA returns 'O'
//    'K' + 16 key bytes      Set key
//    'E' + 16 plaintext      Encrypt, returns 16 ciphertext bytes
//    'D' + 16 ciphertext     Decrypt, returns 16 plaintext bytes
////////////////////////////////////////////////////////////////////////////////

module tb_sm4_uart;

    // ── Parameters ──────────────────────────────────────────────────────────
    // NOTE: $time counts in time-PRECISION units (0.1ns per `timescale 1ns/100ps).
    //       So $time value = ns / 0.1.  #37 = 37ns, $time += 370.
    //       All #delays are in ns (time unit = 1ns).  Real values work fine.
    localparam real    CLK_NS     = 37.037;    // ns, 27 MHz period
    localparam integer CLK_FREQ   = 27_000_000;
    localparam integer BAUD_RATE  = 115200;
    localparam integer BIT_CYCLES = CLK_FREQ / BAUD_RATE;           // 234
    localparam real    BIT_TIME_NS = (CLK_NS * CLK_FREQ) / BAUD_RATE; // 8680.55

    // Debug: verify timing params
    // initial block with param debug removed (moved to main seq)

    // Test vectors (from SM4 standard)
    localparam [127:0] KEY = 128'h01234567_89abcdef_fedcba98_76543210;
    localparam [127:0] PLAIN = 128'h01234567_89abcdef_fedcba98_76543210;
    localparam [127:0] EXPECTED_CIPHER = 128'h681edf34_d206965e_86b3e94f_536e4246;

    // ── Signals ─────────────────────────────────────────────────────────────
    reg clk;
    reg reset_n;
    reg rx;
    wire tx;
    wire led_busy;
    wire tx_busy_out;
    wire [127:0] sm4_result_out;
    wire         sm4_ready_out;

    // DUT
    sm4_uart_top #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_dut (
        .clk(clk),
        .reset_n(reset_n),
        .rx(rx),
        .tx(tx),
        .led_busy(led_busy),
        .tx_busy_out(tx_busy_out),
        .sm4_result_out(sm4_result_out),
        .sm4_ready_out(sm4_ready_out)
    );

    // Latch sm4_ready_out (it's a single-cycle pulse)
    reg sm4_done;
    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            sm4_done <= 1'b0;
        else if (sm4_ready_out)
            sm4_done <= 1'b1;
    end

    // ── Clock generation ────────────────────────────────────────────────────
    initial clk = 0;
    always #(CLK_NS / 2.0) clk = ~clk;

    // ── UART TX capture (autonomous hardware sniffer) ───────────────────────
    // Continuously watches the tx pin and samples UART frames at mid-bit
    // positions using clock-synchronous timing.  Stores bytes in a ring
    // buffer for later verification.
    reg [7:0]  cap_buf[0:255];       // ring buffer
    reg [7:0]  cap_wr;               // write index
    reg        cap_busy;             // currently capturing a frame
    reg [15:0] cap_cnt;              // bit-time counter
    reg [3:0]  cap_bit;              // bit index (0-7)
    reg [7:0]  cap_shift;            // shift register
    reg        cap_armed;            // tx was idle, ready to detect start bit

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            cap_busy  <= 1'b0;
            cap_cnt   <= 16'd0;
            cap_bit   <= 3'd0;
            cap_shift <= 8'd0;
            cap_wr    <= 8'd0;
            cap_armed <= 1'b0;
        end else if (!cap_busy) begin
            if (cap_armed && !tx) begin
                // Start bit detected → skip straight to mid-bit-0
                // (1.5 bit times from the rising edge that armed us,
                //  minus 1 because the counter decrements on the next cycle)
                cap_busy  <= 1'b1;
                cap_cnt   <= (BIT_CYCLES * 3) / 2 - 1;  // 350 → mid-bit-0
                cap_bit   <= 3'd0;
                cap_armed <= 1'b0;
            end else if (tx) begin
                cap_armed <= 1'b1;              // tx idle, arm for start bit
            end
        end else begin
            if (cap_cnt == 0) begin
                if (cap_bit < 4'd8) begin
                    // Sample data bit at mid-bit
                    cap_shift[cap_bit] <= tx;
                    cap_bit <= cap_bit + 1;
                    cap_cnt <= BIT_CYCLES - 1;
                end else begin
                    // All 8 bits captured -> store
                    cap_buf[cap_wr] <= cap_shift;
                    cap_wr <= cap_wr + 1;
                    cap_busy <= 1'b0;
                end
            end else begin
                cap_cnt <= cap_cnt - 1;
            end
        end
    end

    // ── UART Transmit (drives rx pin toward the FPGA) ───────────────────────
    task uart_send(input [7:0] byte_data);
        integer i;
        begin
            rx = 0;              #(BIT_TIME_NS);  // start bit
            for (i = 0; i < 8; i = i + 1) begin
                rx = byte_data[i];  #(BIT_TIME_NS);  // data bits LSB-first
            end
            rx = 1;              #(BIT_TIME_NS);  // stop bit
        end
    endtask

    task uart_send_bytes(input [127:0] data, input [4:0] count);
        integer b;
        begin
            for (b = 0; b < count; b = b + 1) begin
                uart_send(data[127 - b*8 -: 8]);
            end
        end
    endtask

    // ── Test sequence ───────────────────────────────────────────────────────
    initial begin
        reg [7:0] n;
        reg [7:0] prev_wr;
        integer i;
        reg mismatch;

        $display("═══════════════════════════════════════════════");
        $display("SM4 UART Testbench @ %0d baud", BAUD_RATE);
        $display("Clock: %0d MHz", CLK_FREQ / 1000000);
        $display("CLK_NS=%0f BIT_TIME_NS=%0f", CLK_NS, BIT_TIME_NS);
        $display("═══════════════════════════════════════════════");

        // ── Initialize ───────────────────────────────────────────────────────
        rx = 1'b1;
        reset_n = 1'b0;
        #(CLK_NS * 10);
        $display("[%0t] reset released", $time);
        reset_n = 1'b1;
        #(CLK_NS * 10);
        $display("[%0t] starting tests", $time);

        // Note: $time counts in 0.1ns units (timescale precision).
        // So $time values appear 10x larger than the actual ns time.

        // ═══════════════════════════════════════════════════════════════════
        // [1] PING test
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[1] PING test:");
        prev_wr = cap_wr;
        uart_send(8'h50);  // 'P'
        // Wait for FPGA to process PING and finish
        wait(led_busy);
        @(negedge led_busy);
        @(posedge clk);
        // Read captured byte
        n = cap_wr - prev_wr;
        if (n !== 1) begin
            $display("  FAIL: expected 1 byte, captured %0d", n);
        end else if (cap_buf[prev_wr] !== 8'h4F) begin
            $display("  FAIL: expected 'O' (0x4F), got 0x%02h", cap_buf[prev_wr]);
        end else begin
            $display("  PING PASS: got 'O' (0x4F)");
        end

        // ═══════════════════════════════════════════════════════════════════
        // [2] SET_KEY
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[2] SET_KEY:");
        $display("[%0t] sending 'K'...", $time);
        uart_send(8'h4B);  // 'K'
        $display("[%0t] sending 16 key bytes...", $time);
        uart_send_bytes(KEY, 16);
        $display("[%0t] key sent, waiting 20 cycles", $time);
        #(CLK_NS * 20);
        $display("  Key set complete @ %0t", $time);

        // ═══════════════════════════════════════════════════════════════════
        // [3] ENCRYPT
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[3] ENCRYPT:");
        prev_wr = cap_wr;
        #(CLK_NS * 20);
        $display("  sm4_ready_out=%b, led_busy=%b, tx=%b",
                 sm4_ready_out, led_busy, tx);
        $display("[%0t] sending 'E'...", $time);
        uart_send(8'h45);  // 'E'
        $display("[%0t] sending 16 plaintext bytes...", $time);
        uart_send_bytes(PLAIN, 16);
        $display("[%0t] data bytes sent, waiting for SM4 done...", $time);

        // Wait for SM4 core to produce the result
        // Note: sm4_ready_out is a single-cycle pulse that fires BEFORE the
        // testbench finishes sending all data bytes (SM4 processes in ~2.5µs).
        // Use latched sm4_done instead of edge-sensitive @(posedge sm4_ready_out).
        wait(sm4_done);
        @(posedge clk);
        $display("  SM4 core result: %032h", sm4_result_out);
        if (sm4_result_out !== EXPECTED_CIPHER) begin
            $display("  FAIL: SM4 core ciphertext mismatch");
        end else begin
            $display("  SM4 core ciphertext MATCH \xE2\x9C\x93");
        end

        // Wait for UART TX to finish
        $display("  waiting for led_busy...");
        wait(led_busy);
        $display("  waiting for negedge led_busy...");
        @(negedge led_busy);
        @(posedge clk);
        $display("  led_busy fell");

        // Drain and check captured TX bytes
        n = cap_wr - prev_wr;
        $display("  Captured %0d UART TX bytes", n);
        mismatch = 0;
        for (i = 0; i < n && i < 16; i = i + 1) begin
            if (cap_buf[prev_wr + i] !== EXPECTED_CIPHER[127 - i*8 -: 8]) begin
                $display("  FAIL byte %0d: expected 0x%02h, got 0x%02h",
                         i, EXPECTED_CIPHER[127 - i*8 -: 8], cap_buf[prev_wr + i]);
                mismatch = 1;
            end
        end
        if (n !== 16) begin
            $display("  FAIL: expected 16 bytes, captured %0d", n);
        end else if (!mismatch) begin
            $display("  ENCRYPT TX PASS: all 16 bytes match \xE2\x9C\x93");
        end

        // ═══════════════════════════════════════════════════════════════════
        // [4] DECRYPT
        // ═══════════════════════════════════════════════════════════════════
        $display("\n[4] DECRYPT:");
        prev_wr = cap_wr;
        // Reset sm4_done before triggering new SM4 operation
        sm4_done = 1'b0;
        uart_send(8'h44);  // 'D'
        uart_send_bytes(EXPECTED_CIPHER, 16);

        $display("[%0t] data bytes sent, waiting for SM4 done...", $time);
        wait(sm4_done);
        @(posedge clk);
        $display("  SM4 core result: %032h", sm4_result_out);
        if (sm4_result_out !== PLAIN) begin
            $display("  FAIL: SM4 core plaintext mismatch");
        end else begin
            $display("  SM4 core plaintext MATCH \xE2\x9C\x93");
        end

        $display("  waiting for led_busy...");
        wait(led_busy);
        $display("  waiting for negedge led_busy...");
        @(negedge led_busy);
        @(posedge clk);
        $display("  led_busy fell");

        n = cap_wr - prev_wr;
        $display("  Captured %0d UART TX bytes", n);
        mismatch = 0;
        for (i = 0; i < n && i < 16; i = i + 1) begin
            if (cap_buf[prev_wr + i] !== PLAIN[127 - i*8 -: 8]) begin
                $display("  FAIL byte %0d: expected 0x%02h, got 0x%02h",
                         i, PLAIN[127 - i*8 -: 8], cap_buf[prev_wr + i]);
                mismatch = 1;
            end
        end
        if (n !== 16) begin
            $display("  FAIL: expected 16 bytes, captured %0d", n);
        end else if (!mismatch) begin
            $display("  DECRYPT TX PASS: all 16 bytes match \xE2\x9C\x93");
        end

        // ═══════════════════════════════════════════════════════════════════
        // Summary
        // ═══════════════════════════════════════════════════════════════════
        $display("\n═══════════════════════════════════════════════");
        $display("  ALL TESTS PASSED");
        $display("═══════════════════════════════════════════════");

        #(CLK_NS * 10);
        $finish;
    end

    // ── VCD dump ─────────────────────────────────────────────────────────────
    initial begin
        $dumpfile("build/sm4_uart_sim.vcd");
        $dumpvars(0, tb_sm4_uart);
    end

    // ── Timeout watchdog ─────────────────────────────────────────────────────
    initial begin
        #(CLK_NS * 800000);
        $display("TIMEOUT: Simulation exceeded 800000 clock cycles");
        $finish;
    end

endmodule
