// demo_tb: self checking testbench for the seven demo programs in programs/.
// Wraps cpu_top with imem, dmem and the behavioral mmio model, drives switch
// and key stimulus, and checks the observable mmio behavior of every demo,
// including decoding the serial line for the uart demo.

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

  // The transmitter model runs at a small baud divider here so whole 8N1
  // frames fit inside a demo length run: 16 clocks per bit and 10 bits per
  // frame means one character costs 160 cycles instead of the 4340 the
  // hardware BAUD_DIV of 434 would cost. Only uart_hello cares.
  localparam int UART_DIV = 16;

  // room for far more received bytes than the uart demo sends in its budget
  localparam int MAX_RX = 512;

  // The banner uart_hello prints once at startup, and the count line prefix.
  // Neither carries its line ending: \r is not a portable escape across
  // simulators, so the two ending bytes are spelled out below and matched by
  // value instead.
  localparam string UART_BANNER = "rv32-core says hello over uart";
  localparam string UART_COUNT  = "count ";

  localparam logic [7:0] ASCII_CR = 8'h0D;
  localparam logic [7:0] ASCII_LF = 8'h0A;

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
  // the serial line the receiver below decodes, plus the model's busy flag,
  // which nothing checks here but which is worth having in the waveform
  logic                  uart_line;
  logic                  uart_busy;

  // received byte log, filled by the serial receiver process further down
  logic                  uart_capture;
  logic [7:0]            uart_rx[MAX_RX];
  int                    uart_rx_n;

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
    .DATA_WIDTH (DATA_WIDTH),
    .BAUD_DIV   (UART_DIV)
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
    .uart_tx_o (uart_line),
    .uart_busy (uart_busy),
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
    run_active   = 1'b0;
    cyc          = 0;
    ledr_n       = 0;
    hex_n        = 0;
    uart_capture = 1'b0;
    uart_rx_n    = 0;
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

  // Serial receiver, the same shape as the reference decoder in
  // tb/uart_tx_tb.sv: it owns no knowledge of when the CPU wrote a byte, it
  // hunts the falling start edge, waits half a bit period and then samples once
  // per bit period. Bytes land in uart_rx while uart_capture is set.
  task automatic uart_step();
    @(posedge clk);
    #1;
  endtask

  initial begin
    logic [7:0] rx_byte;

    forever begin
      uart_step();
      if (uart_capture && (uart_line === 1'b0)) begin
        repeat (UART_DIV / 2) uart_step();
        rx_byte = '0;
        for (int i = 0; i < 8; i++) begin
          repeat (UART_DIV) uart_step();
          rx_byte[i] = uart_line;
        end
        repeat (UART_DIV) uart_step();
        // a frame without a high stop bit is framing garbage, not a byte
        if ((uart_line === 1'b1) && (uart_rx_n < MAX_RX)) begin
          uart_rx[uart_rx_n] = rx_byte;
          uart_rx_n          = uart_rx_n + 1;
        end
      end
    end
  end

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

  // does the received byte stream carry s starting at pos
  function automatic logic rx_match(input int pos, input string s);
    if (pos < 0) return 1'b0;
    if ((pos + s.len()) > uart_rx_n) return 1'b0;
    for (int i = 0; i < s.len(); i++)
      if (uart_rx[pos+i] !== s[i]) return 1'b0;
    return 1'b1;
  endfunction

  function automatic int rx_count(input string s);
    int n;
    n = 0;
    for (int p = 0; p < uart_rx_n; p++) if (rx_match(p, s)) n = n + 1;
    return n;
  endfunction

  // first position at or after from where s appears, -1 if it never does
  function automatic int rx_find(input string s, input int from);
    for (int p = from; p < uart_rx_n; p++) if (rx_match(p, s)) return p;
    return -1;
  endfunction

  // is there a carriage return line feed pair at pos
  function automatic logic rx_crlf_at(input int pos);
    if ((pos < 0) || ((pos + 2) > uart_rx_n)) return 1'b0;
    return (uart_rx[pos] === ASCII_CR) && (uart_rx[pos+1] === ASCII_LF);
  endfunction

  function automatic int rx_crlf_count();
    int n;
    n = 0;
    for (int p = 0; p < uart_rx_n; p++) if (rx_crlf_at(p)) n = n + 1;
    return n;
  endfunction

  // value of one lowercase hex digit byte, -1 when it is not one
  function automatic int rx_nibble(input logic [7:0] c);
    if ((c >= "0") && (c <= "9")) return c - "0";
    if ((c >= "a") && (c <= "f")) return (c - "a") + 10;
    return -1;
  endfunction

  // the eight hex digits at pos as a value, -1 if any of them is not a digit
  function automatic int rx_hex8(input int pos);
    int v;
    int d;
    v = 0;
    if ((pos < 0) || ((pos + 8) > uart_rx_n)) return -1;
    for (int i = 0; i < 8; i++) begin
      d = rx_nibble(uart_rx[pos+i]);
      if (d < 0) return -1;
      v = (v << 4) | d;
    end
    return v;
  endfunction

  // the received bytes as printable text, control codes spelled out
  function automatic string rx_text();
    string s;
    s = "";
    for (int i = 0; i < uart_rx_n; i++) begin
      if (uart_rx[i] == ASCII_CR) s = {s, "<cr>"};
      else if (uart_rx[i] == ASCII_LF) s = {s, "<lf>"};
      else s = {s, string'(uart_rx[i])};
    end
    return s;
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
    uart_rx_n  = 0;
    step_cycles(2);
    rst_n      = 1'b1;
    run_active = 1'b1;
    $display("demo %s: start", name);
  endtask

  // led_blink: one lit bit walks up to LEDR[9] and back down, one write per
  // delay step, 18 writes per full bounce. Step spacing history: 103 cycles on
  // the load-stall single-cycle core, 201 once the pipeline made every taken
  // branch in delay_loop cost a flush, and 207..211 now that the delay is
  // delay_cycles(BLINK_DELAY) with BLINK_DELAY of 192 CYCLE counts. The extra
  // cycles beyond 192 are the LEDR write and the bounce logic wrapped around
  // the delay, and the four cycle spread is the granularity of the last CYCLE
  // poll. 20 writes now land at cycle 3977, inside the same 5000 cycle budget.
  task automatic check_led_blink();
    int phase;
    int pos;

    start_demo("led_blink");
    while ((ledr_n < 20) && (cyc < 5000)) step_cycles(1);
    if (ledr_n < 20)
      fail("LEDR writes in 5000 cycles", $sformatf("%0d", ledr_n), "20");

    for (int i = 0; i < 20; i++) begin
      phase = i % 18;
      pos   = (phase < 10) ? phase : (18 - phase);
      expect_hex($sformatf("LEDR write %0d", i), ledr_val[i], 32'd1 << pos);
    end
    expect_range("first LEDR write cycle", ledr_cyc[0], 5, 60);
    for (int i = 1; i < 20; i++)
      // was 180..230 against a measured 201; now 195..225 against 207..211
      expect_range($sformatf("LEDR write %0d spacing", i),
                   ledr_cyc[i] - ledr_cyc[i-1], 195, 225);
  endtask

  // counter: HEX4 and HEX5 go dark once, then a four write burst per count
  // with the BCD digits carried by hand. Burst spacing history: 73 cycles
  // single-cycle, 82 once the load stall landed, 128 on the pipeline, and
  // 135..141 now that the delay is delay_cycles(COUNTER_DELAY) with
  // COUNTER_DELAY of 96 CYCLE counts. The delay itself no longer reloads a
  // counter from memory, so what is left on top of the 96 is the four display
  // writes and the BCD carry. 11 full counts land at cycle 1419, comfortably
  // inside the same 2500 cycle budget.
  task automatic check_counter();
    logic [6:0] exp0[11];

    exp0 = '{7'h3F, 7'h06, 7'h5B, 7'h4F, 7'h66, 7'h6D, 7'h7D, 7'h07,
             7'h7F, 7'h6F, 7'h3F};

    start_demo("counter");
    // HEX3 is written last in each burst, so 11 of those means 11 full counts
    while ((hex_count(3) < 11) && (cyc < 2500)) step_cycles(1);
    if (hex_count(3) < 11)
      fail("count bursts in 2500 cycles", $sformatf("%0d", hex_count(3)), "11");

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

    // was 100..160 against a measured 128; now 125..155 against 135..141
    for (int i = 1; i < 11; i++)
      expect_range($sformatf("HEX0 update %0d spacing", i),
                   hex_cyc[hex_at(0, i)] - hex_cyc[hex_at(0, i-1)], 125, 155);
    expect_hex("LEDR untouched", mmio_ledr, 10'h000);
  endtask

  // switch_mirror: SW lands on LEDR and its three hex digits on HEX0..HEX2.
  // Refresh history: 34 cycles single-cycle, 38 with the load stall, 51 on the
  // pipeline, and 57 now with delay_cycles(MIRROR_DELAY) at MIRROR_DELAY of 32
  // CYCLE counts. Both switch settings are picked up 57 cycles after they are
  // driven, so the 600 cycle budget keeps an order of magnitude to spare.
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
  // pulsing 0x001 then 0x000 at every restart of the sequence. Sequence length
  // history: about 2700 cycles single-cycle, 3903 on the pipeline, and 4162
  // now with delay_cycles(FIB_DELAY) at FIB_DELAY of 48 CYCLE counts. The
  // first restart is at cycle 44 and the second at 4206, and a third would not
  // arrive until about 8400, so exactly two restarts fall inside the 6000
  // cycle run and 54 HEX0 terms are logged against the 8 the check reads.
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
    // was 3400..4400 against a measured 3903; now 3900..4450 against 4162
    expect_range("restart period", second_pulse - first_pulse, 3900, 4450);
  endtask

  // memtest: walking ones then an address pattern over the dmem window at
  // 0x1800, LEDR reporting each phase and then the pass code. The phase 2 and
  // pass windows have been re-measured twice now. Load stall: phase 2 moved
  // from cycle 1605 to 1861 and the pass code from 1680 to 1944. Pipeline:
  // phase 2 is at 2426 and the pass code at 2523. Loads themselves got
  // cheaper here, but this demo is a tight loop and every taken branch back to
  // the top costs two cycles, which more than eats the gain. The windows below
  // are centered on the new numbers and the run is 3000 cycles so the final
  // "still passing" check happens after the pass code lands.
  // The delay_loop to delay_cycles switch left this demo alone: memtest has no
  // delay at all, so it never called the helper, its hex image came out byte
  // identical, and phase 2 and the pass code re-measure at exactly 2426 and
  // 2523. The windows below are unchanged for that reason.
  task automatic check_memtest();
    start_demo("memtest");
    while (cyc < 3000) step_cycles(1);

    if (ledr_n != 3) fail("LEDR write count", $sformatf("%0d", ledr_n), "3");
    expect_hex("LEDR phase 1 code", ledr_val[0], 10'h001);
    expect_range("LEDR phase 1 cycle", ledr_cyc[0], 5, 60);
    expect_hex("LEDR phase 2 code", ledr_val[1], 10'h002);
    expect_range("LEDR phase 2 cycle", ledr_cyc[1], 2100, 2800);
    expect_hex("LEDR pass code", ledr_val[2], 10'h3FF);
    expect_range("LEDR pass cycle", ledr_cyc[2], 2200, 2900);
    expect_hex("LEDR still passing at 3000", mmio_ledr, 10'h3FF);

    // MEMTEST_WORDS is 8 in the simulation build, shown as two hex digits
    expect_hex("HEX0 word count low", mmio_hex[0], 7'h7F);
    expect_hex("HEX1 word count high", mmio_hex[1], 7'h3F);

    // the window must be left holding the address pattern, not the poison
    for (int k = 0; k < MEMTEST_WORDS; k++)
      expect_hex($sformatf("dmem[0x%08h]", MEMTEST_BASE + 4*k),
                 u_dmem.mem[MEMTEST_INDEX + k], MEMTEST_BASE + 4*k);
  endtask

  // reaction: run once with no key press so the poll times out, then again
  // pressing as soon as the go signal appears. The poll deadline is read off
  // the CYCLE register now, not counted in poll iterations, so the timeout is
  // an exact cycle window instead of something that moves with the core.
  // Measured on the pipeline: the go signal at cycle 164 and the miss LED at
  // 2177, a span of 2013 against a sim REACT_TIMEOUT of 2000 cycles. With the
  // pre-go wait moved from delay_loop to delay_cycles the go signal comes at
  // cycle 141 and the miss LED at 2154, and the span is still exactly 2013:
  // REACT_TIMEOUT was already a CYCLE count, so the deadline did not move and
  // only the pseudo random wait in front of it did. The go signal window below
  // stays 20..400, which covers the whole REACT_DELAY_MIN + REACT_DELAY_MASK
  // spread of 64..319 cycles plus the seed and LFSR work around it.
  task automatic check_reaction();
    int base;
    int deadline;
    int nibble;
    int elapsed;
    int go_cyc;
    int miss_cyc;

    key_in = 4'h0;
    start_demo("reaction");
    while ((mmio_ledr != 10'h020) && (cyc < 1000)) step_cycles(1);
    expect_hex("run 1 go signal", mmio_ledr, 10'h020);
    expect_range("run 1 go signal cycle", cyc, 20, 400);
    expect_hex("run 1 go signal is the last LEDR write", ledr_val[ledr_n-1],
               10'h020);
    go_cyc = ledr_cyc[ledr_n-1];

    while ((mmio_ledr != 10'h001) && (cyc < 8000)) step_cycles(1);
    expect_hex("run 1 timeout result", mmio_ledr, 10'h001);
    // The span from the go signal to the miss LED must be REACT_TIMEOUT cycles
    // (2000 in the simulation build) plus only the few instructions that read
    // CYCLE one last time and drive LEDR. A poll-count timeout would have made
    // this span depend on the per-iteration cost, which is the bug this pins.
    miss_cyc = ledr_cyc[ledr_n-1];
    expect_range("run 1 timeout span", miss_cyc - go_cyc, 2000, 2060);

    key_in = 4'h0;
    start_demo("reaction");
    while ((mmio_ledr != 10'h020) && (cyc < 1000)) step_cycles(1);
    expect_hex("run 2 go signal", mmio_ledr, 10'h020);

    base   = hex_n;
    key_in = 4'h1;
    while ((mmio_ledr != 10'h3FF) && (cyc < 3000)) step_cycles(1);
    expect_hex("run 2 press result", mmio_ledr, 10'h3FF);

    // hold the key until the six elapsed digits have been written out
    deadline = cyc + 800;
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

  // uart_hello: the banner once, then "count <8 hex digits>" lines forever,
  // with the count's low bits mirrored on LEDR so the board shows life without
  // a serial adapter. Line time dominates the run: at the UART_DIV of 16 above
  // a character is 160 cycles, so the 32 character banner is 5120 cycles and
  // each 16 character count line is 2560. Banner plus three lines is 12800
  // cycles of pure wire time before any program overhead; measured, the third
  // count line finishes decoding at cycle 13266, so the 466 cycles on top of
  // the wire time are the whole cost of the program plus three UART_DELAY
  // waits of 64 cycles each. The 20000 cycle budget is 50 percent above the
  // measurement.
  task automatic check_uart_hello();
    int p;
    int val[3];

    start_demo("uart_hello");
    uart_capture = 1'b1;
    // four line ends means the banner plus three count lines
    while ((rx_crlf_count() < 4) && (cyc < 20000)) step_cycles(1);
    uart_capture = 1'b0;
    $display("demo uart_hello: %0d bytes by cycle %0d: %s", uart_rx_n, cyc,
             rx_text());

    if (rx_crlf_count() < 4)
      fail("uart lines in 20000 cycles", $sformatf("%0d", rx_crlf_count()), "4");

    // the banner arrives exactly once, and it arrives first
    if (rx_count(UART_BANNER) != 1)
      fail("banner occurrences", $sformatf("%0d", rx_count(UART_BANNER)), "1");
    if (!rx_match(0, UART_BANNER))
      fail("banner position", $sformatf("%0d", rx_find(UART_BANNER, 0)), "0");
    if (!rx_crlf_at(UART_BANNER.len()))
      fail("banner ending", "no crlf", "crlf");

    // three count lines follow it, each carrying the next value
    p = UART_BANNER.len() + 2;
    for (int i = 0; i < 3; i++) begin
      if (!rx_match(p, UART_COUNT))
        fail($sformatf("count line %0d prefix", i),
             $sformatf("byte %0d of the stream", p), UART_COUNT);
      val[i] = rx_hex8(p + UART_COUNT.len());
      if (val[i] < 0)
        fail($sformatf("count line %0d value", i), "not eight hex digits",
             "eight hex digits");
      if (!rx_crlf_at(p + UART_COUNT.len() + 8))
        fail($sformatf("count line %0d ending", i), "no crlf", "crlf");
      p = p + UART_COUNT.len() + 10;
    end
    expect_hex("first count value", val[0], 32'd0);
    expect_hex("second count value", val[1], val[0] + 1);
    expect_hex("third count value", val[2], val[1] + 1);

    // LEDR mirrors the same counts, written just before each line goes out
    if (ledr_n < 3)
      fail("LEDR writes", $sformatf("%0d", ledr_n), "3 or more");
    // The LEDR write for the next count happens while the previous line is
    // still going out, so only the writes are checked here, not what LEDR
    // happens to hold at the moment the capture stops.
    for (int i = 0; i < 3; i++)
      expect_hex($sformatf("LEDR write %0d", i), ledr_val[i], i);
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
    check_uart_hello();

    $display("PASS: demo_tb");
    $finish;
  end

endmodule
