// imem_tb: self-checking testbench for the instruction memory.
// Covers the INIT_FILE preload path at two different ADDR_WIDTH values, the
// empty INIT_FILE guard, and the positive edge registered read across the
// address range.

`timescale 1ns / 1ps

module imem_tb;

  localparam int INSTR_WIDTH     = 32;
  localparam int MAIN_ADDR_WIDTH = 10;
  localparam int ALT_ADDR_WIDTH  = 4;
  localparam int BARE_ADDR_WIDTH = 6;
  localparam int FIX_WORDS       = 16;
  localparam int CLK_PERIOD      = 10;

  // Expected contents of tb/fixtures/imem_fixture.hex, listed word 15 down to
  // word 0 because the concatenation builds a packed vector: word i is
  // FIX_DATA[i*INSTR_WIDTH +: INSTR_WIDTH].
  localparam logic [FIX_WORDS*INSTR_WIDTH-1:0] FIX_DATA = {
    32'h0000_600D,  // 15 done magic, also the last initialized word
    32'hFFFF_FFFF,  // 14
    32'h0000_0013,  // 13 nop
    32'hDEAD_B6B7,  // 12 lui  x13, 0xDEADB
    32'h0020_B633,  // 11 sltu x12, x1, x2
    32'h0020_A5B3,  // 10 slt  x11, x1, x2
    32'h4020_D533,  //  9 sra  x10, x1, x2
    32'h0020_D4B3,  //  8 srl  x9,  x1, x2
    32'h0020_9433,  //  7 sll  x8,  x1, x2
    32'h0020_C3B3,  //  6 xor  x7,  x1, x2
    32'h0020_E333,  //  5 or   x6,  x1, x2
    32'h0020_F2B3,  //  4 and  x5,  x1, x2
    32'h4020_8233,  //  3 sub  x4,  x1, x2
    32'h0020_81B3,  //  2 add  x3,  x1, x2
    32'h00C0_0113,  //  1 addi x2,  x0, 12
    32'h0050_0093   //  0 addi x1,  x0, 5
  };

  logic clk;

  logic [MAIN_ADDR_WIDTH-1:0] main_addr;
  logic [INSTR_WIDTH-1:0]     main_rdata;

  logic [ALT_ADDR_WIDTH-1:0]  alt_addr;
  logic [INSTR_WIDTH-1:0]     alt_rdata;

  logic [BARE_ADDR_WIDTH-1:0] bare_addr;
  logic [INSTR_WIDTH-1:0]     bare_rdata;

  logic [INSTR_WIDTH-1:0] held;
  int unsigned            checks;

  // Fixture path is relative to the repo root, where simulations are run.
  imem #(
    .ADDR_WIDTH(MAIN_ADDR_WIDTH),
    .INIT_FILE ("tb/fixtures/imem_fixture.hex")
  ) dut_main (
    .clk   (clk),
    .addr  (main_addr),
    .rdata (main_rdata)
  );

  // same fixture, narrower address space, exactly filled by the 16 words
  imem #(
    .ADDR_WIDTH(ALT_ADDR_WIDTH),
    .INIT_FILE ("tb/fixtures/imem_fixture.hex")
  ) dut_alt (
    .clk   (clk),
    .addr  (alt_addr),
    .rdata (alt_rdata)
  );

  // default INIT_FILE, so the $readmemh guard must skip the load entirely
  imem #(
    .ADDR_WIDTH(BARE_ADDR_WIDTH)
  ) dut_bare (
    .clk   (clk),
    .addr  (bare_addr),
    .rdata (bare_rdata)
  );

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  // Watchdog so a hung testbench fails instead of running forever
  initial begin
    #10000;
    $display("FAIL: timeout, testbench did not finish");
    $fatal(1);
  end

  // The read port is registered on the rising edge, the same edge the core's
  // pc register launches the address on, so every check drives the address,
  // waits for that edge, and samples one nanosecond later.
  task automatic check_main(input int idx, input logic [INSTR_WIDTH-1:0] expected,
                            input string label);
    main_addr = idx[MAIN_ADDR_WIDTH-1:0];
    @(posedge clk);
    #1;
    checks = checks + 1;
    if (main_rdata !== expected) begin
      $display("FAIL: %s, dut_main word %0d expected 0x%08h got 0x%08h at time %0t", label, idx,
               expected, main_rdata, $time);
      $fatal(1);
    end
  endtask

  task automatic check_alt(input int idx, input logic [INSTR_WIDTH-1:0] expected,
                           input string label);
    alt_addr = idx[ALT_ADDR_WIDTH-1:0];
    @(posedge clk);
    #1;
    checks = checks + 1;
    if (alt_rdata !== expected) begin
      $display("FAIL: %s, dut_alt word %0d expected 0x%08h got 0x%08h at time %0t", label, idx,
               expected, alt_rdata, $time);
      $fatal(1);
    end
  endtask

  task automatic check_bare(input int idx, input logic [INSTR_WIDTH-1:0] expected,
                            input string label);
    bare_addr = idx[BARE_ADDR_WIDTH-1:0];
    @(posedge clk);
    #1;
    checks = checks + 1;
    if (bare_rdata !== expected) begin
      $display("FAIL: %s, dut_bare word %0d expected 0x%08h got 0x%08h at time %0t", label, idx,
               expected, bare_rdata, $time);
      $fatal(1);
    end
  endtask

  initial begin
    $dumpfile("sim/build/imem_tb.vcd");
    $dumpvars(0, imem_tb);

    checks    = 0;
    main_addr = '0;
    alt_addr  = '0;
    bare_addr = '0;

    // 1. Every fixture word reads back from the default width instance
    for (int i = 0; i < FIX_WORDS; i++) begin
      check_main(i, FIX_DATA[i*INSTR_WIDTH+:INSTR_WIDTH], "fixture word mismatch");
    end

    // 2. Spot checks against literals, including the first and last loaded word
    check_main(0, 32'h0050_0093, "word 0 wrong");
    check_main(1, 32'h00C0_0113, "word 1 wrong");
    check_main(7, 32'h0020_9433, "word 7 wrong");
    check_main(12, 32'hDEAD_B6B7, "word 12 wrong");
    check_main(FIX_WORDS - 1, 32'h0000_600D, "last initialized word wrong");

    // 3. Words past the end of the fixture stay uninitialized
    check_main(FIX_WORDS, 'x, "word past the fixture was written");
    check_main((1 << MAIN_ADDR_WIDTH) - 1, 'x, "top word of the array was written");

    // 4. The read is registered, not asynchronous: a new address does not
    //    disturb rdata until the next rising edge, then it appears
    check_main(3, 32'h4020_8233, "word 3 wrong before the hold check");
    held      = main_rdata;
    main_addr = 10'd9;
    #0;
    checks = checks + 1;
    if (main_rdata !== held) begin
      $display("FAIL: rdata changed in the same time step as addr, got 0x%08h at time %0t",
               main_rdata, $time);
      $fatal(1);
    end
    // still ahead of the rising edge, so the old word must still be there
    #(CLK_PERIOD / 4);
    checks = checks + 1;
    if (main_rdata !== held) begin
      $display("FAIL: rdata changed before the rising edge, got 0x%08h at time %0t", main_rdata,
               $time);
      $fatal(1);
    end
    @(posedge clk);
    #1;
    checks = checks + 1;
    if (main_rdata !== 32'h4020_D533) begin
      $display("FAIL: registered read of word 9 gave 0x%08h at time %0t", main_rdata, $time);
      $fatal(1);
    end

    // 5. Re-reading an address returns the same word, nothing is consumed
    check_main(3, 32'h4020_8233, "re-read of word 3 changed");

    // 6. Holding one address across several edges keeps rdata stable
    repeat (3) begin
      @(posedge clk);
      #1;
      checks = checks + 1;
      if (main_rdata !== 32'h4020_8233) begin
        $display("FAIL: held address drifted to 0x%08h at time %0t", main_rdata, $time);
        $fatal(1);
      end
    end

    // 7. A second instance with a different ADDR_WIDTH loads the same fixture
    for (int i = 0; i < FIX_WORDS; i++) begin
      check_alt(i, FIX_DATA[i*INSTR_WIDTH+:INSTR_WIDTH], "narrow instance word mismatch");
    end
    check_alt(0, 32'h0050_0093, "narrow instance word 0 wrong");
    check_alt((1 << ALT_ADDR_WIDTH) - 1, 32'h0000_600D, "narrow instance last word wrong");

    // 8. An empty INIT_FILE skips the load and leaves the array untouched
    check_bare(0, 'x, "empty INIT_FILE instance was initialized");
    check_bare((1 << BARE_ADDR_WIDTH) - 1, 'x, "empty INIT_FILE instance was initialized");

    // 9. The instances stay independent: the main instance still holds its word
    check_main(0, 32'h0050_0093, "main instance disturbed by the other instances");

    if (checks == 0) begin
      $display("FAIL: no checks executed");
      $fatal(1);
    end

    $display("PASS: imem");
    $finish;
  end

endmodule
