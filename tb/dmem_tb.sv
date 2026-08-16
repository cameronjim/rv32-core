// dmem_tb: self-checking testbench for the data memory.
// Covers full word and per-lane writes, write gating, overlapping writes to
// one word, the synchronous read protocol, read during write to one address,
// address independence, and INIT_FILE preload.

`timescale 1ns / 1ps

module dmem_tb;

  localparam int DATA_WIDTH      = 32;
  localparam int LANE_WIDTH      = 8;
  localparam int NUM_LANES       = DATA_WIDTH / LANE_WIDTH;
  localparam int MAIN_ADDR_WIDTH = 10;
  localparam int INIT_ADDR_WIDTH = 4;
  localparam int FIX_WORDS       = 16;
  localparam int CLK_PERIOD      = 10;

  // addresses used by the directed cases, kept apart so they cannot alias
  localparam int WORD_ADDR  = 4;
  localparam int OTHER_ADDR = 5;
  localparam int LANE_ADDR  = 8;
  localparam int HALF_ADDR  = 9;
  localparam int ACCUM_ADDR = 12;
  localparam int RDW_ADDR   = 20;
  localparam int VIRGIN_ADDR = 100;

  localparam logic [DATA_WIDTH-1:0] LANE_BASE = 32'hA1B2_C3D4;
  localparam logic [DATA_WIDTH-1:0] LANE_DATA = 32'h1122_3344;

  // Expected contents of tb/fixtures/dmem_fixture.hex, listed word 15 down to
  // word 0 because the concatenation builds a packed vector: word i is
  // FIX_DATA[i*DATA_WIDTH +: DATA_WIDTH].
  localparam logic [FIX_WORDS*DATA_WIDTH-1:0] FIX_DATA = {
    32'h600D_F00D,  // 15 last initialized word
    32'h1122_3344,  // 14
    32'hFEED_FACE,  // 13
    32'h0BAD_C0DE,  // 12
    32'hCAFE_F00D,  // 11
    32'h0102_0304,  // 10
    32'h7FFF_FFFF,  //  9
    32'h8000_0000,  //  8
    32'h0000_0000,  //  7
    32'h5A5A_5A5A,  //  6
    32'hA5A5_A5A5,  //  5
    32'h0000_600D,  //  4
    32'hFFFF_FFFF,  //  3
    32'h1234_5678,  //  2
    32'h0000_0001,  //  1
    32'hDEAD_BEEF   //  0
  };

  logic                       clk;

  logic [MAIN_ADDR_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0]      wdata;
  logic [NUM_LANES-1:0]       byte_en;
  logic                       we;
  logic [DATA_WIDTH-1:0]      rdata;

  logic [INIT_ADDR_WIDTH-1:0] init_addr;
  logic [DATA_WIDTH-1:0]      init_wdata;
  logic [NUM_LANES-1:0]       init_byte_en;
  logic                       init_we;
  logic [DATA_WIDTH-1:0]      init_rdata;

  logic [DATA_WIDTH-1:0]      expected;
  logic [DATA_WIDTH-1:0]      held;
  logic [NUM_LANES-1:0]       lane_en;
  int unsigned                checks;

  dmem #(
    .ADDR_WIDTH(MAIN_ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH)
  ) dut (
    .clk     (clk),
    .addr    (addr),
    .wdata   (wdata),
    .byte_en (byte_en),
    .we      (we),
    .rdata   (rdata)
  );

  // Fixture path is relative to the repo root, where simulations are run.
  dmem #(
    .ADDR_WIDTH(INIT_ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .INIT_FILE ("tb/fixtures/dmem_fixture.hex")
  ) dut_init (
    .clk     (clk),
    .addr    (init_addr),
    .wdata   (init_wdata),
    .byte_en (init_byte_en),
    .we      (init_we),
    .rdata   (init_rdata)
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

  // Drive one memory cycle and return one nanosecond after the capturing edge
  task automatic drive(input int idx, input logic [DATA_WIDTH-1:0] data,
                       input logic [NUM_LANES-1:0] lanes, input logic enable);
    addr    = idx[MAIN_ADDR_WIDTH-1:0];
    wdata   = data;
    byte_en = lanes;
    we      = enable;
    @(posedge clk);
    #1;
    we      = 1'b0;
    byte_en = '0;
  endtask

  task automatic write_word(input int idx, input logic [DATA_WIDTH-1:0] data,
                            input logic [NUM_LANES-1:0] lanes);
    drive(idx, data, lanes, 1'b1);
  endtask

  // Synchronous read protocol: present the address, let one rising edge capture
  // it, then sample rdata a delta later.
  task automatic check_word(input int idx, input logic [DATA_WIDTH-1:0] want,
                            input string label);
    addr = idx[MAIN_ADDR_WIDTH-1:0];
    @(posedge clk);
    #1;
    checks = checks + 1;
    if (rdata !== want) begin
      $display("FAIL: %s, word %0d expected 0x%08h got 0x%08h at time %0t", label, idx, want,
               rdata, $time);
      $fatal(1);
    end
  endtask

  task automatic write_init(input int idx, input logic [DATA_WIDTH-1:0] data,
                            input logic [NUM_LANES-1:0] lanes);
    init_addr    = idx[INIT_ADDR_WIDTH-1:0];
    init_wdata   = data;
    init_byte_en = lanes;
    init_we      = 1'b1;
    @(posedge clk);
    #1;
    init_we      = 1'b0;
    init_byte_en = '0;
  endtask

  task automatic check_init(input int idx, input logic [DATA_WIDTH-1:0] want,
                            input string label);
    init_addr = idx[INIT_ADDR_WIDTH-1:0];
    @(posedge clk);
    #1;
    checks = checks + 1;
    if (init_rdata !== want) begin
      $display("FAIL: %s, preload word %0d expected 0x%08h got 0x%08h at time %0t", label, idx,
               want, init_rdata, $time);
      $fatal(1);
    end
  endtask

  initial begin
    $dumpfile("sim/build/dmem_tb.vcd");
    $dumpvars(0, dmem_tb);

    checks       = 0;
    addr         = '0;
    wdata        = '0;
    byte_en      = '0;
    we           = 1'b0;
    init_addr    = '0;
    init_wdata   = '0;
    init_byte_en = '0;
    init_we      = 1'b0;

    // 1. Untouched words are undefined, so no INIT_FILE means no preload
    check_word(VIRGIN_ADDR, 'x, "word without INIT_FILE was initialized");

    // 2. Full word write then read back
    write_word(WORD_ADDR, 32'hDEAD_BEEF, 4'b1111);
    check_word(WORD_ADDR, 32'hDEAD_BEEF, "full word write did not read back");

    // 3. Two addresses hold independent data
    write_word(OTHER_ADDR, 32'h1234_5678, 4'b1111);
    check_word(OTHER_ADDR, 32'h1234_5678, "second address did not read back");
    check_word(WORD_ADDR, 32'hDEAD_BEEF, "first address disturbed by a write elsewhere");

    // 4. Each byte lane written on its own leaves the other three alone
    for (int i = 0; i < NUM_LANES; i++) begin
      write_word(LANE_ADDR, LANE_BASE, 4'b1111);
      check_word(LANE_ADDR, LANE_BASE, "lane test baseline did not stick");
      lane_en    = '0;
      lane_en[i] = 1'b1;
      write_word(LANE_ADDR, LANE_DATA, lane_en);
      expected                           = LANE_BASE;
      expected[i*LANE_WIDTH+:LANE_WIDTH] = LANE_DATA[i*LANE_WIDTH+:LANE_WIDTH];
      check_word(LANE_ADDR, expected, "one-hot byte lane write hit the wrong lanes");
    end

    // 5. Halfword writes on the low and high halves
    write_word(HALF_ADDR, 32'hFFFF_FFFF, 4'b1111);
    write_word(HALF_ADDR, 32'hAAAA_5555, 4'b0011);
    check_word(HALF_ADDR, 32'hFFFF_5555, "low halfword write wrong");
    write_word(HALF_ADDR, 32'hFFFF_FFFF, 4'b1111);
    write_word(HALF_ADDR, 32'hAAAA_5555, 4'b1100);
    check_word(HALF_ADDR, 32'hAAAA_FFFF, "high halfword write wrong");

    // 6. we low with every lane enabled writes nothing
    drive(WORD_ADDR, 32'h0BAD_0BAD, 4'b1111, 1'b0);
    check_word(WORD_ADDR, 32'hDEAD_BEEF, "write happened while we was low");

    // 7. we high with no lane enabled writes nothing
    drive(WORD_ADDR, 32'h0BAD_0BAD, 4'b0000, 1'b1);
    check_word(WORD_ADDR, 32'hDEAD_BEEF, "write happened with byte_en clear");

    // 8. Overlapping lane writes to one word accumulate
    write_word(ACCUM_ADDR, 32'h0000_0000, 4'b1111);
    write_word(ACCUM_ADDR, 32'h0000_00AA, 4'b0001);
    check_word(ACCUM_ADDR, 32'h0000_00AA, "first accumulate step wrong");
    write_word(ACCUM_ADDR, 32'h0000_BB00, 4'b0010);
    check_word(ACCUM_ADDR, 32'h0000_BBAA, "second accumulate step wrong");
    write_word(ACCUM_ADDR, 32'hCCDD_0000, 4'b1100);
    check_word(ACCUM_ADDR, 32'hCCDD_BBAA, "third accumulate step wrong");
    write_word(ACCUM_ADDR, 32'h0000_1100, 4'b0010);
    check_word(ACCUM_ADDR, 32'hCCDD_11AA, "overwriting one lane disturbed the others");

    // 9. Reads are synchronous: a new address does not reach rdata until the
    //    next rising edge captures it, and it does reach rdata on that edge
    check_word(WORD_ADDR, 32'hDEAD_BEEF, "synchronous read setup");
    held = rdata;
    addr = OTHER_ADDR[MAIN_ADDR_WIDTH-1:0];
    // walk to just before the next rising edge without crossing it
    #(CLK_PERIOD - 2);
    if (rdata !== held) begin
      $display("FAIL: rdata moved to 0x%08h before the capturing edge at time %0t", rdata, $time);
      $fatal(1);
    end
    checks = checks + 1;
    @(posedge clk);
    #1;
    if (rdata !== 32'h1234_5678) begin
      $display("FAIL: registered read of word %0d gave 0x%08h at time %0t", OTHER_ADDR, rdata,
               $time);
      $fatal(1);
    end
    checks = checks + 1;

    // 9b. Read during write to one address on one edge returns the OLD word.
    //     This is the M10K read-during-write behavior; the core never depends
    //     on new data here because the load stall separates the two by a cycle.
    write_word(RDW_ADDR, 32'h1111_2222, 4'b1111);
    addr    = RDW_ADDR[MAIN_ADDR_WIDTH-1:0];
    wdata   = 32'h3333_4444;
    byte_en = 4'b1111;
    we      = 1'b1;
    @(posedge clk);
    #1;
    we      = 1'b0;
    byte_en = '0;
    checks  = checks + 1;
    if (rdata !== 32'h1111_2222) begin
      $display("FAIL: read during write returned 0x%08h, expected the old word 0x11112222",
               rdata);
      $fatal(1);
    end
    check_word(RDW_ADDR, 32'h3333_4444, "read during write lost the write itself");

    // 10. The preloaded instance holds the fixture
    for (int i = 0; i < FIX_WORDS; i++) begin
      check_init(i, FIX_DATA[i*DATA_WIDTH+:DATA_WIDTH], "preload word mismatch");
    end
    check_init(0, 32'hDEAD_BEEF, "preload word 0 wrong");
    check_init(FIX_WORDS - 1, 32'h600D_F00D, "last preloaded word wrong");

    // 11. Writes land on top of preloaded contents without touching neighbors
    write_init(3, 32'h0000_0007, 4'b1111);
    check_init(3, 32'h0000_0007, "write over a preloaded word failed");
    check_init(2, 32'h1234_5678, "write over a preloaded word hit its neighbor");
    check_init(4, 32'h0000_600D, "write over a preloaded word hit its neighbor");

    // 12. The two instances stay independent
    check_word(WORD_ADDR, 32'hDEAD_BEEF, "main instance disturbed by the preload instance");

    if (checks == 0) begin
      $display("FAIL: no checks executed");
      $fatal(1);
    end

    $display("PASS: dmem");
    $finish;
  end

endmodule
