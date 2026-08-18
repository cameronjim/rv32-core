// demo_tb: self checking testbench for the six demo programs in programs/.
// Wraps cpu_top with imem, dmem and the behavioral mmio model, drives switch
// and key stimulus, and checks the observable mmio behavior of every demo.

`timescale 1ns / 1ps

module demo_tb;

  localparam int DATA_WIDTH     = 32;
  localparam int BE_WIDTH       = DATA_WIDTH / 8;
  localparam int MEM_ADDR_WIDTH = 10;
  localparam int NUM_WORDS      = 1 << MEM_ADDR_WIDTH;

  localparam logic [DATA_WIDTH-1:0] POISON = 32'hA5A5_A5A5;

  localparam logic [19:0] DMEM_BASE_TAG = 20'h00001;
  localparam logic [15:0] MMIO_BASE_TAG = 16'hFFFF;

  // dmem window the memtest demo works over, and its word index in dmem
  localparam logic [DATA_WIDTH-1:0] MEMTEST_BASE  = 32'h0000_1800;
  localparam int                    MEMTEST_INDEX = 512;
  localparam int                    MEMTEST_WORDS = 8;

  // more events than any single demo produces inside its budget
  localparam int MAX_EV = 1024;

  logic clk;
  logic rst_n;

  logic [DATA_WIDTH-1:0] imem_addr;
  logic [DATA_WIDTH-1:0] imem_rdata;
  logic [DATA_WIDTH-1:0] dmem_addr;
  logic [DATA_WIDTH-1:0] dmem_wdata;
  logic [BE_WIDTH-1:0]   dmem_be;
  logic                  dmem_we;
  logic                  dmem_re;
  logic [DATA_WIDTH-1:0] dmem_rdata;

  logic                  dmem_sel;
  logic                  mmio_sel;
  logic [DATA_WIDTH-1:0] dmem_raw_rdata;
  logic [DATA_WIDTH-1:0] mmio_rdata;

  logic [9:0]            sw_in;
  logic [3:0]            key_in;
  logic [9:0]            mmio_ledr;
  logic [6:0]            mmio_hex[6];
  logic [DATA_WIDTH-1:0] mmio_cycle;
  logic                  mmio_wr_ledr;
  logic [5:0]            mmio_wr_hex;
  logic [DATA_WIDTH-1:0] mmio_wr_data;

  // address decode lives here, not in the core: dmem answers for 0x00001xxx
  // and the mmio model for 0xFFFFxxxx
  assign dmem_sel   = (dmem_addr[31:12] == DMEM_BASE_TAG);
  assign mmio_sel   = (dmem_addr[31:16] == MMIO_BASE_TAG);
  assign dmem_rdata = (dmem_re && dmem_sel) ? dmem_raw_rdata :
                      (dmem_re && mmio_sel) ? mmio_rdata : '0;

  cpu_top #(
    .DATA_WIDTH   (DATA_WIDTH),
    .RESET_VECTOR (32'h0000_0000)
  ) u_cpu (
    .clk        (clk),
    .rst_n      (rst_n),
    .imem_addr  (imem_addr),
    .imem_rdata (imem_rdata),
    .dmem_addr  (dmem_addr),
    .dmem_wdata (dmem_wdata),
    .dmem_be    (dmem_be),
    .dmem_we    (dmem_we),
    .dmem_re    (dmem_re),
    .dmem_rdata (dmem_rdata)
  );

  // INIT_FILE stays empty; each demo is loaded hierarchically below
  imem #(
    .ADDR_WIDTH (MEM_ADDR_WIDTH),
    .INIT_FILE  ("")
  ) u_imem (
    .clk   (clk),
    .addr  (imem_addr[MEM_ADDR_WIDTH+1:2]),
    .rdata (imem_rdata)
  );

  dmem #(
    .ADDR_WIDTH (MEM_ADDR_WIDTH),
    .DATA_WIDTH (DATA_WIDTH),
    .INIT_FILE  ("")
  ) u_dmem (
    .clk     (clk),
    .addr    (dmem_addr[MEM_ADDR_WIDTH+1:2]),
    .wdata   (dmem_wdata),
    .byte_en (dmem_be),
    .we      (dmem_we && dmem_sel),
    .rdata   (dmem_raw_rdata)
  );

  mmio_sim #(
    .DATA_WIDTH (DATA_WIDTH)
  ) u_mmio (
    .clk     (clk),
    .rst_n   (rst_n),
    .addr    (dmem_addr),
    .wdata   (dmem_wdata),
    .we      (dmem_we && mmio_sel),
    .re      (dmem_re && mmio_sel),
    .rdata   (mmio_rdata),
    .sw_in   (sw_in),
    .key_in  (key_in),
    .ledr_q  (mmio_ledr),
    .hex0_q  (mmio_hex[0]),
    .hex1_q  (mmio_hex[1]),
    .hex2_q  (mmio_hex[2]),
    .hex3_q  (mmio_hex[3]),
    .hex4_q  (mmio_hex[4]),
    .hex5_q  (mmio_hex[5]),
    .cycle_q (mmio_cycle),
    .wr_ledr (mmio_wr_ledr),
    .wr_hex  (mmio_wr_hex),
    .wr_data (mmio_wr_data)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // seven segment patterns for 0..F, the same table the programs keep in
  // .rodata, used to turn expected values into expected display writes
  logic [6:0] seg_table[16];

  // write log. The mmio write strobes are registered, so sampling one step
  // after the clock edge sees exactly the write that committed on it.
  string      cur_demo;
  int         cyc;
  logic       run_active;

  logic [9:0] ledr_val[MAX_EV];
  int         ledr_cyc[MAX_EV];
  int         ledr_n;

  int         hex_who[MAX_EV];
  logic [6:0] hex_val[MAX_EV];
  int         hex_cyc[MAX_EV];
  int         hex_n;

  initial begin
    seg_table = '{7'h3F, 7'h06, 7'h5B, 7'h4F, 7'h66, 7'h6D, 7'h7D, 7'h07,
                  7'h7F, 7'h6F, 7'h77, 7'h7C, 7'h39, 7'h5E, 7'h79, 7'h71};
    run_active = 1'b0;
    cyc        = 0;
    ledr_n     = 0;
    hex_n      = 0;
  end

  always @(posedge clk) begin
    #1;
    if (run_active) begin
      cyc = cyc + 1;
      if (mmio_wr_ledr) begin
        if (ledr_n < MAX_EV) begin
          ledr_val[ledr_n] = mmio_wr_data[9:0];
          ledr_cyc[ledr_n] = cyc;
        end
        ledr_n = ledr_n + 1;
      end
      for (int i = 0; i < 6; i++) begin
        if (mmio_wr_hex[i]) begin
          if (hex_n < MAX_EV) begin
            hex_who[hex_n] = i;
            hex_val[hex_n] = mmio_wr_data[6:0];
            hex_cyc[hex_n] = cyc;
          end
          hex_n = hex_n + 1;
        end
      end
    end
  end

  // control code samples one step after the recorder, so the ordering between
  // the two never depends on event scheduling
  task automatic step_cycles(input int n);
    for (int i = 0; i < n; i++) begin
      @(posedge clk);
      #2;
    end
  endtask

  task automatic fail(input string what, input string got, input string exp);
    $display("FAIL: %s: %s: got %s expected %s", cur_demo, what, got, exp);
    $fatal(1);
  endtask

  task automatic expect_hex(input string what, input logic [DATA_WIDTH-1:0] got,
                            input logic [DATA_WIDTH-1:0] exp);
    if (got !== exp) fail(what, $sformatf("0x%0h", got), $sformatf("0x%0h", exp));
  endtask

  task automatic expect_range(input string what, input int got,
                              input int lo, input int hi);
    if ((got < lo) || (got > hi))
      fail(what, $sformatf("%0d", got), $sformatf("%0d..%0d", lo, hi));
  endtask

  // how many writes one hex display has taken so far
  function automatic int hex_count(input int who);
    int n;
    n = 0;
    for (int i = 0; (i < hex_n) && (i < MAX_EV); i++)
      if (hex_who[i] == who) n = n + 1;
    return n;
  endfunction

  // write log index of the nth (zero based) write to one display, -1 if the
  // write has not happened; callers check hex_count first
  function automatic int hex_at(input int who, input int nth);
    int n;
    n = 0;
    for (int i = 0; (i < hex_n) && (i < MAX_EV); i++) begin
      if (hex_who[i] == who) begin
        if (n == nth) return i;
        n = n + 1;
      end
    end
    return -1;
  endfunction

  // reverse the digit table; -1 when the pattern is not a hex digit
  function automatic int seg_digit(input logic [6:0] seg);
    for (int i = 0; i < 16; i++) if (seg_table[i] == seg) return i;
    return -1;
  endfunction

  // load one demo image, poison the rest of dmem, then release reset
  task automatic start_demo(input string name);
    cur_demo = name;
    for (int i = 0; i < NUM_WORDS; i++) begin
      u_imem.mem[i] = '0;
      u_dmem.mem[i] = POISON;
    end
    $readmemh($sformatf("programs/hex/%s.hex", name), u_imem.mem);
    $readmemh($sformatf("programs/hex/%s_data.hex", name), u_dmem.mem);

    run_active = 1'b0;
    rst_n      = 1'b0;
    cyc        = 0;
    ledr_n     = 0;
    hex_n      = 0;
    step_cycles(2);
    rst_n      = 1'b1;
    run_active = 1'b1;
    $display("demo %s: start", name);
  endtask

  // led_blink: one lit bit walks up to LEDR[9] and back down, one write per
  // delay step, 18 writes per full bounce, measured near 103 cycles apart
  task automatic check_led_blink();
    int phase;
    int pos;

    start_demo("led_blink");
    while ((ledr_n < 20) && (cyc < 3000)) step_cycles(1);
    if (ledr_n < 20)
      fail("LEDR writes in 3000 cycles", $sformatf("%0d", ledr_n), "20");

    for (int i = 0; i < 20; i++) begin
      phase = i % 18;
      pos   = (phase < 10) ? phase : (18 - phase);
      expect_hex($sformatf("LEDR write %0d", i), ledr_val[i], 32'd1 << pos);
    end
    expect_range("first LEDR write cycle", ledr_cyc[0], 5, 60);
    for (int i = 1; i < 20; i++)
      expect_range($sformatf("LEDR write %0d spacing", i),
                   ledr_cyc[i] - ledr_cyc[i-1], 78, 130);
  endtask

  // counter: HEX4 and HEX5 go dark once, then a four write burst per count
  // with the BCD digits carried by hand, measured 82 cycles apart (73 before
  // the load stall; the delay loop reloads its counter from memory)
  task automatic check_counter();
    logic [6:0] exp0[11];

    exp0 = '{7'h3F, 7'h06, 7'h5B, 7'h4F, 7'h66, 7'h6D, 7'h7D, 7'h07,
             7'h7F, 7'h6F, 7'h3F};

    start_demo("counter");
    // HEX3 is written last in each burst, so 11 of those means 11 full counts
    while ((hex_count(3) < 11) && (cyc < 1500)) step_cycles(1);
    if (hex_count(3) < 11)
      fail("count bursts in 1500 cycles", $sformatf("%0d", hex_count(3)), "11");

    expect_range("HEX4 write count", hex_count(4), 1, 1);
    expect_range("HEX5 write count", hex_count(5), 1, 1);
    expect_hex("HEX4 blank", hex_val[hex_at(4, 0)], 7'h00);
    expect_hex("HEX5 blank", hex_val[hex_at(5, 0)], 7'h00);
    expect_range("HEX4 blank cycle", hex_cyc[hex_at(4, 0)], 1, 120);

    for (int i = 0; i < 11; i++)
      expect_hex($sformatf("HEX0 update %0d", i), hex_val[hex_at(0, i)], exp0[i]);
    // the tens digit only moves when the ones digit wraps past 9
    for (int i = 0; i < 10; i++)
      expect_hex($sformatf("HEX1 update %0d", i), hex_val[hex_at(1, i)], 7'h3F);
    expect_hex("HEX1 update 10", hex_val[hex_at(1, 10)], 7'h06);

    for (int i = 1; i < 11; i++)
      expect_range($sformatf("HEX0 update %0d spacing", i),
                   hex_cyc[hex_at(0, i)] - hex_cyc[hex_at(0, i-1)], 50, 120);
    expect_hex("LEDR untouched", mmio_ledr, 10'h000);
  endtask

  // switch_mirror: SW lands on LEDR and its three hex digits on HEX0..HEX2,
  // refreshed roughly every 38 cycles (34 before the load stall)
  task automatic check_switch_mirror();
    int deadline;

    sw_in = 10'h2A5;
    start_demo("switch_mirror");
    while (!((mmio_ledr == 10'h2A5) && (mmio_hex[0] == 7'h6D) &&
             (mmio_hex[1] == 7'h77) && (mmio_hex[2] == 7'h5B)) &&
           (cyc < 600)) step_cycles(1);
    expect_hex("LEDR mirrors 0x2A5", mmio_ledr, 10'h2A5);
    expect_hex("HEX0 shows 5", mmio_hex[0], 7'h6D);
    expect_hex("HEX1 shows A", mmio_hex[1], 7'h77);
    expect_hex("HEX2 shows 2", mmio_hex[2], 7'h5B);

    sw_in    = 10'h081;
    deadline = cyc + 600;
    while (!((mmio_ledr == 10'h081) && (mmio_hex[0] == 7'h06) &&
             (mmio_hex[1] == 7'h7F) && (mmio_hex[2] == 7'h3F)) &&
           (cyc < deadline)) step_cycles(1);
    expect_hex("LEDR mirrors 0x081", mmio_ledr, 10'h081);
    expect_hex("HEX0 shows 1", mmio_hex[0], 7'h06);
    expect_hex("HEX1 shows 8", mmio_hex[1], 7'h7F);
    expect_hex("HEX2 shows 0", mmio_hex[2], 7'h3F);
    sw_in = 10'h000;
  endtask

  // fibonacci: terms 0,1,1,2,3,5,8,13.. spread over HEX0..HEX5, with LEDR
  // pulsing 0x001 then 0x000 at every restart of the sequence
  task automatic check_fibonacci();
    logic [6:0] exp0[8];
    int         pulses;
    int         first_pulse;
    int         second_pulse;

    // low nibbles of 0,1,1,2,3,5,8,13 through the digit table
    exp0 = '{7'h3F, 7'h06, 7'h06, 7'h5B, 7'h4F, 7'h6D, 7'h7F, 7'h5E};

    start_demo("fibonacci");
    while (cyc < 6000) step_cycles(1);

    if (hex_count(0) < 8)
      fail("HEX0 terms in 6000 cycles", $sformatf("%0d", hex_count(0)), "8 or more");
    for (int i = 0; i < 8; i++)
      expect_hex($sformatf("HEX0 term %0d", i), hex_val[hex_at(0, i)], exp0[i]);

    pulses       = 0;
    first_pulse  = -1;
    second_pulse = -1;
    for (int i = 0; (i < ledr_n) && (i < MAX_EV); i++) begin
      expect_hex($sformatf("LEDR write %0d", i), ledr_val[i],
                 (i % 2 == 0) ? 32'h001 : 32'h000);
      if (ledr_val[i] == 10'h001) begin
        pulses = pulses + 1;
        if (first_pulse < 0) first_pulse = ledr_cyc[i];
        else if (second_pulse < 0) second_pulse = ledr_cyc[i];
      end
    end
    if (pulses < 2)
      fail("restart pulses in 6000 cycles", $sformatf("%0d", pulses), "2 or more");
    expect_range("first restart cycle", first_pulse, 5, 200);
    expect_range("restart period", second_pulse - first_pulse, 2000, 3500);
  endtask

  // memtest: walking ones then an address pattern over the dmem window at
  // 0x1800, LEDR reporting each phase and then the pass code. The phase 2 and
  // pass windows were re-measured after the load stall landed: this demo is
  // load heavy, so phase 2 moved from cycle 1605 to 1861 and the pass code
  // from 1680 to 1944. The windows below are centered on the new numbers.
  task automatic check_memtest();
    start_demo("memtest");
    while (cyc < 2500) step_cycles(1);

    if (ledr_n != 3) fail("LEDR write count", $sformatf("%0d", ledr_n), "3");
    expect_hex("LEDR phase 1 code", ledr_val[0], 10'h001);
    expect_range("LEDR phase 1 cycle", ledr_cyc[0], 5, 60);
    expect_hex("LEDR phase 2 code", ledr_val[1], 10'h002);
    expect_range("LEDR phase 2 cycle", ledr_cyc[1], 1500, 2200);
    expect_hex("LEDR pass code", ledr_val[2], 10'h3FF);
    expect_range("LEDR pass cycle", ledr_cyc[2], 1600, 2300);
    expect_hex("LEDR still passing at 2500", mmio_ledr, 10'h3FF);

    // MEMTEST_WORDS is 8 in the simulation build, shown as two hex digits
    expect_hex("HEX0 word count low", mmio_hex[0], 7'h7F);
    expect_hex("HEX1 word count high", mmio_hex[1], 7'h3F);

    // the window must be left holding the address pattern, not the poison
    for (int k = 0; k < MEMTEST_WORDS; k++)
      expect_hex($sformatf("dmem[0x%08h]", MEMTEST_BASE + 4*k),
                 u_dmem.mem[MEMTEST_INDEX + k], MEMTEST_BASE + 4*k);
  endtask

  // reaction: run once with no key press so the poll times out, then again
  // pressing as soon as the go signal appears
  task automatic check_reaction();
    int base;
    int deadline;
    int nibble;
    int elapsed;

    key_in = 4'h0;
    start_demo("reaction");
    while ((mmio_ledr != 10'h020) && (cyc < 1000)) step_cycles(1);
    expect_hex("run 1 go signal", mmio_ledr, 10'h020);
    expect_range("run 1 go signal cycle", cyc, 20, 400);
    while ((mmio_ledr != 10'h001) && (cyc < 8000)) step_cycles(1);
    expect_hex("run 1 timeout result", mmio_ledr, 10'h001);

    key_in = 4'h0;
    start_demo("reaction");
    while ((mmio_ledr != 10'h020) && (cyc < 1000)) step_cycles(1);
    expect_hex("run 2 go signal", mmio_ledr, 10'h020);

    base   = hex_n;
    key_in = 4'h1;
    while ((mmio_ledr != 10'h3FF) && (cyc < 3000)) step_cycles(1);
    expect_hex("run 2 press result", mmio_ledr, 10'h3FF);

    // hold the key until the six elapsed digits have been written out
    deadline = cyc + 400;
    while (((hex_n - base) < 6) && (cyc < deadline)) step_cycles(1);
    key_in = 4'h0;
    if ((hex_n - base) < 6)
      fail("run 2 elapsed digit writes", $sformatf("%0d", hex_n - base), "6");

    elapsed = 0;
    for (int i = 0; i < 6; i++) begin
      if (hex_who[base+i] != i)
        fail($sformatf("run 2 elapsed digit %0d target", i),
             $sformatf("HEX%0d", hex_who[base+i]), $sformatf("HEX%0d", i));
      nibble = seg_digit(hex_val[base+i]);
      if (nibble < 0)
        fail($sformatf("run 2 elapsed digit %0d", i),
             $sformatf("0x%02h", hex_val[base+i]), "a hex digit pattern");
      elapsed = elapsed | (nibble << (4*i));
    end
    if (elapsed == 0) fail("run 2 elapsed count", "0", "nonzero");
    $display("demo reaction: measured elapsed %0d cycles", elapsed);
  endtask

  initial begin
    $dumpfile("sim/build/demo_tb.vcd");
    $dumpvars(0, demo_tb);

    rst_n  = 1'b0;
    sw_in  = 10'h000;
    key_in = 4'h0;

    check_led_blink();
    check_counter();
    check_switch_mirror();
    check_fibonacci();
    check_memtest();
    check_reaction();

    $display("PASS: demo_tb");
    $finish;
  end

endmodule
