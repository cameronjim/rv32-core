// de1_soc_tb: board level testbench for de1_soc_top running the committed
// switch_mirror image. Drives the raw board pins, checks LEDR and the active
// low HEX pins follow SW, and checks a KEY3 reset restarts the program.

`timescale 1ns / 1ps

module de1_soc_tb;

  localparam int SEG_WIDTH = 7;

  // active high segment patterns, the same table the demo programs carry
  localparam logic [SEG_WIDTH-1:0] SEG_0 = 7'h3F;
  localparam logic [SEG_WIDTH-1:0] SEG_1 = 7'h06;
  localparam logic [SEG_WIDTH-1:0] SEG_2 = 7'h5B;
  localparam logic [SEG_WIDTH-1:0] SEG_5 = 7'h6D;
  localparam logic [SEG_WIDTH-1:0] SEG_8 = 7'h7F;
  localparam logic [SEG_WIDTH-1:0] SEG_A = 7'h77;
  localparam logic [SEG_WIDTH-1:0] SEG_BLANK = 7'h00;

  // Every budget below counts CLOCK_50 cycles, which is what step_cycles
  // advances. de1_soc_top divides CLOCK_50 by two, so the CPU only steps on
  // every other one and each budget is twice what the work actually needs.

  // how long switch_mirror may take to pick up a new switch value
  localparam int MIRROR_BUDGET = 1600;
  // six cpu_clk cycles of reset held
  localparam int RESET_CYCLES  = 12;
  // two cpu_clk cycles after reset is released
  localparam int RELEASE_CYCLES = 4;

  logic       CLOCK_50;
  logic [3:0] KEY;
  logic [9:0] SW;
  logic [9:0] LEDR;
  logic [6:0] HEX0;
  logic [6:0] HEX1;
  logic [6:0] HEX2;
  logic [6:0] HEX3;
  logic [6:0] HEX4;
  logic [6:0] HEX5;

  int cyc;

  de1_soc_top u_dut (
    .CLOCK_50 (CLOCK_50),
    .KEY      (KEY),
    .SW       (SW),
    .LEDR     (LEDR),
    .HEX0     (HEX0),
    .HEX1     (HEX1),
    .HEX2     (HEX2),
    .HEX3     (HEX3),
    .HEX4     (HEX4),
    .HEX5     (HEX5)
  );

  initial CLOCK_50 = 1'b0;
  always #5 CLOCK_50 = ~CLOCK_50;

  task automatic step_cycles(input int n);
    for (int i = 0; i < n; i++) begin
      @(posedge CLOCK_50);
      #2;
      cyc = cyc + 1;
    end
  endtask

  task automatic fail(input string what, input string got, input string exp);
    $display("FAIL: de1_soc_tb: %s: got %s expected %s (cycle %0d)",
             what, got, exp, cyc);
    $fatal(1);
  endtask

  task automatic expect_pin(input string what, input logic [31:0] got,
                            input logic [31:0] exp);
    if (got !== exp) fail(what, $sformatf("0x%0h", got), $sformatf("0x%0h", exp));
  endtask

  // Poll rather than sampling a fixed cycle: the input synchronizers add
  // latency, the program refreshes on its own schedule, and LEDR is written
  // before the three digits. The inverses land in 7 bit variables first
  // because ~ takes its width from the context it is used in.
  task automatic wait_mirror(input string what,
                             input logic [9:0] val,
                             input logic [SEG_WIDTH-1:0] d0,
                             input logic [SEG_WIDTH-1:0] d1,
                             input logic [SEG_WIDTH-1:0] d2,
                             input int budget);
    logic [SEG_WIDTH-1:0] p0;
    logic [SEG_WIDTH-1:0] p1;
    logic [SEG_WIDTH-1:0] p2;
    int n;

    p0 = ~d0;
    p1 = ~d1;
    p2 = ~d2;
    n  = 0;
    while (!((LEDR === val) && (HEX0 === p0) && (HEX1 === p1) &&
             (HEX2 === p2)) && (n < budget)) begin
      step_cycles(1);
      n = n + 1;
    end

    expect_pin($sformatf("%s LEDR pins", what), LEDR, val);
    expect_pin($sformatf("%s HEX0 pins", what), HEX0, p0);
    expect_pin($sformatf("%s HEX1 pins", what), HEX1, p1);
    expect_pin($sformatf("%s HEX2 pins", what), HEX2, p2);
  endtask

  // unused displays stay dark, so every segment pin sits high
  task automatic expect_unused_dark(input string what);
    logic [SEG_WIDTH-1:0] dark;
    dark = ~SEG_BLANK;
    expect_pin($sformatf("%s HEX3 pins", what), HEX3, dark);
    expect_pin($sformatf("%s HEX4 pins", what), HEX4, dark);
    expect_pin($sformatf("%s HEX5 pins", what), HEX5, dark);
  endtask

  // press and release KEY3, the board reset button (pressed pulls the pin low)
  task automatic pulse_reset();
    KEY[3] = 1'b0;
    step_cycles(RESET_CYCLES);
    // reset reached the peripherals if the LED register cleared
    expect_pin("LEDR while reset held", LEDR, 10'h000);
    expect_pin("pc while reset held", u_dut.u_cpu.pc, 32'h0000_0000);
    KEY[3] = 1'b1;
    step_cycles(RELEASE_CYCLES);
  endtask

  initial begin
    $dumpfile("sim/build/de1_soc_tb.vcd");
    $dumpvars(0, de1_soc_tb);

    cyc    = 0;
    KEY    = 4'b1111;
    SW     = 10'h000;

    // power-on reset. The synchronizer flops start unknown, so the first two
    // cpu_clk edges carry X on rst_n; holding KEY3 down settles them.
    pulse_reset();

    SW = 10'h2A5;
    wait_mirror("SW 0x2A5", 10'h2A5, SEG_5, SEG_A, SEG_2, MIRROR_BUDGET);
    expect_unused_dark("SW 0x2A5");
    $display("de1_soc_tb: mirrored 0x2A5 at cycle %0d", cyc);

    SW = 10'h081;
    wait_mirror("SW 0x081", 10'h081, SEG_1, SEG_8, SEG_0, MIRROR_BUDGET);
    expect_unused_dark("SW 0x081");
    $display("de1_soc_tb: mirrored 0x081 at cycle %0d", cyc);

    // mid-run reset: hold KEY3 down, change the switches, then check the
    // program comes back up and mirrors the new value
    SW = 10'h155;
    pulse_reset();
    wait_mirror("post reset SW 0x155", 10'h155, SEG_5, SEG_5, SEG_1,
                MIRROR_BUDGET);
    expect_unused_dark("post reset SW 0x155");
    $display("de1_soc_tb: restarted and mirrored 0x155 at cycle %0d", cyc);

    $display("PASS: de1_soc_tb");
    $finish;
  end

endmodule
