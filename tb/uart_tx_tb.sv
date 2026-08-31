// uart_tx_tb: self-checking testbench for the 8N1 serial transmitter. Checks tx
// cycle by cycle against the expected frame, decodes it again with a mid bit
// sampling receiver model, and times busy, back to back frames and reset.

`timescale 1ns / 1ps

module uart_tx_tb;

  localparam int DATA_WIDTH = 8;
  localparam int FRAME_BITS = DATA_WIDTH + 2;
  localparam int CLK_PERIOD = 10;

  // small divider for the bulk of the tests, plus one instance left at the
  // default so the shipped BAUD_DIV is exercised too
  localparam int FAST_DIV = 8;
  localparam int DEF_DIV  = 434;

  localparam int RAND_BYTES = 4;

  logic clk;
  logic rst_n;

  logic [DATA_WIDTH-1:0] data_fast;
  logic                  start_fast;
  logic                  tx_fast;
  logic                  busy_fast;

  logic [DATA_WIDTH-1:0] data_def;
  logic                  start_def;
  logic                  tx_def;
  logic                  busy_def;

  // mon_sel picks which transmitter the tasks drive and watch
  logic mon_sel;
  logic tx_mon;
  logic busy_mon;

  string       phase;
  int unsigned checks;

  integer rand_seed = 32'd20260818;

  uart_tx #(
    .DATA_WIDTH (DATA_WIDTH),
    .BAUD_DIV   (FAST_DIV)
  ) dut_fast (
    .clk   (clk),
    .rst_n (rst_n),
    .data  (data_fast),
    .start (start_fast),
    .tx    (tx_fast),
    .busy  (busy_fast)
  );

  // no overrides: proves DATA_WIDTH 8 and BAUD_DIV 434 as declared
  uart_tx dut_def (
    .clk   (clk),
    .rst_n (rst_n),
    .data  (data_def),
    .start (start_def),
    .tx    (tx_def),
    .busy  (busy_def)
  );

  assign tx_mon   = mon_sel ? tx_def   : tx_fast;
  assign busy_mon = mon_sel ? busy_def : busy_fast;

  initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD / 2) clk = ~clk;
  end

  initial begin
    #500000;
    $display("FAIL: timeout, testbench did not finish");
    $fatal(1);
  end

  task automatic fail_now(input string what);
    $display("FAIL: %s during %s at time %0t", what, phase, $time);
    $fatal(1);
  endtask

  // Every task enters and leaves one nanosecond after a posedge, where the
  // registered outputs of the current cycle are settled.
  task automatic step();
    @(posedge clk);
    #1;
  endtask

  task automatic drive_start(input logic [DATA_WIDTH-1:0] d, input logic s);
    if (mon_sel) begin
      data_def  = d;
      start_def = s;
    end else begin
      data_fast  = d;
      start_fast = s;
    end
  endtask

  task automatic do_reset(input int cycles);
    rst_n      = 1'b0;
    start_fast = 1'b0;
    start_def  = 1'b0;
    repeat (cycles) @(posedge clk);
    #1;
    rst_n = 1'b1;
  endtask

  task automatic expect_idle(input int cycles, input string label);
    for (int i = 0; i < cycles; i++) begin
      checks = checks + 1;
      if (tx_fast !== 1'b1 || tx_def !== 1'b1) begin
        $display("idle check %s: tx_fast %0b, tx_def %0b", label, tx_fast, tx_def);
        fail_now("tx did not idle high");
      end
      checks = checks + 1;
      if (busy_fast !== 1'b0 || busy_def !== 1'b0) begin
        $display("idle check %s: busy_fast %0b, busy_def %0b", label, busy_fast, busy_def);
        fail_now("busy was high while idle");
      end
      step();
    end
  endtask

  // One start pulse. busy must already answer in this same cycle, which is what
  // the mmio status bit relies on.
  task automatic pulse_start(input logic [DATA_WIDTH-1:0] d);
    drive_start(d, 1'b1);
    #1;
    checks = checks + 1;
    if (busy_mon !== 1'b1) begin
      fail_now("busy did not assert on the cycle the start was accepted");
    end
    step();
    drive_start(d, 1'b0);
  endtask

  // Watches one whole frame from its first cycle. Checks tx against the exact
  // expected waveform every cycle, so every transition has to land on a bit
  // boundary, samples the middle of each bit like a receiver would, and holds
  // busy to the frame. intrude_at, when not negative, pulses start that many
  // cycles into the frame to prove a mid frame start is ignored.
  task automatic watch_frame(input logic [DATA_WIDTH-1:0] want, input int div,
                             input int intrude_at, input logic [DATA_WIDTH-1:0] intrude_byte);
    logic [FRAME_BITS-1:0] frame;
    logic [DATA_WIDTH-1:0] got;
    int                    total;
    int                    idx;

    // start bit low, then the byte LSB first, then the stop bit high
    frame = {1'b1, want, 1'b0};
    got   = '0;
    total = FRAME_BITS * div;

    for (int c = 0; c < total; c++) begin
      idx = c / div;
      checks = checks + 1;
      if (tx_mon !== frame[idx]) begin
        $display("tx was %0b at cycle %0d of the frame, bit %0d should be %0b", tx_mon, c, idx,
                 frame[idx]);
        fail_now("tx did not match the expected frame waveform");
      end
      checks = checks + 1;
      if (busy_mon !== 1'b1) begin
        fail_now("busy dropped inside the frame");
      end
      // mid bit sample: what a receiver locked to this baud rate would read
      if ((c % div) == (div / 2)) begin
        if (idx == 0) begin
          checks = checks + 1;
          if (tx_mon !== 1'b0) fail_now("start bit was not low at its mid point");
        end else if (idx == FRAME_BITS - 1) begin
          checks = checks + 1;
          if (tx_mon !== 1'b1) fail_now("stop bit was not high at its mid point");
        end else begin
          got[idx-1] = tx_mon;
        end
      end
      if (c == intrude_at) begin
        drive_start(intrude_byte, 1'b1);
      end else begin
        drive_start(want, 1'b0);
      end
      step();
    end

    checks = checks + 1;
    if (got !== want) begin
      $display("decoded 0x%02h, expected 0x%02h", got, want);
      fail_now("the mid bit decode rebuilt the wrong byte");
    end
    // exactly FRAME_BITS bit periods after tx fell the line is idle again
    checks = checks + 1;
    if (tx_mon !== 1'b1) fail_now("tx was not back to idle high at the frame end");
    checks = checks + 1;
    if (busy_mon !== 1'b0) fail_now("busy did not drop exactly at the frame end");
  endtask

  // Full frame: idle before it, start taken, tx down the next cycle, waveform,
  // decode and busy all checked by watch_frame.
  task automatic send_frame(input logic [DATA_WIDTH-1:0] d, input int div, input int intrude_at,
                            input logic [DATA_WIDTH-1:0] intrude_byte);
    checks = checks + 1;
    if (busy_mon !== 1'b0) fail_now("busy was still high before a new frame");
    checks = checks + 1;
    if (tx_mon !== 1'b1) fail_now("tx was not idle high before a new frame");
    pulse_start(d);
    checks = checks + 1;
    if (tx_mon !== 1'b0) fail_now("tx did not fall the cycle after the start pulse");
    watch_frame(d, div, intrude_at, intrude_byte);
  endtask

  task automatic send_byte(input logic [DATA_WIDTH-1:0] d, input int div);
    send_frame(d, div, -1, '0);
  endtask

  // Reference receiver that owns no knowledge of when start was pulsed: it
  // hunts the falling edge, waits half a bit period and then samples once per
  // bit period, which is how adjacent frames are told apart.
  task automatic decode_next(input int div, output logic [DATA_WIDTH-1:0] got);
    got = '0;
    while (tx_mon !== 1'b0) begin
      step();
    end
    repeat (div / 2) step();
    checks = checks + 1;
    if (tx_mon !== 1'b0) fail_now("decoder did not find a low start bit");
    for (int i = 0; i < DATA_WIDTH; i++) begin
      repeat (div) step();
      got[i] = tx_mon;
    end
    repeat (div) step();
    checks = checks + 1;
    if (tx_mon !== 1'b1) fail_now("decoder did not find a high stop bit");
  endtask

  task automatic wait_idle();
    while (busy_mon !== 1'b0) begin
      step();
    end
  endtask

  task automatic expect_byte(input logic [DATA_WIDTH-1:0] got, input logic [DATA_WIDTH-1:0] want,
                             input string label);
    checks = checks + 1;
    if (got !== want) begin
      $display("%s: decoded 0x%02h, expected 0x%02h", label, got, want);
      fail_now("decoded byte mismatch");
    end
  endtask

  logic [DATA_WIDTH-1:0] rnd;
  logic [DATA_WIDTH-1:0] got_a;
  logic [DATA_WIDTH-1:0] got_b;
  int                    cnt;

  initial begin
    $dumpfile("sim/build/uart_tx_tb.vcd");
    $dumpvars(0, uart_tx_tb);

    checks     = 0;
    phase      = "startup";
    mon_sel    = 1'b0;
    data_fast  = '0;
    start_fast = 1'b0;
    data_def   = '0;
    start_def  = 1'b0;
    rst_n      = 1'b0;

    // 1. Reset leaves both transmitters idle with the line high
    phase = "reset state";
    do_reset(3);
    expect_idle(20, "after reset");

    // 2. Alternating patterns prove the LSB first bit order
    phase = "alternating patterns";
    send_byte(8'h55, FAST_DIV);
    expect_idle(4, "between frames");
    send_byte(8'hAA, FAST_DIV);
    expect_idle(4, "between frames");

    // 3. All zeros and all ones: a stuck line would pass one and fail the other
    phase = "stuck line";
    send_byte(8'h00, FAST_DIV);
    expect_idle(4, "between frames");
    send_byte(8'hFF, FAST_DIV);
    expect_idle(4, "between frames");

    // 4. A handful of random bytes
    phase = "random bytes";
    for (int i = 0; i < RAND_BYTES; i++) begin
      rnd = $random(rand_seed);
      send_byte(rnd, FAST_DIV);
      expect_idle(3, "between random frames");
    end

    // 5. A start pulse mid frame is dropped wherever it lands, in the start bit,
    //    among the data bits or in the stop bit: the byte on the wire and the
    //    frame length are both unchanged, and nothing is queued behind it
    phase = "mid frame start ignored";
    send_frame(8'h3C, FAST_DIV, 1, 8'hF0);
    expect_idle(20, "after a start bit intrusion");
    send_frame(8'h3C, FAST_DIV, 3 * FAST_DIV + 2, 8'hF0);
    expect_idle(20, "after a data bit intrusion");
    send_frame(8'h3C, FAST_DIV, 9 * FAST_DIV + 3, 8'hF0);
    expect_idle(20, "after a stop bit intrusion");

    // 6. Back to back frames, the second started the cycle busy drops
    phase = "back to back";
    send_byte(8'h12, FAST_DIV);
    send_byte(8'h34, FAST_DIV);
    expect_idle(4, "after back to back frames");

    // 7. Two identical bytes with no gap, told apart by start edge detection
    //    alone in the reference receiver
    phase = "repeated byte";
    fork
      begin
        wait_idle();
        pulse_start(8'h00);
        wait_idle();
        pulse_start(8'h00);
        wait_idle();
      end
      begin
        decode_next(FAST_DIV, got_a);
        decode_next(FAST_DIV, got_b);
      end
    join
    expect_byte(got_a, 8'h00, "first repeated frame");
    expect_byte(got_b, 8'h00, "second repeated frame");
    wait_idle();
    expect_idle(4, "after the repeated frames");

    // 8. Reset mid frame aborts it, the line returns high and a fresh frame
    //    still works afterwards
    phase = "reset mid frame";
    pulse_start(8'h6D);
    repeat (3 * FAST_DIV) step();
    checks = checks + 1;
    if (busy_mon !== 1'b1) fail_now("transmitter was not busy going into the mid frame reset");
    do_reset(2);
    expect_idle(6, "after the mid frame reset");
    send_byte(8'h6D, FAST_DIV);
    expect_idle(4, "after the post reset frame");

    // 9. One frame on the default 434 divider, which is the 115200 baud setting
    phase = "default divider";
    mon_sel = 1'b1;
    send_byte(8'h5A, DEF_DIV);
    expect_idle(8, "after the default divider frame");
    mon_sel = 1'b0;

    cnt = checks;
    if (cnt == 0) begin
      $display("FAIL: no checks executed");
      $fatal(1);
    end

    $display("PASS: uart_tx");
    $finish;
  end

endmodule
