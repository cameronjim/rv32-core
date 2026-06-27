// mmio_tb: self-checking testbench for the synthesizable mmio block. Runs the
// dut and the behavioral tb/lib/mmio_sim.sv reference on identical stimulus and
// compares rdata, all register state, the uart busy flag and the serial line
// every cycle, directed then randomized.

`timescale 1ns / 1ps

module mmio_tb;

  localparam int DATA_WIDTH = 32;
  localparam int LEDR_WIDTH = 10;
  localparam int SEG_WIDTH  = 7;
  localparam int HEX_COUNT  = 6;
  localparam int CLK_PERIOD = 10;
  localparam int RAND_ITERS = 3000;

  // Both models get the same small divider so a frame finishes in 160 clocks
  // instead of 4340. Must stay even so the bit centre sampling below lands on a
  // clean half bit.
  localparam int BAUD_DIV   = 16;
  // start bit, eight data bits, stop bit
  localparam int FRAME_BITS = 10;

  // The reference decodes the full architectural address, the dut only the low
  // 16 bits, so every cross-checked access carries the real mmio base.
  localparam logic [DATA_WIDTH-1:0] MMIO_BASE = 32'hFFFF_0000;

  localparam logic [15:0] OFF_LEDR  = 16'h0000;
  localparam logic [15:0] OFF_SW    = 16'h0004;
  localparam logic [15:0] OFF_KEY   = 16'h0008;
  localparam logic [15:0] OFF_HEX0  = 16'h0010;
  localparam logic [15:0] OFF_HEX1  = 16'h0014;
  localparam logic [15:0] OFF_HEX2  = 16'h0018;
  localparam logic [15:0] OFF_HEX3  = 16'h001C;
  localparam logic [15:0] OFF_HEX4  = 16'h0020;
  localparam logic [15:0] OFF_HEX5  = 16'h0024;
  localparam logic [15:0] OFF_CYCLE = 16'h0030;
  localparam logic [15:0] OFF_UDATA = 16'h0040;
  localparam logic [15:0] OFF_USTAT = 16'h0044;

  logic                  clk;
  logic                  rst_n;
  logic [DATA_WIDTH-1:0] addr;
  logic [DATA_WIDTH-1:0] wdata;
  logic                  we;
  logic                  re;
  logic [9:0]            sw_in;
  logic [3:0]            key_in;

  logic [DATA_WIDTH-1:0] rdata_dut;
  logic [LEDR_WIDTH-1:0] ledr_dut;
  logic [SEG_WIDTH-1:0]  hex_dut[HEX_COUNT];
  logic [DATA_WIDTH-1:0] cycle_dut;
  logic                  uart_tx_dut;
  logic                  uart_busy_dut;

  logic [DATA_WIDTH-1:0] rdata_ref;
  logic [LEDR_WIDTH-1:0] ledr_ref;
  logic [SEG_WIDTH-1:0]  hex_ref[HEX_COUNT];
  logic [DATA_WIDTH-1:0] cycle_ref;
  logic                  uart_tx_ref;
  logic                  uart_busy_ref;
  logic                  wr_ledr_ref;
  logic [5:0]            wr_hex_ref;
  logic [DATA_WIDTH-1:0] wr_data_ref;

  // cross_check off means the reference is knowingly being driven outside its
  // decode, so only the dut is judged for those cycles
  logic        cross_check;
  logic        monitor_en;
  string       phase;
  int unsigned rand_iter;
  int unsigned checks;

  integer rand_seed = 32'd20260806;

  mmio #(
    .DATA_WIDTH (DATA_WIDTH),
    .BAUD_DIV   (BAUD_DIV)
  ) dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .addr      (addr),
    .wdata     (wdata),
    .we        (we),
    .re        (re),
    .rdata     (rdata_dut),
    .sw_in     (sw_in),
    .key_in    (key_in),
    .ledr_out  (ledr_dut),
    .hex0_out  (hex_dut[0]),
    .hex1_out  (hex_dut[1]),
    .hex2_out  (hex_dut[2]),
    .hex3_out  (hex_dut[3]),
    .hex4_out  (hex_dut[4]),
    .hex5_out  (hex_dut[5]),
    .uart_tx_o (uart_tx_dut)
  );

  // Reference model. Its port shape differs: it exposes register state as
  // *_q plus write strobes instead of driving named board outputs.
  mmio_sim #(
    .DATA_WIDTH (DATA_WIDTH),
    .BAUD_DIV   (BAUD_DIV)
  ) ref_model (
    .clk       (clk),
    .rst_n     (rst_n),
    .addr      (addr),
    .wdata     (wdata),
    .we        (we),
    .re        (re),
    .rdata     (rdata_ref),
    .sw_in     (sw_in),
    .key_in    (key_in),
    .ledr_q    (ledr_ref),
    .hex0_q    (hex_ref[0]),
    .hex1_q    (hex_ref[1]),
    .hex2_q    (hex_ref[2]),
    .hex3_q    (hex_ref[3]),
    .hex4_q    (hex_ref[4]),
    .hex5_q    (hex_ref[5]),
    .cycle_q   (cycle_ref),
    .uart_tx_o (uart_tx_ref),
    .uart_busy (uart_busy_ref),
    .wr_ledr   (wr_ledr_ref),
    .wr_hex    (wr_hex_ref),
    .wr_data   (wr_data_ref)
  );

  // The dut has no cycle counter port; the board top never needs one. Its uart
  // busy flag is internal too: software sees it through UART_STATUS.
  assign cycle_dut     = dut.cycle_q;
  assign uart_busy_dut = dut.uart_busy;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  initial begin
    #400000;
    $display("FAIL: timeout, testbench did not finish");
    $fatal(1);
  end

  function automatic logic [15:0] mapped_off(input logic [3:0] sel);
    case (sel)
      4'd0:    mapped_off = OFF_LEDR;
      4'd1:    mapped_off = OFF_SW;
      4'd2:    mapped_off = OFF_KEY;
      4'd3:    mapped_off = OFF_HEX0;
      4'd4:    mapped_off = OFF_HEX1;
      4'd5:    mapped_off = OFF_HEX2;
      4'd6:    mapped_off = OFF_HEX3;
      4'd7:    mapped_off = OFF_HEX4;
      4'd8:    mapped_off = OFF_HEX5;
      4'd10:   mapped_off = OFF_UDATA;
      4'd11:   mapped_off = OFF_USTAT;
      default: mapped_off = OFF_CYCLE;
    endcase
  endfunction

  function automatic logic [15:0] hex_off(input int idx);
    hex_off = OFF_HEX0 + (idx * 4);
  endfunction

  task automatic fail_now(input string what);
    $display("FAIL: %s during %s, iter %0d, addr 0x%08h we %0b re %0b at time %0t", what, phase,
             rand_iter, addr, we, re, $time);
    $fatal(1);
  endtask

  // Full dut versus reference comparison: read data, both register banks, the
  // outputs that carry them, and the free-running counter.
  task automatic compare_models();
    checks = checks + 1;
    if (cross_check) begin
      if (rdata_dut !== rdata_ref) begin
        $display("dut rdata 0x%08h, ref rdata 0x%08h", rdata_dut, rdata_ref);
        fail_now("rdata mismatch");
      end
      if (ledr_dut !== ledr_ref) begin
        $display("dut ledr 0x%03h, ref ledr 0x%03h", ledr_dut, ledr_ref);
        fail_now("ledr mismatch");
      end
      for (int i = 0; i < HEX_COUNT; i++) begin
        if (hex_dut[i] !== hex_ref[i]) begin
          $display("hex%0d: dut 0x%02h, ref 0x%02h", i, hex_dut[i], hex_ref[i]);
          fail_now("hex mismatch");
        end
      end
      if (cycle_dut !== cycle_ref) begin
        $display("dut cycle 0x%08h, ref cycle 0x%08h", cycle_dut, cycle_ref);
        fail_now("cycle counter mismatch");
      end
      if (uart_tx_dut !== uart_tx_ref) begin
        $display("dut uart_tx %0b, ref uart_tx %0b", uart_tx_dut, uart_tx_ref);
        fail_now("uart line mismatch");
      end
      if (uart_busy_dut !== uart_busy_ref) begin
        $display("dut uart busy %0b, ref uart busy %0b", uart_busy_dut, uart_busy_ref);
        fail_now("uart busy mismatch");
      end
    end
  endtask

  // Cycle by cycle cross check, sampled mid cycle where everything is settled.
  // Plain always because it only logs and checks.
  always @(negedge clk) begin
    if (monitor_en) begin
      compare_models();
    end
  end

  // One bus cycle at a raw address. Entered and left one nanosecond after a
  // posedge, so each call consumes exactly one clock.
  task automatic bus_raw(input logic [DATA_WIDTH-1:0] a, input logic [DATA_WIDTH-1:0] data,
                         input logic do_we, input logic do_re,
                         output logic [DATA_WIDTH-1:0] got);
    addr  = a;
    wdata = data;
    we    = do_we;
    re    = do_re;
    #1;
    got = rdata_dut;
    compare_models();
    @(posedge clk);
    #1;
    we = 1'b0;
    re = 1'b0;
  endtask

  task automatic bus_op(input logic [15:0] off, input logic [DATA_WIDTH-1:0] data,
                        input logic do_we, input logic do_re,
                        output logic [DATA_WIDTH-1:0] got);
    bus_raw(MMIO_BASE | {16'h0000, off}, data, do_we, do_re, got);
  endtask

  task automatic bus_write(input logic [15:0] off, input logic [DATA_WIDTH-1:0] data);
    logic [DATA_WIDTH-1:0] ignored;
    bus_op(off, data, 1'b1, 1'b0, ignored);
  endtask

  task automatic bus_read(input logic [15:0] off, output logic [DATA_WIDTH-1:0] got);
    bus_op(off, 32'h0000_0000, 1'b0, 1'b1, got);
  endtask

  task automatic idle_cycle();
    logic [DATA_WIDTH-1:0] ignored;
    bus_op(16'h0000, 32'h0000_0000, 1'b0, 1'b0, ignored);
  endtask

  task automatic expect_read(input logic [15:0] off, input logic [DATA_WIDTH-1:0] want,
                             input string label);
    logic [DATA_WIDTH-1:0] got;
    bus_read(off, got);
    checks = checks + 1;
    if (got !== want) begin
      $display("FAIL: %s, read of offset 0x%04h expected 0x%08h got 0x%08h at time %0t", label, off,
               want, got, $time);
      $fatal(1);
    end
  endtask

  task automatic expect_ledr_out(input logic [LEDR_WIDTH-1:0] want, input string label);
    checks = checks + 1;
    if (ledr_dut !== want) begin
      $display("FAIL: %s, ledr_out expected 0x%03h got 0x%03h at time %0t", label, want, ledr_dut,
               $time);
      $fatal(1);
    end
  endtask

  task automatic expect_hex_out(input int idx, input logic [SEG_WIDTH-1:0] want,
                                input string label);
    checks = checks + 1;
    if (hex_dut[idx] !== want) begin
      $display("FAIL: %s, hex%0d_out expected 0x%02h got 0x%02h at time %0t", label, idx, want,
               hex_dut[idx], $time);
      $fatal(1);
    end
  endtask

  // Spins until the free-running counter reaches target, keeping the caller on
  // the usual "one nanosecond after a posedge" footing. The counter advances
  // every clock, so it is the cheapest frame-relative clock the tb has.
  task automatic wait_cycle_count(input logic [DATA_WIDTH-1:0] target);
    while (cycle_dut < target) begin
      @(posedge clk);
      #1;
    end
  endtask

  // The one serial decoder, sampling both models at the same instants so an
  // asymmetric decode cannot hide a difference between them. Call it right
  // after the write that started the frame, passing the counter value read
  // there: that cycle is bit 0 of the frame, so bit k is centred BAUD_DIV/2
  // clocks into its own slot.
  task automatic decode_frame(input logic [DATA_WIDTH-1:0] t0,
                              output logic [FRAME_BITS-1:0] frame_dut,
                              output logic [FRAME_BITS-1:0] frame_ref);
    for (int k = 0; k < FRAME_BITS; k++) begin
      wait_cycle_count(t0 + (k * BAUD_DIV) + (BAUD_DIV / 2));
      frame_dut[k] = uart_tx_dut;
      frame_ref[k] = uart_tx_ref;
    end
  endtask

  task automatic expect_frame(input logic [FRAME_BITS-1:0] frame_dut,
                              input logic [FRAME_BITS-1:0] frame_ref,
                              input logic [7:0] want, input string label);
    checks = checks + 1;
    if (frame_dut !== frame_ref) begin
      $display("FAIL: %s, dut frame 0b%010b, ref frame 0b%010b at time %0t", label, frame_dut,
               frame_ref, $time);
      $fatal(1);
    end
    if (frame_dut[0] !== 1'b0) begin
      $display("FAIL: %s, start bit was not low, frame 0b%010b at time %0t", label, frame_dut,
               $time);
      $fatal(1);
    end
    if (frame_dut[FRAME_BITS-1] !== 1'b1) begin
      $display("FAIL: %s, stop bit was not high, frame 0b%010b at time %0t", label, frame_dut,
               $time);
      $fatal(1);
    end
    if (frame_dut[8:1] !== want) begin
      $display("FAIL: %s, decoded 0x%02h expected 0x%02h at time %0t", label, frame_dut[8:1], want,
               $time);
      $fatal(1);
    end
  endtask

  task automatic expect_uart(input logic want_tx, input logic want_busy, input string label);
    checks = checks + 1;
    if (uart_tx_dut !== want_tx || uart_busy_dut !== want_busy) begin
      $display("FAIL: %s, dut tx %0b busy %0b expected tx %0b busy %0b at time %0t", label,
               uart_tx_dut, uart_busy_dut, want_tx, want_busy, $time);
      $fatal(1);
    end
    if (uart_tx_ref !== want_tx || uart_busy_ref !== want_busy) begin
      $display("FAIL: %s, ref tx %0b busy %0b expected tx %0b busy %0b at time %0t", label,
               uart_tx_ref, uart_busy_ref, want_tx, want_busy, $time);
      $fatal(1);
    end
  endtask

  // A UART_DATA write that also proves when busy becomes visible: the start
  // pulse is taken combinationally, so busy already reads 1 in the write cycle
  // while the line is still idling high. tx only drops to the start bit on the
  // edge that ends this cycle, which is where the frame timing starts.
  task automatic uart_write(input logic [DATA_WIDTH-1:0] data, input string label);
    addr  = MMIO_BASE | {16'h0000, OFF_UDATA};
    wdata = data;
    we    = 1'b1;
    re    = 1'b0;
    #1;
    expect_uart(1'b1, 1'b1, label);
    compare_models();
    @(posedge clk);
    #1;
    we = 1'b0;
    re = 1'b0;
  endtask

  // Holds reset for the given number of clocks, returning one nanosecond after
  // the release edge with both models cleared and their counters at zero.
  task automatic do_reset(input int cycles);
    rst_n = 1'b0;
    addr  = MMIO_BASE;
    wdata = '0;
    we    = 1'b0;
    re    = 1'b0;
    repeat (cycles) @(posedge clk);
    #1;
    rst_n = 1'b1;
  endtask

  task automatic expect_all_clear(input string label);
    expect_ledr_out('0, label);
    for (int i = 0; i < HEX_COUNT; i++) begin
      expect_hex_out(i, '0, label);
    end
    if (cycle_dut !== '0) begin
      $display("FAIL: %s, cycle counter expected 0 got 0x%08h at time %0t", label, cycle_dut,
               $time);
      $fatal(1);
    end
    checks = checks + 1;
  endtask

  logic [DATA_WIDTH-1:0] got;
  logic [DATA_WIDTH-1:0] frame_t0;
  logic [FRAME_BITS-1:0] frame_dut;
  logic [FRAME_BITS-1:0] frame_ref;
  logic [DATA_WIDTH-1:0] rnd_a;
  logic [DATA_WIDTH-1:0] rnd_d;
  logic [DATA_WIDTH-1:0] rnd_c;
  logic [DATA_WIDTH-1:0] r_off;
  logic [3:0]            sel;

  initial begin
    $dumpfile("sim/build/mmio_tb.vcd");
    $dumpvars(0, mmio_tb);

    checks      = 0;
    rand_iter   = 0;
    cross_check = 1'b1;
    monitor_en  = 1'b0;
    phase       = "startup";
    addr        = MMIO_BASE;
    wdata       = '0;
    we          = 1'b0;
    re          = 1'b0;
    sw_in       = '0;
    key_in      = '0;
    rst_n       = 1'b0;

    #1;
    // The reference prints a line per write; that trace would bury the result.
    ref_model.log_writes = 1'b0;

    // 1. Reset state: registers and counter clear, reads of them return zero
    phase = "reset state";
    do_reset(3);
    monitor_en = 1'b1;
    expect_all_clear("after initial reset");
    expect_read(OFF_LEDR, 32'h0000_0000, "LEDR not zero after reset");
    expect_read(OFF_HEX0, 32'h0000_0000, "HEX0 not zero after reset");
    expect_read(OFF_HEX5, 32'h0000_0000, "HEX5 not zero after reset");

    // 2. LEDR write and readback, including the mask above bit 9
    phase = "ledr";
    bus_write(OFF_LEDR, 32'h0000_03FF);
    expect_read(OFF_LEDR, 32'h0000_03FF, "LEDR all ones readback");
    expect_ledr_out(10'h3FF, "LEDR output did not follow the register");
    bus_write(OFF_LEDR, 32'h0000_0000);
    expect_read(OFF_LEDR, 32'h0000_0000, "LEDR clear readback");
    expect_ledr_out(10'h000, "LEDR output did not clear");
    bus_write(OFF_LEDR, 32'h0000_0155);
    expect_read(OFF_LEDR, 32'h0000_0155, "LEDR pattern readback");
    expect_ledr_out(10'h155, "LEDR output wrong for the pattern");
    bus_write(OFF_LEDR, 32'hFFFF_FFFF);
    expect_read(OFF_LEDR, 32'h0000_03FF, "LEDR did not mask bits above 9");
    expect_ledr_out(10'h3FF, "LEDR output wrong after a masked write");

    // 3. Every HEX register: write, masked write, readback, output, isolation
    phase = "hex";
    do_reset(2);
    for (int i = 0; i < HEX_COUNT; i++) begin
      bus_write(hex_off(i), 32'h0000_007F);
      expect_read(hex_off(i), 32'h0000_007F, "HEX all segments readback");
      expect_hex_out(i, 7'h7F, "HEX output did not follow the register");
      bus_write(hex_off(i), 32'hFFFF_FFFF);
      expect_read(hex_off(i), 32'h0000_007F, "HEX did not mask bits above 6");
      // a per-register pattern so a decode swap between HEX0..HEX5 shows up
      bus_write(hex_off(i), 32'h0000_0041 + i);
      expect_read(hex_off(i), 32'h0000_0041 + i, "HEX pattern readback");
      expect_hex_out(i, 7'h41 + i, "HEX output wrong for the pattern");
    end
    // all six patterns survived: the writes did not alias onto each other
    for (int i = 0; i < HEX_COUNT; i++) begin
      expect_read(hex_off(i), 32'h0000_0041 + i, "HEX disturbed by a write elsewhere");
      expect_hex_out(i, 7'h41 + i, "HEX output disturbed by a write elsewhere");
    end
    expect_read(OFF_LEDR, 32'h0000_0000, "LEDR disturbed by the HEX writes");

    // 4. SW and KEY reflect the inputs and zero-extend
    phase = "sw and key";
    sw_in  = 10'h3FF;
    key_in = 4'hF;
    expect_read(OFF_SW, 32'h0000_03FF, "SW did not reflect all switches up");
    expect_read(OFF_KEY, 32'h0000_000F, "KEY did not reflect all keys pressed");
    sw_in  = 10'h2AA;
    key_in = 4'h5;
    expect_read(OFF_SW, 32'h0000_02AA, "SW did not reflect the pattern");
    expect_read(OFF_KEY, 32'h0000_0005, "KEY did not reflect the pattern");
    sw_in  = 10'h001;
    key_in = 4'h8;
    expect_read(OFF_SW, 32'h0000_0001, "SW did not reflect one switch");
    expect_read(OFF_KEY, 32'h0000_0008, "KEY did not reflect one key");

    // 5. SW and KEY are read only: writes to them change nothing
    phase = "read only regs";
    bus_write(OFF_SW, 32'hFFFF_FFFF);
    bus_write(OFF_KEY, 32'hFFFF_FFFF);
    expect_read(OFF_SW, 32'h0000_0001, "a write to SW changed what it reads");
    expect_read(OFF_KEY, 32'h0000_0008, "a write to KEY changed what it reads");
    sw_in  = 10'h000;
    key_in = 4'h0;
    expect_read(OFF_SW, 32'h0000_0000, "SW stuck after a write attempt");
    expect_read(OFF_KEY, 32'h0000_0000, "KEY stuck after a write attempt");

    // 6. Unmapped offsets read zero and swallow writes
    phase = "unmapped";
    bus_write(OFF_LEDR, 32'h0000_02AA);
    bus_write(OFF_HEX2, 32'h0000_0033);
    bus_write(16'h000C, 32'hFFFF_FFFF);
    bus_write(16'h0028, 32'hFFFF_FFFF);
    bus_write(16'h002C, 32'hFFFF_FFFF);
    bus_write(16'h0034, 32'hFFFF_FFFF);
    bus_write(16'h0002, 32'hFFFF_FFFF);
    bus_write(16'h8000, 32'hFFFF_FFFF);
    bus_write(16'hFFFC, 32'hFFFF_FFFF);
    expect_read(16'h000C, 32'h0000_0000, "unmapped offset 0x000C did not read zero");
    expect_read(16'h0028, 32'h0000_0000, "unmapped offset 0x0028 did not read zero");
    expect_read(16'h002C, 32'h0000_0000, "unmapped offset 0x002C did not read zero");
    expect_read(16'h0034, 32'h0000_0000, "unmapped offset 0x0034 did not read zero");
    expect_read(16'h0002, 32'h0000_0000, "unaligned offset 0x0002 did not read zero");
    expect_read(16'h8000, 32'h0000_0000, "unmapped offset 0x8000 did not read zero");
    expect_read(16'hFFFC, 32'h0000_0000, "unmapped offset 0xFFFC did not read zero");
    expect_read(OFF_LEDR, 32'h0000_02AA, "LEDR changed by an unmapped write");
    expect_read(OFF_HEX2, 32'h0000_0033, "HEX2 changed by an unmapped write");
    expect_ledr_out(10'h2AA, "ledr_out changed by an unmapped write");
    expect_hex_out(2, 7'h33, "hex2_out changed by an unmapped write");

    // 7. re low. The dut gates rdata with re exactly like the reference, so
    //    both read zero and the cycle by cycle compare stays exact rather than
    //    being skipped as a don't-care.
    phase = "re low";
    bus_op(OFF_LEDR, 32'h0000_0000, 1'b0, 1'b0, got);
    checks = checks + 1;
    if (got !== 32'h0000_0000) begin
      $display("FAIL: rdata was 0x%08h with re low at time %0t", got, $time);
      $fatal(1);
    end
    expect_read(OFF_LEDR, 32'h0000_02AA, "LEDR lost after an idle cycle");

    // 8. we and re together: the read sees the value before the write commits
    phase = "we and re together";
    bus_op(OFF_LEDR, 32'h0000_0155, 1'b1, 1'b1, got);
    checks = checks + 1;
    if (got !== 32'h0000_02AA) begin
      $display("FAIL: simultaneous read returned 0x%08h, expected the old 0x000002AA at time %0t",
               got, $time);
      $fatal(1);
    end
    expect_read(OFF_LEDR, 32'h0000_0155, "simultaneous write did not commit");

    // 9. CYCLE counts every clock from zero and ignores writes
    phase = "cycle counter";
    do_reset(2);
    for (int i = 0; i < 12; i++) begin
      expect_read(OFF_CYCLE, i, "CYCLE did not increment by one per clock");
    end
    // the read loop consumed 12 clocks, so the counter now reads 12
    bus_write(OFF_CYCLE, 32'hDEAD_BEEF);
    expect_read(OFF_CYCLE, 32'd13, "a write to CYCLE disturbed the count");
    idle_cycle();
    expect_read(OFF_CYCLE, 32'd15, "CYCLE stopped counting during idle cycles");

    // 10. Reset mid test clears LEDR and HEX and restarts the counter
    phase = "mid test reset";
    bus_write(OFF_LEDR, 32'h0000_03FF);
    for (int i = 0; i < HEX_COUNT; i++) begin
      bus_write(hex_off(i), 32'h0000_007F);
    end
    expect_ledr_out(10'h3FF, "LEDR not loaded before the mid test reset");
    expect_hex_out(3, 7'h7F, "HEX3 not loaded before the mid test reset");
    if (cycle_dut === '0) begin
      $display("FAIL: counter was still zero going into the mid test reset at time %0t", $time);
      $fatal(1);
    end
    checks = checks + 1;
    do_reset(2);
    expect_all_clear("after the mid test reset");
    expect_read(OFF_LEDR, 32'h0000_0000, "LEDR survived the mid test reset");
    for (int i = 0; i < HEX_COUNT; i++) begin
      expect_read(hex_off(i), 32'h0000_0000, "HEX survived the mid test reset");
    end
    // reads above burned 7 clocks, so the restarted counter is at 7
    expect_read(OFF_CYCLE, 32'd7, "CYCLE did not restart from zero after the mid test reset");

    // 11. Upper address bits are ignored: external logic owns that decode. The
    //     reference checks the full address, so it is not cross checked here.
    phase = "upper address bits";
    cross_check = 1'b0;
    bus_raw(32'h1234_0000, 32'h0000_02AA, 1'b1, 1'b0, got);
    expect_ledr_out(10'h2AA, "a write with foreign upper address bits was dropped");
    bus_raw(32'h0000_0000, 32'h0000_0000, 1'b0, 1'b1, got);
    checks = checks + 1;
    if (got !== 32'h0000_02AA) begin
      $display("FAIL: read with zero upper address bits gave 0x%08h at time %0t", got, $time);
      $fatal(1);
    end
    bus_raw(32'hDEAD_0010, 32'h0000_007F, 1'b1, 1'b0, got);
    expect_hex_out(0, 7'h7F, "a HEX0 write with foreign upper address bits was dropped");
    // put both models back in step before resuming the cross check
    do_reset(2);
    cross_check = 1'b1;

    // 12. UART_DATA and UART_STATUS. busy answers 1 in the cycle of the write
    //     that starts a frame and stays up for exactly FRAME_BITS*BAUD_DIV
    //     clocks of shifting after the edge that took that write.
    phase = "uart";
    expect_read(OFF_USTAT, 32'h0000_0000, "UART_STATUS was not zero at reset");
    expect_read(OFF_UDATA, 32'h0000_0000, "UART_DATA did not read zero");
    // read with wdata driven, so a write only register that leaked the bus data
    // back would show up
    bus_op(OFF_UDATA, 32'hFFFF_FFFF, 1'b0, 1'b1, got);
    checks = checks + 1;
    if (got !== 32'h0000_0000) begin
      $display("FAIL: UART_DATA read returned 0x%08h at time %0t", got, $time);
      $fatal(1);
    end
    expect_uart(1'b1, 1'b0, "uart did not idle high before the first frame");

    // 0x4B is not a palindrome, so a transmitter shifting MSB first fails here
    uart_write(32'h0000_004B, "busy did not answer in the cycle of the write itself");
    frame_t0 = cycle_dut;
    expect_read(OFF_USTAT, 32'h0000_0001, "UART_STATUS did not read busy the cycle after a write");
    // dropped: the transmitter is mid frame, so 0x5A never reaches the line
    bus_write(OFF_UDATA, 32'h0000_005A);
    expect_read(OFF_UDATA, 32'h0000_0000, "UART_DATA did not read zero while busy");
    decode_frame(frame_t0, frame_dut, frame_ref);
    expect_frame(frame_dut, frame_ref, 8'h4B, "decoded frame did not match the byte written");

    // the last sample sat in the stop bit, so busy is still up here
    expect_uart(1'b1, 1'b1, "uart dropped busy before the stop bit ended");
    wait_cycle_count(frame_t0 + (FRAME_BITS * BAUD_DIV) - 1);
    expect_uart(1'b1, 1'b1, "uart dropped busy one cycle early");
    wait_cycle_count(frame_t0 + (FRAME_BITS * BAUD_DIV));
    expect_uart(1'b1, 1'b0, "uart did not drop busy after exactly one frame");
    // the second write really was dropped: no frame followed the first
    expect_read(OFF_USTAT, 32'h0000_0000, "UART_STATUS stayed busy after the frame");
    expect_uart(1'b1, 1'b0, "uart started a second frame from a write made while busy");

    // a fresh write after the frame is accepted normally
    bus_write(OFF_UDATA, 32'hFFFF_FF1C);
    frame_t0 = cycle_dut;
    decode_frame(frame_t0, frame_dut, frame_ref);
    expect_frame(frame_dut, frame_ref, 8'h1C, "UART_DATA did not take only bits 7:0");
    wait_cycle_count(frame_t0 + (FRAME_BITS * BAUD_DIV));
    expect_read(OFF_USTAT, 32'h0000_0000, "UART_STATUS stayed busy after the second frame");

    // 13. The offsets either side of the uart pair are still unmapped
    phase = "uart neighbours";
    bus_write(16'h003C, 32'hFFFF_FFFF);
    bus_write(16'h0048, 32'hFFFF_FFFF);
    expect_read(16'h003C, 32'h0000_0000, "unmapped offset 0x003C did not read zero");
    expect_read(16'h0048, 32'h0000_0000, "unmapped offset 0x0048 did not read zero");
    expect_uart(1'b1, 1'b0, "a write to a uart neighbour started a frame");

    // 14. Reset mid frame parks the line high and clears busy on both models.
    //     0x00 keeps tx low through the start and data bits, so the reset lands
    //     while the line is being driven low.
    phase = "uart reset";
    bus_write(OFF_UDATA, 32'h0000_0000);
    frame_t0 = cycle_dut;
    wait_cycle_count(frame_t0 + (2 * BAUD_DIV));
    expect_uart(1'b0, 1'b1, "uart was not mid frame with the line low before the reset");
    do_reset(2);
    expect_uart(1'b1, 1'b0, "a reset mid frame did not park tx high with busy clear");
    expect_read(OFF_USTAT, 32'h0000_0000, "UART_STATUS was not zero after a reset mid frame");

    // 15. Randomized mixed traffic over mapped and unmapped offsets, with
    //     random switch and key inputs and the occasional reset pulse
    phase = "random loop";
    for (int i = 0; i < RAND_ITERS; i++) begin
      rand_iter = i;
      rnd_a     = $random(rand_seed);
      rnd_d     = $random(rand_seed);
      rnd_c     = $random(rand_seed);

      // sel 10 and 11 pick the uart pair, so the random traffic starts frames,
      // writes into busy frames and resets mid frame as well
      sel = rnd_c[3:0];
      if (sel < 4'd12) begin
        r_off = {16'h0000, mapped_off(sel)};
      end else begin
        r_off = {16'h0000, rnd_a[15:0]};
      end

      addr   = MMIO_BASE | r_off;
      wdata  = rnd_d;
      we     = rnd_c[4];
      re     = rnd_c[5];
      sw_in  = rnd_a[25:16];
      key_in = rnd_a[29:26];
      rst_n  = (rnd_c[15:8] == 8'h00) ? 1'b0 : 1'b1;
      #1;
      compare_models();
      @(posedge clk);
      #1;
    end

    we    = 1'b0;
    re    = 1'b0;
    rst_n = 1'b1;
    phase = "wrap up";
    @(posedge clk);
    #1;

    if (checks == 0) begin
      $display("FAIL: no checks executed");
      $fatal(1);
    end

    $display("PASS: mmio");
    $finish;
  end

endmodule
